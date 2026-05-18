#!/usr/bin/env tclsh

package require Tk

namespace eval ::pino {
	variable appDir [file normalize [file dirname [info script]]]
	variable root [file normalize [file join $appDir ..]]
	variable runtime [file join $root tcltk]
}

proc ::pino::hasArg {name} {
	expr {[lsearch -exact $::argv $name] >= 0}
}

if {[::pino::hasArg "--check"]} {
	puts "Pino UI runtime OK"
	puts "Tcl [info patchlevel]"
	puts "Tk [package provide Tk]"
	destroy .
	exit 0
}

wm title . "Pino"
wm minsize . 420 260
catch {ttk::style theme use vista}

set main [ttk::frame .main -padding 18]
grid $main -sticky nsew
grid columnconfigure . 0 -weight 1
grid rowconfigure . 0 -weight 1
grid columnconfigure $main 1 -weight 1

ttk::label $main.title -text "Pino" -font TkHeadingFont
ttk::label $main.status -text "Ready"
ttk::separator $main.separator -orient horizontal
ttk::label $main.repositoryLabel -text "Repository"
ttk::label $main.repository -text $::pino::root
ttk::label $main.runtimeLabel -text "Runtime"
ttk::label $main.runtime -text "Tcl [info patchlevel] / Tk [package provide Tk]"
ttk::button $main.close -text "Close" -command {destroy .}

grid $main.title -row 0 -column 0 -columnspan 2 -sticky w
grid $main.status -row 1 -column 0 -columnspan 2 -sticky w -pady {6 16}
grid $main.separator -row 2 -column 0 -columnspan 2 -sticky ew -pady {0 14}
grid $main.repositoryLabel -row 3 -column 0 -sticky nw -padx {0 12} -pady {0 8}
grid $main.repository -row 3 -column 1 -sticky new -pady {0 8}
grid $main.runtimeLabel -row 4 -column 0 -sticky nw -padx {0 12}
grid $main.runtime -row 4 -column 1 -sticky new
grid $main.close -row 5 -column 1 -sticky e -pady {28 0}
