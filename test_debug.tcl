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

debugger::add_breakpoint test_basic 4

proc test_for {} {

	for {set i 0} {$i < 5} {incr i} {
		puts $i
	}

}

debugger::add_breakpoint test_for 2

proc test_foreach {} {

	foreach arg [string repeat "1 " 5] {
		puts $arg
	}

}

debugger::add_breakpoint test_foreach 2

proc test_while {} {

	set count 0

	while {$count < 5} {
		puts "count = $count"
		incr count
	}

}

debugger::add_breakpoint test_while 4

proc test_if {} {

	if {1 == 0} {
		puts "wtf?"
	} elseif {1 == 1} {
		puts "true"
	} else {
		puts "check code"
	}

}

debugger::add_breakpoint test_if 2