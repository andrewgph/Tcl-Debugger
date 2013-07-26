source parsetcl.tcl
source debug.tcl

proc test_basic {a b} {

	puts $a

	set test_var 0

	return $b

}

proc test_call {} {

	set res [test_basic hello world]

	puts $res
}

debug::add_breakpoint test_basic 4

proc test_for {} {

	for {set i 0} {$i < 5} {incr i} {
		puts $i
	}

}

debug::add_breakpoint test_for 2

proc test_foreach {} {

	foreach arg [string repeat "1 " 5] {
		puts $arg
	}

}

debug::add_breakpoint test_foreach 2

proc test_foreach_2 {} {

	foreach {arg1 arg2} {1 2 3 4 5 6} {
		puts "foreach body"
		puts $arg1
		puts $arg2
	}

}

debug::add_breakpoint test_foreach_2 2

proc test_while {} {

	set count 0

	while {$count < 5} {
		puts "count = $count"
		incr count
	}

}

debug::add_breakpoint test_while 4

proc test_if_1 {} {

	if {1 == 0} {
		puts "wtf?"
	} elseif {1 == 1} {
		puts "true"
	} else {
		puts "check code"
	}

}

debug::add_breakpoint test_if_1 2

proc test_if_2 {} {

	if {1 == 0} {
		puts "wtf?"
	}

}

debug::add_breakpoint test_if_2 2

proc test_if_3 {} {

	if {1 == 0} {
		puts "wtf?"
	} else {
		puts "correct"
	}

}

debug::add_breakpoint test_if_3 2

proc test_switch {} {

	switch -glob -- "hello" {
		"world" {
			puts world
		}
		"hel*" {
			puts hel
		}
		"hello" {
			puts hello
		}
		default {
			puts default
		}
	}

}

debug::add_breakpoint test_switch 2

proc empty_return {} {}

proc test_Sc {} {

	set ls {1}
	set test_var [empty_return]
	if {[llength $ls] == 0 || $test_var == ""} {
		puts empty
	}

}

debug::add_breakpoint test_Sc 3