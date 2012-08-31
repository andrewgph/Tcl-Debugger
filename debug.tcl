namespace eval debugger {

	variable BREAKPOINTS
	variable debug_up_level  0
	variable debug_proc_body ""
	variable debug_repl      0
	variable debug_proc_name ""

	set BREAKPOINTS(procs) {}

}

proc debugger::debug_tree {tree} {
	eval "debug_$tree"
}

proc debugger::debug_Lr {interval text args} {
	return $text
}

proc debugger::debug_Lb {interval text args} {
	return \{$text\}
}

proc debugger::debug_Lq {interval text args} {
	return \"$text\"
}

proc debugger::debug_Sb {interval text args} {
	return "\\$text"
}

proc debugger::debug_Nc {interval text args} {
	return ""
}

proc debugger::debug_Mb {interval text args} {
	foreach a $args {
		append result [eval "debug_$a"]
	}
	return \{$result\}
}

proc debugger::debug_Sv {interval text args} {
	return "\$[eval debug_[lindex $args 0]]"
}

proc debugger::debug_Sa {interval text args} {
	foreach a [lrange $args 1 end] {
		append result [eval "debug_$a"]
	}
	return "\$[eval debug_[lindex $args 0]]($result)"
}

proc debugger::debug_Sc {interval text args} {
	foreach a $args {
		append cmd " " [eval "debug_$a"]
	}
	return ${cmd}
}

proc debugger::debug_Mr {interval text args} {
	foreach a $args {
		append result [eval "debug_$a"]
	}
	return ${result}
}

proc debugger::debug_Mq {interval text args} {
	foreach a $args {
		append result [eval "debug_$a"]
	}
	return \"${result}\"
}

proc debugger::debug_Cd {interval text args} {
	variable BREAKPOINTS
	variable debug_up_level
	variable debug_proc_body
	variable debug_return
	variable debug_proc_name

	if {[lindex $debug_return 0]} {
		return
	}

	set cmd [eval "debug_[lindex $args 0]"]
	set args [lrange $args 1 end]

	set line_number [calculate_line_number $interval $debug_proc_body]

	# Handle control structures
	switch $cmd {
		"if" {
			return [_handle_if_statement $debug_proc_name $line_number $args]
		}
		"switch" {
#			return [_handle_switch_statement $debug_proc_name $line_number $proc_args]
			return [debug_repl $debug_proc_name $line_number $cmd $args]
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
			set debug_return [list 1 $res]
			return $res
		}
		"vwait" -
		"after" {
			puts "DEBUG: don't know what to do with proc_name $proc_name - will attempt evaluation"
			return [debug_repl $debug_proc_name $line_number $cmd $args]
		}
		default {
			# Handle procs that can be stepped into. Check that the
			# proc isn't a tcl command that can't be stepped into.
			if {[lsearch [info commands] $cmd] == -1} {
				return [debug_repl $debug_proc_name $line_number $cmd $args $proc_name]
			} else {
				return [debug_repl $debug_proc_name $line_number $cmd $args]
			}
		}
	}
}

proc debugger::_handle_if_statement {proc_name line_number proc_args} {

	puts $proc_args

	set if_condition  [lindex $proc_args 0]
	set if_result     [lindex $proc_args 1]
	set check_command [eval debug_$if_condition]

	# Check what the if_condition evaluated to in the proc context
	# If necessary loop through elseif and else statements
	set check [debug_repl $proc_name $line_number $check_command {} "" 0 "if"]
	if {$check} {
		return [eval "debug_$if_result"]
	}

	set proc_args [lrange $proc_args 2 end]

	# Loop through the elseif statements
	for {set i 0} {$i < [expr {[llength $proc_args]-2}]} {set i [expr $i+3]} {
		set elseif_condition [lindex $proc_args [expr {$i+1}]]
		set elseif_result    [lindex $proc_args [expr {$i+2}]]

		set check_command [eval debug_$elseif_condition]
		set check [debug_repl $proc_name $line_number $check_command {} "" 0 "elseif"]
		if {$check} {
			return [eval "debug_$elseif_result"]
		}
	}

	# If we're at this stage, apply the else clause
	return [eval "debug_[lindex $proc_args end]"]

}

# Currently there's a problem with the parsetcl handling of switch statements
# The parsing doesn't parse the switch conditions
# for now, we just evaluate the switch statement as a whole
# TODO! Fix the parsetcl parsing of switch statements and update this proc
proc debugger::_handle_switch_statement {proc_name line_number proc_args} {
	set switch_args [lrange $proc_args 0 end-1]
	set switch_body [lindex $proc_args end]

	set switch_stmt "switch "

	foreach arg $switch_args {
		append switch_stmt [eval "debug_$arg"] " "
	}

	append switch_stmt [eval "debug_$switch_body"] " "

	return
}

proc debugger::_handle_while_statement {proc_name line_number proc_args} {

	set while_condition [lindex $proc_args 0]
	set while_body      [lindex $proc_args 1]

	set check_command [eval "debug_$while_condition"]

	while {[debug_repl $proc_name $line_number $check_command {} "" 0 "while"]} {
		set ret   [eval "debug_$while_body"]
	}

	return $ret

}

proc debugger::_handle_for_statement {proc_name line_number proc_args} {

	set for_init  [lindex $proc_args 0]
	set for_check [eval "debug_[lindex $proc_args 1]"]
	set for_iter  [lindex $proc_args 2]
	set for_body  [lindex $proc_args 3]

	for {eval "debug_$for_init"} {[debug_repl $proc_name $line_number $for_check {} "" 0 "for"]} {eval "debug_$for_iter"} {
		set ret [eval "debug_$for_body"]
	}

	return $ret
}

proc debugger::_handle_foreach_statement {proc_name line_number proc_args} {

	variable debug_up_level

	set foreach_arg  [lindex $proc_args 0]
	set foreach_list [lindex $proc_args 1]
	set foreach_body [lindex $proc_args 2]

	set up_level [expr {[info level]-$debug_up_level}]

	set ls [eval "debug_$foreach_list"]

	foreach elem $ls {

		set arg [eval "debug_$foreach_arg"]
		set arg_command "set $arg $elem"
		uplevel $up_level $arg_command

		set ret [eval "debug_$foreach_body"]
	}

	return $ret
}

proc debugger::debug_Rs {interval text args} {
	variable debug_return

	foreach a $args {
		if {[lindex $debug_return 0]} {
			break;
		}
		eval "debug_$a"
	}

	return [lindex $debug_return 1]

}

proc debugger::calculate_line_number {interval string} {
	return [expr {[regexp -all "\n" [string range $string 0 [lindex $interval 0]]]+1}]
}

proc debugger::debug_repl {proc_name line_number cmd args {step_into_proc ""} {is_return 0} {control_stmt ""}} {

	variable BREAKPOINTS
	variable debug_up_level
	variable debug_repl

	# Check whether we need to break on the line
	if {[info exists BREAKPOINTS($proc_name,lines)] &&
		[lsearch $BREAKPOINTS($proc_name,lines) $line_number] > -1} {
		set debug_repl 1
	}

	# Evaluate all the arguments for the command
	set cmd "$cmd "
	foreach a $args {
		append cmd [eval "debug_$a"] " "
	}

	# If it's a control statement, prefix the command display with the
	# control structure
	if {$control_stmt != ""} {
		set display_cmd "$control_stmt $cmd"
		set cmd "expr $cmd"
	} else {
		set display_cmd $cmd
	}

	set up_level [expr {[info level]-$debug_up_level}]

	if {$debug_repl} {
		puts "line $line_number: $display_cmd"
		set get_user_input 1
		while {$get_user_input} {
			puts -nonewline ">"
			flush stdout
			gets stdin user_command

			switch -glob -- $user_command {
				"continue" {
					set debug_repl 0
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
					if {$debug_up_level > 1} {
						set up_proc [uplevel $up_level {info level [expr {[info level]-1}]}]
						lappend BREAKPOINTS(procs) $up_proc
						lappend BREAKPOINTS($step_into_proc,lines) 0
					}
				}
				"add_breakpoint *" {
					set words [regexp -inline -all -- {\S+} $user_command]
					if {[llength $words] != 3} {
						puts "Usage: add_breakpoint proc_name line_number"
						continue
					}
					set breakpoint_proc_name   [lindex $words 1]
					set breakpoint_line_number [lindex $words 2]
					debugger::add_breakpoint $breakpoint_proc_name $breakpoint_line_number
				}
				"remove_breakpoint *" {
					set words [regexp -inline -all -- {\S+} $user_command]
					if {[llength $words] != 3} {
						puts "Usage: remove_breakpoint proc_name line_number"
						continue
					}
					set breakpoint_proc_name   [lindex $words 1]
					set breakpoint_line_number [lindex $words 2]
					debugger::remove_breakpoint $breakpoint_proc_name $breakpoint_line_number
				}
				default {
					if {[catch {
						uplevel $up_level $user_command
					} msg]} {
						puts $msg
					}
				}
			}
		}
	}

	if {$is_return} {
		set ret_command {set ret }
		set ret_command [append ret_command "[string range $cmd 6 end]"]
	} else {
		set ret_command "set ret \[$cmd\]"
	}
	set ret [uplevel $up_level $ret_command]
	return $ret

}

proc debugger::debug_proc {name} {

	variable BREAKPOINTS
	variable debug_up_level [expr {[info level]-1}]
	variable debug_proc_body
	variable debug_repl
	variable debug_return {0 {}}
	variable debug_proc_name $name

	if {[lsearch $BREAKPOINTS(procs) $name] == -1} {
		return {0 {}}
	}

	# Set debug_repl if there is a breakpoint at line 0. Otherwise the
	# breakpoint will be reached at the appropriate line.
	if {[lsearch $BREAKPOINTS($name,lines) 0] > -1} {
		set debug_repl 1
	}

	set body_commands [split [info body $name] "\n"]

	# Remove the first 2 lines of the proc, which are the lines used
	# to call this debug_proc
	set body_commands [lrange $body_commands 2 end]
	set debug_proc_body [join $body_commands "\n"]
	set body_parsed [parsetcl::simple_parse_script $debug_proc_body]

	# Traverse the parse of the proc body
	# Halting at breakpoints
	# The debug_return variable should be set during the traversal
	set ret [debug_tree $body_parsed]

	return [list 1 $ret]
}

proc debugger::add_breakpoint {proc_name line_number} {
	variable BREAKPOINTS

	if {![string is integer $line_number] && $line_number > 0} {
		error "debugger::add_breakpoint: $line_number needs to be an integer greater than 0"
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

proc debugger::remove_breakpoint {proc_name line_number} {
	variable BREAKPOINTS

	if {[info exists BREAKPOINTS($proc_name,lines)] &&
		[lsearch $BREAKPOINTS($proc_name,lines) $line_number] > -1} {
		set BREAKPOINTS($proc_name,lines) [lsearch -inline -all -not -exact $BREAKPOINTS($proc_name,lines) $line_number]
		if {$BREAKPOINTS($proc_name,lines) == {}} {
			set BREAKPOINTS(procs) [lsearch -inline -all -not -exact $BREAKPOINTS(procs) $proc_name]
		}
	}
}

rename proc _proc
_proc proc {name args body} {
	 set debug "set debug_res \[debugger::debug_proc $name\]; if {\[lindex \$debug_res 0\]} {return \[lindex \$debug_res 1\]};\n"
	 append debug $body
	 _proc $name $args $debug
}