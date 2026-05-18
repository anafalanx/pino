#!/usr/bin/env tclsh

package require Tk

namespace eval ::pino {
	variable appDir [file normalize [file dirname [info script]]]
	if {[info exists ::env(PINO_ROOT)] && $::env(PINO_ROOT) ne ""} {
		variable root [file normalize $::env(PINO_ROOT)]
	} else {
		variable root [file normalize [file join $appDir ..]]
	}
	if {[info exists ::env(PINO_TCLTK)] && $::env(PINO_TCLTK) ne ""} {
		variable runtime [file normalize $::env(PINO_TCLTK)]
	} else {
		variable runtime [file join $root tcltk]
	}
	if {[info exists ::env(PINO_WORKSPACE)] && $::env(PINO_WORKSPACE) ne ""} {
		variable workspace [file normalize $::env(PINO_WORKSPACE)]
	} else {
		variable workspace [pwd]
	}
	variable workspaceVar $workspace
	variable repoStateVar ""
	variable headVar ""
	variable fileCountVar ""
	variable statusVar "Ready"
	variable commitMessageVar ""
	variable changesTree ""
	variable historyTree ""
	variable initButton ""
	variable commitButton ""
}

proc ::pino::hasArg {name} {
	expr {[lsearch -exact $::argv $name] >= 0}
}

proc ::pino::repoDir {} {
	variable workspace
	file join $workspace .pino
}

proc ::pino::repoExists {} {
	file isdirectory [repoDir]
}

proc ::pino::setStatus {message} {
	variable statusVar
	set statusVar $message
}

proc ::pino::setWorkspace {path} {
	variable workspace
	set workspace [file normalize $path]
	refresh
}

proc ::pino::chooseWorkspace {} {
	variable workspace
	set selected [tk_chooseDirectory -initialdir $workspace -mustexist true]
	if {$selected ne ""} {
		setWorkspace $selected
	}
}

proc ::pino::initRepository {} {
	set repo [repoDir]
	if {[file exists $repo]} {
		setStatus "Repository already exists"
		refresh
		return
	}

	foreach dir [list $repo [file join $repo objects] [file join $repo commits] [file join $repo refs]] {
		file mkdir $dir
	}

	set handle [open [file join $repo HEAD] w]
	puts $handle "refs/main"
	close $handle

	set handle [open [file join $repo refs main] w]
	close $handle

	setStatus "Repository initialized"
	refresh
}

proc ::pino::headValue {} {
	set ref [file join [repoDir] refs main]
	if {![file exists $ref]} {
		return ""
	}
	set handle [open $ref r]
	set value [string trim [read $handle]]
	close $handle
	return $value
}

proc ::pino::shouldSkip {name} {
	set skipped {. .. .git .pino tcltk pino.code-workspace}
	expr {[lsearch -exact $skipped $name] >= 0}
}

proc ::pino::scanFiles {} {
	variable workspace
	set files {}
	walkFiles $workspace "" files
	lsort -dictionary $files
}

proc ::pino::walkFiles {dir prefix resultVar} {
	upvar 1 $resultVar result
	foreach entry [glob -nocomplain -directory $dir * .*] {
		set name [file tail $entry]
		if {[shouldSkip $name]} {
			continue
		}
		if {$prefix eq ""} {
			set relative $name
		} else {
			set relative "$prefix/$name"
		}
		if {[file isdirectory $entry]} {
			walkFiles $entry $relative result
		} elseif {[file isfile $entry]} {
			lappend result $relative
		}
	}
}

proc ::pino::refreshChanges {} {
	variable changesTree
	variable fileCountVar
	if {$changesTree eq ""} {
		return
	}
	$changesTree delete [$changesTree children {}]
	set files [scanFiles]
	set fileCountVar "[llength $files] working files"
	if {[llength $files] == 0} {
		return
	}

	if {[repoExists] && [headValue] eq ""} {
		set status "Untracked"
	} elseif {[repoExists]} {
		set status "Working"
	} else {
		set status "File"
	}

	foreach relative [lrange $files 0 199] {
		$changesTree insert {} end -values [list $status $relative]
	}
	if {[llength $files] > 200} {
		$changesTree insert {} end -values [list More "[expr {[llength $files] - 200}] more files"]
	}
}

proc ::pino::refreshHistory {} {
	variable historyTree
	if {$historyTree eq ""} {
		return
	}
	$historyTree delete [$historyTree children {}]
	if {![repoExists]} {
		return
	}
	set head [headValue]
	if {$head ne ""} {
		$historyTree insert {} end -values [list [string range $head 0 11] HEAD]
	}
}

proc ::pino::refresh {} {
	variable workspace
	variable workspaceVar
	variable repoStateVar
	variable headVar
	variable initButton
	variable commitButton
	set workspaceVar $workspace

	if {[repoExists]} {
		set repoStateVar "Repository ready"
		set head [headValue]
		if {$head eq ""} {
			set headVar "No commits"
		} else {
			set headVar $head
		}
		if {$initButton ne ""} {
			$initButton state disabled
		}
	} else {
		set repoStateVar "No repository"
		set headVar ""
		if {$initButton ne ""} {
			$initButton state !disabled
		}
	}
	if {$commitButton ne ""} {
		$commitButton state disabled
	}
	refreshChanges
	refreshHistory
}

if {[::pino::hasArg "--check"]} {
	puts "Pino UI runtime OK"
	puts "Tcl [info patchlevel]"
	puts "Tk [package provide Tk]"
	puts "Workspace $::pino::workspace"
	destroy .
	exit 0
}

wm title . "Pino"
wm minsize . 880 560
catch {ttk::style theme use vista}

ttk::style configure Title.TLabel -font TkHeadingFont

set main [ttk::frame .main -padding 12]
grid $main -sticky nsew
grid columnconfigure . 0 -weight 1
grid rowconfigure . 0 -weight 1
grid columnconfigure $main 0 -weight 1
grid rowconfigure $main 2 -weight 1

ttk::label $main.title -text "Pino" -style Title.TLabel
ttk::label $main.status -textvariable ::pino::statusVar

set toolbar [ttk::frame $main.toolbar]
grid columnconfigure $toolbar 1 -weight 1
ttk::label $toolbar.workspaceLabel -text "Workspace"
ttk::entry $toolbar.workspace -textvariable ::pino::workspaceVar -state readonly
ttk::button $toolbar.open -text "Open" -command ::pino::chooseWorkspace
ttk::button $toolbar.refresh -text "Refresh" -command ::pino::refresh
set ::pino::initButton [ttk::button $toolbar.init -text "Initialize" -command ::pino::initRepository]

grid $toolbar.workspaceLabel -row 0 -column 0 -sticky w -padx {0 8}
grid $toolbar.workspace -row 0 -column 1 -sticky ew -padx {0 8}
grid $toolbar.open -row 0 -column 2 -padx {0 6}
grid $toolbar.refresh -row 0 -column 3 -padx {0 6}
grid $toolbar.init -row 0 -column 4

set body [ttk::panedwindow $main.body -orient horizontal]
set sidebar [ttk::frame $body.sidebar -padding 10]
set notebook [ttk::notebook $body.notebook]
$body add $sidebar -weight 0
$body add $notebook -weight 1

ttk::label $sidebar.repositoryLabel -text "Repository"
ttk::label $sidebar.repository -textvariable ::pino::repoStateVar
ttk::label $sidebar.headLabel -text "Head"
ttk::label $sidebar.head -textvariable ::pino::headVar -wraplength 210
ttk::label $sidebar.filesLabel -text "Files"
ttk::label $sidebar.files -textvariable ::pino::fileCountVar
ttk::label $sidebar.runtimeLabel -text "Runtime"
ttk::label $sidebar.runtime -text "Tcl [info patchlevel] / Tk [package provide Tk]" -wraplength 210

grid $sidebar.repositoryLabel -row 0 -column 0 -sticky w
grid $sidebar.repository -row 1 -column 0 -sticky ew -pady {2 14}
grid $sidebar.headLabel -row 2 -column 0 -sticky w
grid $sidebar.head -row 3 -column 0 -sticky ew -pady {2 14}
grid $sidebar.filesLabel -row 4 -column 0 -sticky w
grid $sidebar.files -row 5 -column 0 -sticky ew -pady {2 14}
grid $sidebar.runtimeLabel -row 6 -column 0 -sticky w
grid $sidebar.runtime -row 7 -column 0 -sticky ew -pady {2 0}

set changes [ttk::frame $notebook.changes -padding 10]
grid columnconfigure $changes 0 -weight 1
grid rowconfigure $changes 0 -weight 1
set ::pino::changesTree [ttk::treeview $changes.tree -columns {status path} -show headings -height 14]
$::pino::changesTree heading status -text "Status"
$::pino::changesTree heading path -text "Path"
$::pino::changesTree column status -width 110 -stretch false
$::pino::changesTree column path -width 520 -stretch true
set changesScroll [ttk::scrollbar $changes.scroll -orient vertical -command "$::pino::changesTree yview"]
$::pino::changesTree configure -yscrollcommand "$changesScroll set"
ttk::label $changes.messageLabel -text "Commit message"
ttk::entry $changes.message -textvariable ::pino::commitMessageVar
set ::pino::commitButton [ttk::button $changes.commit -text "Commit"]

grid $::pino::changesTree -row 0 -column 0 -sticky nsew
grid $changesScroll -row 0 -column 1 -sticky ns
grid $changes.messageLabel -row 1 -column 0 -sticky w -pady {12 4}
grid $changes.message -row 2 -column 0 -sticky ew -pady {0 8}
grid $changes.commit -row 3 -column 0 -sticky e
$notebook add $changes -text "Changes"

set history [ttk::frame $notebook.history -padding 10]
grid columnconfigure $history 0 -weight 1
grid rowconfigure $history 0 -weight 1
set ::pino::historyTree [ttk::treeview $history.tree -columns {commit label} -show headings -height 14]
$::pino::historyTree heading commit -text "Commit"
$::pino::historyTree heading label -text "Label"
$::pino::historyTree column commit -width 140 -stretch false
$::pino::historyTree column label -width 520 -stretch true
set historyScroll [ttk::scrollbar $history.scroll -orient vertical -command "$::pino::historyTree yview"]
$::pino::historyTree configure -yscrollcommand "$historyScroll set"
grid $::pino::historyTree -row 0 -column 0 -sticky nsew
grid $historyScroll -row 0 -column 1 -sticky ns
$notebook add $history -text "History"

grid $main.title -row 0 -column 0 -sticky w
grid $main.status -row 0 -column 0 -sticky e
grid $toolbar -row 1 -column 0 -sticky ew -pady {10 10}
grid $body -row 2 -column 0 -sticky nsew

::pino::refresh
