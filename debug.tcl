################################################################################
# debug.tcl
#
# Defines the debug procs used to interactively debug a tcl script
#
# The proc command is renamed at the end of this script to prepend a
# breakpoint check at the beginning of each proc call.
#
# If a breakpoint is set for a proc, the proc body is parsed by
# parsetcl.tcl and each command is checked for breakpoints. If a
# breakpoint is reached, debug::debug_repl is used to interactively
# step through code execution from that point.
#
# Depends upon parsetcl.tcl, which needs to be sourced before this script.
################################################################################

namespace eval debug {

	variable BREAKPOINTS
	variable PROCFILES
	variable QUEUE

	set BREAKPOINTS(procs) {}
	set QUEUE(count) 0

}

################################################################################
# The following procs are used to evaluated the parsed tcl script
################################################################################

proc debug::debug_tree {tree} {
	eval "debug_$tree"
}

proc debug::debug_Lr {interval text args} {
	return $text
}

proc debug::debug_Lb {interval text args} {
	return \{$text\}
}

proc debug::debug_Lq {interval text args} {
	return \"$text\"
}

proc debug::debug_Sb {interval text args} {
	return "\\$text"
}

proc debug::debug_Nc {interval text args} {
	return ""
}

proc debug::debug_Mb {interval text args} {
	foreach a $args {
		append result [eval "debug_$a"]
	}
	return \{$result\}
}

proc debug::debug_Sv {interval text args} {
	return "\$[eval debug_[lindex $args 0]]"
}

proc debug::debug_Sa {interval text args} {
	foreach a [lrange $args 1 end] {
		append result [eval "debug_$a"]
	}
	return "\$[eval debug_[lindex $args 0]]($result)"
}

proc debug::debug_Sc {interval text args} {
	foreach a $args {
		append cmd " " [eval "debug_$a"]
	}

	# String trim the command in case the eval returned {}
	# We need to do this to remove the space appended to cmd
	set cmd [string trim $cmd]

	return \{$cmd\}

}

proc debug::debug_Mr {interval text args} {
	foreach a $args {
		append result [eval "debug_$a"]
	}
	return ${result}
}

proc debug::debug_Mq {interval text args} {
	foreach a $args {
		append result [eval "debug_$a"]
	}
	return \"${result}\"
}

# Evaluate commands in the parsed tcl script
proc debug::debug_Cd {interval text args} {
	variable BREAKPOINTS
	variable QUEUE

	set queue_item $QUEUE(count)
	set debug_up_level  $QUEUE($queue_item,up_level)
	set debug_proc_body $QUEUE($queue_item,proc_body)
	set debug_return    $QUEUE($queue_item,return)
	set debug_proc_name $QUEUE($queue_item,proc_name)

	# Don't evaluate the command if we've already encountered a return
	# statement in the script.
	if {[lindex $debug_return 0]} {
		return
	}

	set cmd [eval "debug_[lindex $args 0]"]
	set args [lrange $args 1 end]

	# Get the line number in the proc, based upon the interval in the
	# parsed tcl command and the proc body string.
	set line_number [calculate_line_number $interval $debug_proc_body]

	# Handle control structures
	switch $cmd {
		"if" {
			return [_handle_if_statement $debug_proc_name $line_number $args]
		}
		"switch" {
			return [_handle_switch_statement $debug_proc_name $line_number $args]
		}
		"while" {
			return [_handle_while_statement $debug_proc_name $line_number $args]
		}
		"for" {
			return [_handle_for_statement $debug_proc_name $line_number $args]
		}
		"foreach" {
			return [_handle_foreach_statement $debug_proc_name $line_number $args]
		}
		"return" {
			foreach a $args {
				lappend proc_args [eval "debug_$a"]
			}
			set res [debug_repl $debug_proc_name $line_number $cmd $args "" 1]
			set QUEUE($queue_item,return) [list 1 $res]
			return $res
		}
		"vwait" -
		"after" {
			show_line "DEBUG: don't know what to do with proc_name $proc_name - will attempt evaluation"
			return [debug_repl $debug_proc_name $line_number $cmd $args]
		}
		default {
			# Handle procs that can be stepped into. Check that the
			# proc isn't a tcl command that can't be stepped into.
			if {[lsearch [info commands] $cmd] == -1} {
				return [debug_repl $debug_proc_name $line_number $cmd $args $cmd]
			} else {
				return [debug_repl $debug_proc_name $line_number $cmd $args]
			}
		}
	}
}

proc debug::_handle_if_statement {proc_name line_number proc_args} {

	set if_condition  [lindex $proc_args 0]
	set if_result     [lindex $proc_args 1]
	set check_command [eval debug_$if_condition]

	# Check what the if_condition evaluated to in the proc context
	# If necessary loop through elseif and else statements
	set check [debug_repl $proc_name $line_number $check_command {} "" 0 "if $check_command"]
	if {$check} {
		return [eval "debug_$if_result"]
	}

	set proc_args [lrange $proc_args 2 end]

	# Loop through the elseif statements
	while {[lindex $proc_args 0 2] == "elseif"} {
		set elseif_condition [lindex $proc_args 1]
		set elseif_result    [lindex $proc_args 2]

		set check_command [eval debug_$elseif_condition]
		set check [debug_repl $proc_name $line_number $check_command {} "" 0 "elseif $check_command"]
		if {$check} {
			return [eval "debug_$elseif_result"]
		}
		set proc_args [lrange $proc_args 3 end]
	}

	# If there are two arguments left, evaluate them as an else clause
	# Otherwise return nothing
	if {[llength $proc_args] == 2} {
		return [eval "debug_[lindex $proc_args end]"]
	} else {
		return
	}

}

proc debug::_handle_switch_statement {proc_name line_number proc_args} {

	# Identify the argument index for the last option passed to the
	# switch command.
	for {set i 0} {$i < [llength $proc_args]} {incr i} {
		if {![string match "-*" [lindex [lindex $proc_args $i] 2]]} {
			break
		}
	}

	set options_args   [lrange $proc_args 0 $i-1]
	set switch_arg     [lindex $proc_args $i]
	set condition_args [lrange $proc_args $i+1 end]

	set switch_stmt "switch "

	foreach arg $options_args {
		append switch_stmt [eval "debug_$arg"] " "
	}

	# Use the debug_repl to get the value of evaluating the switch arg
	# in the uplevel of the proc being debugged. We need this as we're
	# going to eval the switch statement in the current context, so
	# any variable references need to be evaluated first.
	set switch_arg_expr "set ret [eval debug_$switch_arg]"
	set switch_arg_val [debug_repl $proc_name $line_number $switch_arg_expr {}]

	append switch_stmt $switch_arg_val " "
	set switch_display $switch_stmt

	foreach {pattern condition} $condition_args {
		append switch_stmt [eval "debug_$pattern"] " "
		append switch_stmt {{set ret [eval debug_$condition]}} " "
	}

	# Use a dummy command here to trigger the debug_repl when the
	# switch command is evaluated.

	# We need a dummy command because the switch statement will
	# actually by evaluated at this uplevel.

	# The switch command is evaluated at this uplevel so that we can
	# trigger breakpoints on any condition bodies that are evaluated
	# as a result of the switch command.

	debug_repl $proc_name $line_number true {} "" 0 $switch_display

	return [eval $switch_stmt]

}

proc debug::_handle_while_statement {proc_name line_number proc_args} {

	set while_condition [lindex $proc_args 0]
	set while_body      [lindex $proc_args 1]

	set check_command [eval "debug_$while_condition"]

	while {[debug_repl $proc_name $line_number $check_command {} "" 0 "while $check_command"]} {
		set ret   [eval "debug_$while_body"]
	}

	return $ret

}

proc debug::_handle_for_statement {proc_name line_number proc_args} {

	set for_init  [lindex $proc_args 0]
	set for_check [eval "debug_[lindex $proc_args 1]"]
	set for_iter  [lindex $proc_args 2]
	set for_body  [lindex $proc_args 3]

	set ret {}

	# Use the debug_repl to check the command every time the for check
	# condition is evaluated.
	for {eval "debug_$for_init"} {[debug_repl $proc_name $line_number $for_check {} "" 0 "for $for_check"]} {eval "debug_$for_iter"} {
		set ret [eval "debug_$for_body"]
	}

	return $ret
}

proc debug::_handle_foreach_statement {proc_name line_number proc_args} {

	variable QUEUE

	set queue_item $QUEUE(count)
	set debug_up_level  $QUEUE($queue_item,up_level)

	set foreach_arg  [lindex $proc_args 0]
	set foreach_list [lindex $proc_args 1]
	set foreach_body [lindex $proc_args 2]

	set up_level [expr {[info level]-$debug_up_level}]

	set ls [eval "debug_$foreach_list"]
	set arg [eval "debug_$foreach_arg"]
	set arg_count [uplevel $up_level "expr {\[llength $ls]/\[llength $arg\]}"]

	# Artificially loop through the list, setting the arguments as we go
	# Need to handle the case where the argument is a list of arguments
	# so we uplevel statements to set the arguments from values in the list.
	for {set i 0} {$i < $arg_count} {incr i} {
		set start_idx [uplevel $up_level "expr {$i * \[llength $arg\]}"]
		set end_idx [uplevel $up_level "expr {($i+1) * \[llength $arg\] - 1}"]

		set arg_command "foreach $arg \[lrange $ls $start_idx $end_idx\] {}"

		# Use a dummy command to show the debug_repl when the
		# arguments are being set in the foreach loop
		debug_repl $proc_name $line_number true {} "" 0 "foreach $arg $ls"

		uplevel $up_level $arg_command
		set ret [eval "debug_$foreach_body"]
	}

	return $ret
}

# The Rs element in the parsed tcl script it the outer wrapper element
# for the whole script.
proc debug::debug_Rs {interval text args} {
	variable QUEUE

	set queue_item $QUEUE(count)

	foreach a $args {
		# Stop evaluating expresions in the script if this debug point
		# has a return value.
		if {[lindex $QUEUE($queue_item,return) 0]} {
			break;
		}
		eval "debug_$a"
	}

	return [lindex $QUEUE($queue_item,return) 1]

}

# Utility proc to calculate the line number of an interval within a
# string.
proc debug::calculate_line_number {interval string} {
	return [expr {[regexp -all "\n" [string range $string 0 [lindex $interval 0]]]+1}]
}

proc debug::debug_repl {proc_name line_number cmd args {step_into_proc ""} {is_return 0} {control_stmt ""}} {

	variable BREAKPOINTS
	variable QUEUE
	variable PROCFILES

	# Get the current queue item
	set queue_item $QUEUE(count)

	# Check whether we need to break on the line.
	if {[info exists BREAKPOINTS($proc_name,lines)] &&
		[lsearch $BREAKPOINTS($proc_name,lines) $line_number] > -1} {
		set QUEUE($queue_item,debug_repl) 1
	}

	# Evaluate all the arguments for the command
	set cmd "$cmd "
	foreach a $args {
		append cmd [eval "debug_$a"] " "
	}

	# If it's a control statement, prefix the command display with the
	# control structure
	if {$control_stmt != ""} {
		set display_cmd $control_stmt
		set cmd "expr $cmd"
	} else {
		set display_cmd $cmd
	}

	set up_level [expr {[info level]-$QUEUE($queue_item,up_level)}]

	if {[info exists PROCFILES($proc_name)]} {
		set filename [file tail $PROCFILES($proc_name)]
	} else {
		set filename ""
	}

	if {$QUEUE($queue_item,debug_repl)} {
		show_line "line $line_number: $display_cmd"
		set get_user_input 1
		while {$get_user_input} {
			set user_command [_get_repl_input $filename $proc_name $line_number]

			switch -glob -- $user_command {
				"help" {
					show_repl_usage
				}
				"continue" {
					set QUEUE($queue_item,debug_repl) 0
					set get_user_input 0
				}
				"step" {
					set get_user_input 0
				}
				"step_into" {
					if {$step_into_proc != ""} {
						lappend BREAKPOINTS(procs) $step_into_proc
						lappend BREAKPOINTS($step_into_proc,lines) 0
						set get_user_input 0
					}
				}
				"step_out" {
					# TODO! step_out needs to be implemented. This wont
					# currently work. As the calling proc isn't
					# necessarily being evaluated by the debug_proc May
					# need to evaluate all procs in the debug_proc, so we
					# can backtrack to the calling proc.
					if {$QUEUE($queue_item,up_level) > 1} {
						set up_proc [uplevel $up_level {info level [expr {[info level]-1}]}]
						lappend BREAKPOINTS(procs) $up_proc
						lappend BREAKPOINTS($step_into_proc,lines) 0
					}
				}
				"add_breakpoint *" {
					set words [regexp -inline -all -- {\S+} $user_command]
					if {[llength $words] != 3} {
						show_line "Usage: add_breakpoint proc_name line_number"
						continue
					}
					set breakpoint_proc_name   [lindex $words 1]
					set breakpoint_line_number [lindex $words 2]
					debug::add_breakpoint $breakpoint_proc_name $breakpoint_line_number
				}
				"remove_breakpoint *" {
					set words [regexp -inline -all -- {\S+} $user_command]
					if {[llength $words] != 3} {
						show_line "Usage: remove_breakpoint proc_name line_number"
						continue
					}
					set breakpoint_proc_name   [lindex $words 1]
					set breakpoint_line_number [lindex $words 2]
					debug::remove_breakpoint $breakpoint_proc_name $breakpoint_line_number
				}
				"filepath" {
					if {[info exists PROCFILES($proc_name)]} {
						show_line $PROCFILES($proc_name)
					} else {
						show_line "not available"
					}
				}
				"parray *" {
					# Rewrite puts and parray proc requests to val
					# displays, so that the show_line proc can display
					# the value.
					set array_name [string trim [string range $user_command [string wordend $user_command 0] end]]
					set user_command [subst {set debug_parray_c19d5f864c9d2 {}; foreach name \[array names $array_name\] {append debug_parray_c19d5f864c9d2 "${array_name}(\$name) = \$${array_name}(\$name)" "\n"}; set debug_parray_c19d5f864c9d2}]
					_repl_up_level $up_level $user_command
				}
				"puts *" {
					set user_command "set debug_puts_c19d5f864c9d2 [string range $user_command [string wordend $user_command 0] end]"
					_repl_up_level $up_level $user_command
				}
				default {
					_repl_up_level $up_level $user_command
				}
			}
		}
	}

	# If the command being debugged is a return statement, get the
	# result of the return statement
	if {$is_return} {
		set ret_command {set ret }
		set ret_command [append ret_command "[string range $cmd 6 end]"]
	} else {
		set ret_command "set debug_return_c19d5f864c9d2 \[$cmd\]"
	}
	set ret [uplevel $up_level $ret_command]
	return $ret

}

# Evaluate an expression at a particular up level and show the user
# either the result or the error message
# up_level argument is relative to the calling proc (not this proc)
proc debug::_repl_up_level {up_level user_command} {
	# increment the uplevel to account for this proc
	incr up_level
	if {[catch {
		set val [uplevel $up_level $user_command]
	} msg]} {
		show_line $msg
	} else {
		show_line $val
	}
}

proc debug::show_repl_usage {} {
	show_line "Available commands are:"
	show_line "* step"
	show_line "* continue"
	show_line "* step_into"
	show_line "* add_breakpoint <proc_name> <line_number>"
	show_line "* remove_breakpoint <proc_name> <line_number>"
	show_line "* filepath (shows absolute path of the file that the proc is sourced from)"
	show_line "Anything else is evaluated using uplevel in the context of the proc being debugged."
}

# The proc command is renamed at the end of debug.tcl so that
# debug_proc is evaluated at the beginning of every proc call. This
# allows us to intercept the proc calls, check for breakpoints and
# step through code execution if a breakpoint is set.
proc debug::debug_proc {name} {

	variable BREAKPOINTS
	variable QUEUE

	# Let the proc evaluate as normal if no breakpoints are set in the proc.
	if {[lsearch $BREAKPOINTS(procs) $name] == -1} {
		return {0 {}}
	}

	# Set debug_repl if there is a breakpoint at line 0. Otherwise the
	# breakpoint will be reached at the appropriate line.
	if {[lsearch $BREAKPOINTS($name,lines) 0] > -1} {
		set debug_repl 1
	} else {
		set debug_repl 0
	}

	set body_commands [split [uplevel #0 info body $name] "\n"]

	# Remove any lines at the beginning of the proc which begin with
	# 'set debug_res', these have been added by the debug redefinition
	# of the proc command.
	# TODO is there a better way of adding and removing these lines?
	# This wouldn't play well with anything else that added additional
	# lines to the beginning of the proc (an edge case, but a
	# possibility)
	while {[string match "set debug_res*debug::*debug_proc*" [lindex $body_commands 0]]} {
		set body_commands [lrange $body_commands 1 end]
	}

	# Remove the next line if it's empty, it has also been added by
	# the debug proc command.
	if {[string trim [lindex $body_commands 0]] == ""} {
		set body_commands [lrange $body_commands 1 end]
	}

	# Use parsetcl.tcl to get the parse tree of the tcl script.
	set debug_proc_body [join $body_commands "\n"]
	set body_parsed [parsetcl::simple_parse_script $debug_proc_body]

	# Add the breakpoint to the current queue of active breakpoints
	incr QUEUE(count)
	set queue_count $QUEUE(count)
	set QUEUE($queue_count,up_level)  [expr {[info level]-1}]
	set QUEUE($queue_count,proc_body)  $debug_proc_body
	set QUEUE($queue_count,debug_repl) $debug_repl
	set QUEUE($queue_count,proc_name)  $name
	set QUEUE($queue_count,return)    {0 {}}

	# Traverse the parse of the proc body
	# Halting at breakpoints
	# The QUEUE($queue_count,return) variable should be set during the traversal
	set ret [debug_tree $body_parsed]

	# Decrement the queue count, to remove the item from the queue
	array unset QUEUE "$queue_count,*"
	incr QUEUE(count) -1

	return [list 1 $ret]
}

proc debug::add_breakpoint {proc_name line_number} {
	variable BREAKPOINTS

	if {![string is integer $line_number] && $line_number > 0} {
		error "debug::add_breakpoint: $line_number needs to be an integer greater than 0"
	}

	if {[lsearch $BREAKPOINTS(procs) $proc_name] == -1} {
		lappend BREAKPOINTS(procs) $proc_name
	}

	if {![info exists BREAKPOINTS($proc_name,lines)]} {
		set BREAKPOINTS($proc_name,lines) {}
	}

	if {[lsearch $BREAKPOINTS($proc_name,lines) $line_number] == -1} {
		lappend BREAKPOINTS($proc_name,lines) $line_number
	}

}

proc debug::remove_breakpoint {proc_name line_number} {
	variable BREAKPOINTS

	if {[info exists BREAKPOINTS($proc_name,lines)] &&
		[lsearch $BREAKPOINTS($proc_name,lines) $line_number] > -1} {
		set BREAKPOINTS($proc_name,lines) [lsearch -inline -all -not -exact $BREAKPOINTS($proc_name,lines) $line_number]
		if {$BREAKPOINTS($proc_name,lines) == {}} {
			set BREAKPOINTS(procs) [lsearch -inline -all -not -exact $BREAKPOINTS(procs) $proc_name]
		}
	}
}

proc debug::_breakpoint_commands {input} {

	switch -glob -- $input {
		"add_breakpoint *" {
			set words [regexp -inline -all -- {\S+} $input]
			if {[llength $words] == 3} {
				set breakpoint_proc_name   [lindex $words 1]
				set breakpoint_line_number [lindex $words 2]
				debug::add_breakpoint $breakpoint_proc_name $breakpoint_line_number
			}
		}
		"remove_breakpoint *" {
			set words [regexp -inline -all -- {\S+} $input]
			if {[llength $words] == 3} {
				set breakpoint_proc_name   [lindex $words 1]
				set breakpoint_line_number [lindex $words 2]
				debug::remove_breakpoint $breakpoint_proc_name $breakpoint_line_number
			}
		}
	}
}

# Get user input, either from the debug router or stdin
proc debug::_get_repl_input {filename proc_name line_number} {
	puts -nonewline "$filename:$proc_name:$line_number>"
	flush stdout
	gets stdin repl_input
	return $repl_input
}

proc debug::show_line {line} {
	puts $line
}

# Prepend the debug_proc calls to the proc body
proc debug::make_proc_body {debug_proc name body} {

	set proc_body [subst {set debug_result_c19d5f864c9d2 \[$debug_proc {$name}\];}]
	append proc_body {if {[lindex $debug_result_c19d5f864c9d2 0]} {return [lindex $debug_result_c19d5f864c9d2 1]};
	}
	append proc_body $body

	return $proc_body
}

set proc_defined 0
set iter 1

# Try to define the wrapper for proc Allow the debug wrapper proc to
# rename the proc command arbitrary times. So the debug procs can
# debug themselves.
while {!$proc_defined} {
	set proc_name "[string repeat {_} $iter]proc"
	if {[info commands $proc_name] == ""} {

		set debug_proc "debug::[string repeat {_} $iter]debug_proc"
		rename debug::debug_proc $debug_proc

		rename proc $proc_name
		$proc_name proc {name args body} [subst {
			set ::debug::PROCFILES(\$name) \[file join \[pwd\] \[info script\]\]
			uplevel 1 \[subst {$proc_name {\$name} {\$args} {\[debug::make_proc_body $debug_proc \$name \$body\]}}\]
		}]

		set proc_defined 1
	} else {
		incr iter
	}
}
