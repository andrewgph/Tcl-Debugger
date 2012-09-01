Tcl Dynamic Debugger
==============

A dynamic debugger for Tcl code implemented in Tcl. It uses the [parsetcl.tcl](http://wiki.tcl.tk/9649) script created by Lars Hellström, with some modifcations made to improve parsing of switch statements.

Design
-------------

The debugger renames the proc command so that all proc definitions have a wrapper proc that checks whether any breakpoints have been set for the proc.

If a breakpoint has been set, the proc body is explicitly parsed and each command is evaluated using the uplevel command in the context of the proc being debugged. This allows the debugger to handle control structures and multiline commands.

See the [tcl wiki](http://wiki.tcl.tk/8637) page for more detail on dynamic debuggers in tcl.

Usage
-------------

Add the following to the top of the tcl file you want to debug.

    source parsetcl.tcl
    source debug.tcl

Breakpoints can be added and removed from procs at specific lines with the following procs:

    ot::debug::add_breakpoint example_proc 2
    ot::debug::remove_breakpoint example_proc 2

Once the debug repl has been triggered, the following commands are available:

* step
* continue
* step_into
* add_breakpoint
* remove_breakpoint

The debug repl will evaluate any other input as a tcl command in the context of the proc being debugged.

Acknowledgements
-------------

* The [parsetcl.tcl](http://wiki.tcl.tk/9649) script created by Lars Hellström
