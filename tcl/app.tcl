#!/usr/bin/env tclsh

namespace eval ::pino {
	variable diagnosticsLog ""
	variable suppressErrorDialogs 0
	variable guiReadyFile ""
	variable guiCheckAutoExitMs 0
	variable guiCheckExerciseDialogError 0
	variable guiCheckDone 0
	variable guiCheckExitCode 0
	variable guiErrorCount 0
}

proc ::pino::envValue {name {default ""}} {
	if {[info exists ::env($name)] && $::env($name) ne ""} {
		return $::env($name)
	}
	return $default
}

proc ::pino::envFlag {name} {
	if {![info exists ::env($name)]} {
		return 0
	}
	set value [string tolower [string trim $::env($name)]]
	expr {$value ni {"" "0" "false" "no" "off"}}
}

proc ::pino::envInt {name default} {
	set value [envValue $name ""]
	if {[string is integer -strict $value] && $value >= 0} {
		return $value
	}
	return $default
}

proc ::pino::writeDiagnostic {level message {options {}}} {
	variable diagnosticsLog
	set timestamp [clock format [clock seconds] -gmt true -format "%Y-%m-%dT%H:%M:%SZ"]
	set lines [list [format {%s [%s] %s} $timestamp $level $message]]
	if {[dict exists $options -errorinfo]} {
		lappend lines [dict get $options -errorinfo]
	}
	if {[dict exists $options -errorcode]} {
		lappend lines "errorCode: [dict get $options -errorcode]"
	}
	set text [join $lines "\n"]
	catch {
		puts stderr $text
		flush stderr
	}
	if {$diagnosticsLog ne ""} {
		catch {
			file mkdir [file dirname $diagnosticsLog]
			set handle [open $diagnosticsLog a]
			fconfigure $handle -encoding utf-8 -translation lf
			puts $handle $text
			close $handle
		}
	}
}

proc ::pino::showErrorDialog {title message} {
	variable suppressErrorDialogs
	if {$suppressErrorDialogs || [llength [info commands tk_messageBox]] == 0} {
		return
	}
	catch {tk_messageBox -icon error -type ok -title $title -message $message}
}

proc ::pino::reportError {context message options} {
	variable guiErrorCount
	incr guiErrorCount
	writeDiagnostic ERROR "$context: $message" $options
}

proc ::pino::fatalError {context message options} {
	reportError $context $message $options
	showErrorDialog "Pino Error" "$context: $message"
	exit 1
}

proc ::pino::requirePackage {name} {
	if {[catch {package require $name} result options]} {
		fatalError "Load package $name" $result $options
	}
	return $result
}

proc bgerror {message} {
	set options [dict create]
	if {[info exists ::errorInfo]} {
		dict set options -errorinfo $::errorInfo
	}
	if {[info exists ::errorCode]} {
		dict set options -errorcode $::errorCode
	}
	::pino::reportError "Tk background error" $message $options
	::pino::showErrorDialog "Pino Error" $message
}

proc ::pino::setupDiagnostics {} {
	variable diagnosticsLog [envValue PINO_DIAGNOSTICS_LOG]
	variable suppressErrorDialogs [expr {[envFlag PINO_NO_ERROR_DIALOGS] || [envFlag PINO_SUPPRESS_ERROR_DIALOGS]}]
	variable guiReadyFile [envValue PINO_GUI_READY_FILE]
	variable guiCheckAutoExitMs [envInt PINO_GUI_AUTO_EXIT_MS 0]
	variable guiCheckExerciseDialogError [envFlag PINO_GUI_EXERCISE_DIALOG_ERROR]
	if {$diagnosticsLog ne ""} {
		writeDiagnostic INFO "Diagnostics started"
	}
}

::pino::setupDiagnostics
::pino::requirePackage Tk

namespace eval ::pino {
	variable appDir [file normalize [file dirname [info script]]]
	lappend ::auto_path [file join $appDir vendor tcllib sha1]
	lappend ::auto_path [file join $appDir vendor tcllib json]
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
	variable changeSummaryVar ""
	variable statusVar "Ready"
	variable commitMessageVar ""
	variable changesTree ""
	variable historyTree ""
	variable restoreTree ""
	variable initButton ""
	variable commitButton ""
	variable restoreButton ""
	variable selectedCommitId ""
	variable restoreCommitVar ""
	variable restoreFileVar ""
}

::pino::requirePackage sha256
::pino::requirePackage json
::pino::requirePackage json::write

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

proc ::pino::tmpDir {} {
	file join [repoDir] tmp
}

proc ::pino::objectPath {objectId} {
	file join [repoDir] objects [string range $objectId 0 1] [string range $objectId 2 end]
}

proc ::pino::commitPath {commitId} {
	file join [repoDir] commits [string range $commitId 0 1] "[string range $commitId 2 end].json"
}

proc ::pino::shortId {id} {
	if {$id eq ""} {
		return ""
	}
	string range $id 0 11
}

proc ::pino::ensureRepoLayout {} {
	set repo [repoDir]
	foreach dir [list $repo [file join $repo objects] [file join $repo commits] [file join $repo refs] [tmpDir]] {
		file mkdir $dir
	}
	set headPath [file join $repo HEAD]
	if {![file exists $headPath]} {
		writeTextFile $headPath "refs/main\n"
	}
	set mainRef [file join $repo refs main]
	if {![file exists $mainRef]} {
		writeTextFile $mainRef ""
	}
}

proc ::pino::writeTextFile {path data} {
	file mkdir [file dirname $path]
	set handle [open $path w]
	fconfigure $handle -encoding utf-8 -translation lf
	puts -nonewline $handle $data
	close $handle
}

proc ::pino::readTextFile {path} {
	set handle [open $path r]
	fconfigure $handle -encoding utf-8 -translation lf
	set data [read $handle]
	close $handle
	return $data
}

proc ::pino::atomicWriteText {path data} {
	ensureRepoLayout
	set tmp [file join [tmpDir] "write-[pid]-[clock clicks]-[file tail $path]"]
	writeTextFile $tmp $data
	file mkdir [file dirname $path]
	file rename -force $tmp $path
}

proc ::pino::copyObject {absolutePath objectId} {
	ensureRepoLayout
	set destination [objectPath $objectId]
	if {[file exists $destination]} {
		return
	}
	file mkdir [file dirname $destination]
	set tmp [file join [tmpDir] "object-[pid]-[clock clicks]-$objectId"]
	file copy -force $absolutePath $tmp
	file rename -force $tmp $destination
}

proc ::pino::safeRelativePath {path} {
	if {[file pathtype $path] ne "relative"} {
		return 0
	}
	foreach part [file split $path] {
		if {$part eq "" || $part eq "." || $part eq ".."} {
			return 0
		}
	}
	return 1
}

proc ::pino::fileEntryByPath {entries relativePath} {
	foreach entry $entries {
		if {[dict get $entry path] eq $relativePath} {
			return $entry
		}
	}
	return {}
}

proc ::pino::fileMatchesEntry {absolutePath entry} {
	if {$entry eq {} || ![file exists $absolutePath] || ![file isfile $absolutePath]} {
		return 0
	}
	if {[file size $absolutePath] ne [dict get $entry size]} {
		return 0
	}
	expr {[::sha2::sha256 -hex -filename $absolutePath] eq [dict get $entry object]}
}

proc ::pino::hasLocalChangesForPath {relativePath} {
	variable workspace
	set headEntry [fileEntryByPath [headFiles] $relativePath]
	set absolutePath [file join $workspace $relativePath]
	if {[file exists $absolutePath]} {
		if {$headEntry eq {}} {
			return 1
		}
		return [expr {![fileMatchesEntry $absolutePath $headEntry]}]
	}
	expr {$headEntry ne {}}
}

proc ::pino::restoreFileFromCommit {commitId relativePath {force 0}} {
	variable workspace
	if {![repoExists]} {
		error "Repository is not initialized"
	}
	if {![safeRelativePath $relativePath]} {
		error "Unsafe restore path: $relativePath"
	}
	set commit [readCommit $commitId]
	if {$commit eq {}} {
		error "Commit not found: [shortId $commitId]"
	}
	set entry [fileEntryByPath [dict get $commit files] $relativePath]
	if {$entry eq {}} {
		error "File is not present in snapshot: $relativePath"
	}
	if {!$force && [hasLocalChangesForPath $relativePath]} {
		error "Refusing to overwrite local changes in $relativePath"
	}
	set source [objectPath [dict get $entry object]]
	if {![file exists $source]} {
		error "Object is missing: [dict get $entry object]"
	}
	set destination [file join $workspace $relativePath]
	if {[file exists $destination] && ![file isfile $destination]} {
		error "Destination is not a regular file: $relativePath"
	}
	ensureRepoLayout
	file mkdir [file dirname $destination]
	set tmp [file join [tmpDir] "restore-[pid]-[clock clicks]-[file tail $relativePath]"]
	file copy -force $source $tmp
	file rename -force $tmp $destination
	return $relativePath
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

	ensureRepoLayout

	refresh
	setStatus "Repository initialized"
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
	set skipped {. .. .git .pino tcltk pino.code-workspace pino.exe desktop.ini Thumbs.db .DS_Store}
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

proc ::pino::buildSnapshot {writeObjects} {
	variable workspace
	set entries {}
	foreach relative [scanFiles] {
		set absolute [file join $workspace $relative]
		set objectId [::sha2::sha256 -hex -filename $absolute]
		set size [file size $absolute]
		if {$writeObjects} {
			copyObject $absolute $objectId
		}
		lappend entries [dict create path $relative mode file object $objectId size $size]
	}
	return $entries
}

proc ::pino::entryMap {entries} {
	set map [dict create]
	foreach entry $entries {
		dict set map [dict get $entry path] $entry
	}
	return $map
}

proc ::pino::headCommit {} {
	set id [headValue]
	if {$id eq ""} {
		return {}
	}
	readCommit $id
}

proc ::pino::headFiles {} {
	set commit [headCommit]
	if {$commit eq {} || ![dict exists $commit files]} {
		return {}
	}
	dict get $commit files
}

proc ::pino::readCommit {commitId} {
	set path [commitPath $commitId]
	if {![file exists $path]} {
		return {}
	}
	set handle [open $path r]
	fconfigure $handle -encoding utf-8 -translation lf
	set data [read $handle]
	close $handle
	::json::json2dict $data
}

proc ::pino::commitFilesEqual {left right} {
	set leftMap [entryMap $left]
	set rightMap [entryMap $right]
	if {[lsort -dictionary [dict keys $leftMap]] ne [lsort -dictionary [dict keys $rightMap]]} {
		return false
	}
	foreach path [dict keys $leftMap] {
		set leftEntry [dict get $leftMap $path]
		set rightEntry [dict get $rightMap $path]
		if {[dict get $leftEntry object] ne [dict get $rightEntry object]} {
			return false
		}
		if {[dict get $leftEntry size] ne [dict get $rightEntry size]} {
			return false
		}
	}
	return true
}

proc ::pino::statusRows {currentEntries} {
	if {![repoExists]} {
		set rows {}
		foreach entry $currentEntries {
			lappend rows [dict create status File path [dict get $entry path] size [dict get $entry size] object [dict get $entry object]]
		}
		return $rows
	}

	set headEntries [headFiles]
	set headMap [entryMap $headEntries]
	set currentMap [entryMap $currentEntries]
	set rows {}

	foreach entry $currentEntries {
		set path [dict get $entry path]
		if {![dict exists $headMap $path]} {
			lappend rows [dict create status Added path $path size [dict get $entry size] object [dict get $entry object]]
			continue
		}
		set previous [dict get $headMap $path]
		if {[dict get $entry object] ne [dict get $previous object] || [dict get $entry size] ne [dict get $previous size]} {
			lappend rows [dict create status Modified path $path size [dict get $entry size] object [dict get $entry object]]
		}
	}

	foreach path [lsort -dictionary [dict keys $headMap]] {
		if {![dict exists $currentMap $path]} {
			set previous [dict get $headMap $path]
			lappend rows [dict create status Deleted path $path size [dict get $previous size] object [dict get $previous object]]
		}
	}

	return $rows
}

proc ::pino::changeSummary {rows} {
	array set counts {Added 0 Modified 0 Deleted 0 File 0}
	foreach row $rows {
		set status [dict get $row status]
		if {![info exists counts($status)]} {
			set counts($status) 0
		}
		incr counts($status)
	}
	set parts {}
	foreach status {Added Modified Deleted File} {
		if {$counts($status) > 0} {
			lappend parts "$counts($status) $status"
		}
	}
	if {[llength $parts] == 0} {
		return "No changes"
	}
	join $parts " / "
}

proc ::pino::manifestJson {parent message entries} {
	set fileJson {}
	foreach entry $entries {
		lappend fileJson [::json::write object \
			path [::json::write string [dict get $entry path]] \
			mode [::json::write string [dict get $entry mode]] \
			object [::json::write string [dict get $entry object]] \
			size [dict get $entry size]]
	}
	set created [clock format [clock seconds] -gmt true -format "%Y-%m-%dT%H:%M:%SZ"]
	append manifest [::json::write object \
		version 1 \
		parent [::json::write string $parent] \
		created [::json::write string $created] \
		message [::json::write string $message] \
		files [::json::write array {*}$fileJson]] "\n"
	return $manifest
}

proc ::pino::commitSnapshot {} {
	variable commitMessageVar
	if {![repoExists]} {
		setStatus "Initialize a repository first"
		return ""
	}
	ensureRepoLayout
	set entries [buildSnapshot true]
	set parent [headValue]
	if {$parent ne "" && [commitFilesEqual $entries [headFiles]]} {
		setStatus "No changes to commit"
		refresh
		return ""
	}
	if {$parent eq "" && [llength $entries] == 0} {
		setStatus "No files to commit"
		refresh
		return ""
	}
	set message [string trim $commitMessageVar]
	if {$message eq ""} {
		set message "Snapshot"
	}
	set manifest [manifestJson $parent $message $entries]
	set commitId [::sha2::sha256 -hex $manifest]
	atomicWriteText [commitPath $commitId] $manifest
	atomicWriteText [file join [repoDir] refs main] "$commitId\n"
	set commitMessageVar ""
	refresh
	setStatus "Committed [shortId $commitId]"
	return $commitId
}

proc ::pino::refreshChanges {} {
	variable changesTree
	variable fileCountVar
	variable changeSummaryVar
	if {$changesTree eq ""} {
		return 0
	}
	$changesTree delete [$changesTree children {}]
	set entries [buildSnapshot false]
	set rows [statusRows $entries]
	set fileCountVar "[llength $entries] files"
	set changeSummaryVar [changeSummary $rows]

	foreach row [lrange $rows 0 299] {
		set object [dict get $row object]
		$changesTree insert {} end -values [list \
			[dict get $row status] \
			[dict get $row path] \
			[dict get $row size] \
			[string range $object 0 11]]
	}
	if {[llength $rows] > 300} {
		$changesTree insert {} end -values [list More "[expr {[llength $rows] - 300}] more changes" "" ""]
	}
	return [llength $rows]
}

proc ::pino::refreshHistory {} {
	variable historyTree
	variable selectedCommitId
	if {$historyTree eq ""} {
		return
	}
	$historyTree delete [$historyTree children {}]
	set selectedCommitId ""
	if {![repoExists]} {
		refreshRestoreFiles
		return
	}
	set head [headValue]
	set seen {}
	set count 0
	while {$head ne "" && $count < 100} {
		if {[dict exists $seen $head]} {
			$historyTree insert {} end -values [list [shortId $head] "cycle detected" "" ""]
			return
		}
		dict set seen $head true
		set commit [readCommit $head]
		if {$commit eq {}} {
			$historyTree insert {} end -values [list [shortId $head] "missing commit" "" ""]
			return
		}
		set files [dict get $commit files]
		$historyTree insert {} end -id $head -values [list \
			[shortId $head] \
			[dict get $commit created] \
			[dict get $commit message] \
			[llength $files]]
		set head [dict get $commit parent]
		incr count
	}
	set first [lindex [$historyTree children {}] 0]
	if {$first ne ""} {
		$historyTree selection set $first
		set selectedCommitId $first
	}
	refreshRestoreFiles
}

proc ::pino::selectHistoryCommit {} {
	variable historyTree
	variable selectedCommitId
	set selection [$historyTree selection]
	if {[llength $selection] == 0} {
		set selectedCommitId ""
	} else {
		set selectedCommitId [lindex $selection 0]
	}
	refreshRestoreFiles
}

proc ::pino::refreshRestoreFiles {} {
	variable selectedCommitId
	variable restoreTree
	variable restoreButton
	variable restoreCommitVar
	variable restoreFileVar
	set restoreCommitVar ""
	set restoreFileVar ""
	if {$restoreTree eq ""} {
		return
	}
	$restoreTree delete [$restoreTree children {}]
	if {$restoreButton ne ""} {
		$restoreButton state disabled
	}
	if {$selectedCommitId eq ""} {
		return
	}
	set commit [readCommit $selectedCommitId]
	if {$commit eq {}} {
		set restoreCommitVar "Missing snapshot [shortId $selectedCommitId]"
		return
	}
	set restoreCommitVar "Snapshot [shortId $selectedCommitId] / [dict get $commit message]"
	foreach entry [lrange [dict get $commit files] 0 299] {
		set object [dict get $entry object]
		$restoreTree insert {} end -values [list \
			[dict get $entry path] \
			[dict get $entry size] \
			[string range $object 0 11]]
	}
	if {[llength [dict get $commit files]] > 300} {
		$restoreTree insert {} end -values [list "[expr {[llength [dict get $commit files]] - 300}] more files" "" ""]
	}
	set first [$restoreTree children {}]
	if {[llength $first] > 0} {
		$restoreTree selection set [lindex $first 0]
		selectRestoreFile
	}
}

proc ::pino::selectRestoreFile {} {
	variable restoreTree
	variable restoreButton
	variable restoreFileVar
	set selection [$restoreTree selection]
	if {[llength $selection] == 0} {
		set restoreFileVar ""
		if {$restoreButton ne ""} {
			$restoreButton state disabled
		}
		return
	}
	set values [$restoreTree item [lindex $selection 0] -values]
	set restoreFileVar [lindex $values 0]
	if {$restoreButton ne "" && [llength $values] == 3 && [lindex $values 1] ne ""} {
		$restoreButton state !disabled
	}
}

proc ::pino::restoreSelectedFile {} {
	variable selectedCommitId
	variable restoreFileVar
	if {$selectedCommitId eq "" || $restoreFileVar eq ""} {
		setStatus "Select a snapshot file to restore"
		return
	}
	set answer [tk_messageBox \
		-icon warning \
		-type yesno \
		-title "Restore File" \
		-message "Restore $restoreFileVar from snapshot [shortId $selectedCommitId]?" \
		-detail "Pino will refuse to overwrite local changes."]
	if {$answer ne "yes"} {
		return
	}
	if {[catch {restoreFileFromCommit $selectedCommitId $restoreFileVar 0} restored options]} {
		setStatus $restored
		showErrorDialog "Restore File" $restored
		return
	}
	refresh
	setStatus "Restored $restored"
}

proc ::pino::refresh {} {
	variable workspace
	variable workspaceVar
	variable repoStateVar
	variable headVar
	variable changeSummaryVar
	variable initButton
	variable commitButton
	set workspaceVar $workspace

	if {[repoExists]} {
		ensureRepoLayout
		set repoStateVar "Repository ready"
		set head [headValue]
		if {$head eq ""} {
			set headVar "No commits"
		} else {
			set headVar [shortId $head]
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
	set changeCount [refreshChanges]
	if {$commitButton ne ""} {
		if {[repoExists] && $changeCount > 0} {
			$commitButton state !disabled
		} else {
			$commitButton state disabled
		}
	}
	refreshHistory
	if {![repoExists]} {
		setStatus "Initialize repository to start snapshots"
	} elseif {$changeCount == 0} {
		setStatus "No changes"
	} else {
		setStatus $changeSummaryVar
	}
}

proc ::pino::writeGuiReady {} {
	variable guiReadyFile
	variable workspace
	wm deiconify .
	raise .
	update
	set geometry [wm geometry .]
	set width [winfo width .]
	set height [winfo height .]
	if {$width < 200 || $height < 200} {
		after 100 ::pino::writeGuiReady
		return
	}
	writeDiagnostic INFO "GUI ready: $geometry"
	if {$guiReadyFile eq ""} {
		return
	}
	set data [join [list \
		"ready 1" \
		"pid [pid]" \
		"title [wm title .]" \
		"geometry $geometry" \
		"width $width" \
		"height $height" \
		"workspace $workspace"] "\n"]
	append data "\n"
	if {[catch {writeTextFile $guiReadyFile $data} result options]} {
		reportError "Write GUI ready file" $result $options
	}
}

proc ::pino::finishGuiCheck {} {
	variable guiErrorCount
	variable guiCheckDone
	variable guiCheckExitCode
	set guiCheckExitCode [expr {$guiErrorCount > 0 ? 2 : 0}]
	set guiCheckDone 1
}

proc ::pino::startGuiAutomation {} {
	variable guiReadyFile
	variable guiCheckAutoExitMs
	variable guiCheckExerciseDialogError
	if {$guiReadyFile ne "" || [hasArg "--gui-check"]} {
		after idle ::pino::writeGuiReady
	}
	if {![hasArg "--gui-check"]} {
		return
	}
	if {$guiCheckAutoExitMs <= 0} {
		set guiCheckAutoExitMs 1200
	}
	if {$guiCheckExerciseDialogError || [hasArg "--dialog-error-check"]} {
		after 100 {error "Pino dialog capture check"}
	}
	after $guiCheckAutoExitMs ::pino::finishGuiCheck
}

proc ::pino::runRestoreCheck {} {
	variable workspace
	variable commitMessageVar
	if {![repoExists]} {
		initRepository
	}
	set relativePath "restore-check.txt"
	set absolutePath [file join $workspace $relativePath]
	writeTextFile $absolutePath "first\n"
	set commitMessageVar "Restore check first"
	set firstCommit [commitSnapshot]
	if {$firstCommit eq ""} {
		error "First restore-check commit was not created"
	}
	writeTextFile $absolutePath "second\n"
	set commitMessageVar "Restore check second"
	set secondCommit [commitSnapshot]
	if {$secondCommit eq ""} {
		error "Second restore-check commit was not created"
	}
	writeTextFile $absolutePath "dirty\n"
	if {![catch {restoreFileFromCommit $firstCommit $relativePath 0} result]} {
		error "Restore unexpectedly overwrote local changes"
	}
	restoreFileFromCommit $firstCommit $relativePath 1
	set restored [readTextFile $absolutePath]
	if {$restored ne "first\n"} {
		error "Restore produced unexpected content: $restored"
	}
	puts "Pino restore check OK"
	puts "First $firstCommit"
	puts "Second $secondCommit"
}

if {[::pino::hasArg "--check"]} {
	puts "Pino UI runtime OK"
	puts "Tcl [info patchlevel]"
	puts "Tk [package provide Tk]"
	puts "sha256 [package provide sha256]"
	puts "json [package provide json]"
	puts "Workspace $::pino::workspace"
	destroy .
	exit 0
}

if {[::pino::hasArg "--repo-check"]} {
	if {![::pino::repoExists]} {
		::pino::initRepository
	}
	set ::pino::commitMessageVar "Repository check"
	set commitId [::pino::commitSnapshot]
	puts "Pino repository check OK"
	if {$commitId eq ""} {
		puts "Commit none"
	} else {
		puts "Commit $commitId"
	}
	destroy .
	exit 0
}

if {[::pino::hasArg "--restore-check"]} {
	if {[catch {::pino::runRestoreCheck} result options]} {
		::pino::reportError "Restore check" $result $options
		destroy .
		exit 1
	}
	destroy .
	exit 0
}

wm title . "Pino"
wm minsize . 880 560
wm geometry . 1000x680
catch {ttk::style theme use vista}

ttk::style configure Pino.Title.TLabel -font {{Segoe UI} 16 bold}
ttk::style configure Pino.Meta.TLabel -foreground #555555
ttk::style configure Pino.Sidebar.TLabel -foreground #555555
ttk::style configure Pino.Primary.TButton -padding {14 7}
ttk::style configure Treeview -rowheight 24

set main [ttk::frame .main -padding 16]
grid $main -sticky nsew
grid columnconfigure . 0 -weight 1
grid rowconfigure . 0 -weight 1
grid columnconfigure $main 0 -weight 1
grid rowconfigure $main 3 -weight 1

ttk::label $main.title -text "Pino" -style Pino.Title.TLabel
ttk::label $main.status -textvariable ::pino::statusVar -style Pino.Meta.TLabel

set toolbar [ttk::frame $main.toolbar]
grid columnconfigure $toolbar 1 -weight 1
ttk::label $toolbar.workspaceLabel -text "Workspace"
ttk::entry $toolbar.workspace -textvariable ::pino::workspaceVar -state readonly
ttk::button $toolbar.open -text "Open..." -command ::pino::chooseWorkspace
ttk::button $toolbar.refresh -text "Refresh" -command ::pino::refresh
set ::pino::initButton [ttk::button $toolbar.init -text "Initialize" -command ::pino::initRepository]

grid $toolbar.workspaceLabel -row 0 -column 0 -sticky w -padx {0 8}
grid $toolbar.workspace -row 0 -column 1 -sticky ew -padx {0 8}
grid $toolbar.open -row 0 -column 2 -padx {0 6}
grid $toolbar.refresh -row 0 -column 3 -padx {0 6}
grid $toolbar.init -row 0 -column 4

ttk::separator $main.rule -orient horizontal

set body [ttk::panedwindow $main.body -orient horizontal]
set sidebar [ttk::frame $body.sidebar -padding 10]
set notebook [ttk::notebook $body.notebook]
$body add $sidebar -weight 0
$body add $notebook -weight 1

ttk::label $sidebar.repositoryLabel -text "Repository" -style Pino.Sidebar.TLabel
ttk::label $sidebar.repository -textvariable ::pino::repoStateVar
ttk::label $sidebar.headLabel -text "Head" -style Pino.Sidebar.TLabel
ttk::label $sidebar.head -textvariable ::pino::headVar -wraplength 210
ttk::label $sidebar.filesLabel -text "Files" -style Pino.Sidebar.TLabel
ttk::label $sidebar.files -textvariable ::pino::fileCountVar
ttk::label $sidebar.changesLabel -text "Changes" -style Pino.Sidebar.TLabel
ttk::label $sidebar.changes -textvariable ::pino::changeSummaryVar -wraplength 210
ttk::label $sidebar.runtimeLabel -text "Runtime" -style Pino.Sidebar.TLabel
ttk::label $sidebar.runtime -text "Tcl [info patchlevel] / Tk [package provide Tk]" -wraplength 210

grid $sidebar.repositoryLabel -row 0 -column 0 -sticky w
grid $sidebar.repository -row 1 -column 0 -sticky ew -pady {2 14}
grid $sidebar.headLabel -row 2 -column 0 -sticky w
grid $sidebar.head -row 3 -column 0 -sticky ew -pady {2 14}
grid $sidebar.filesLabel -row 4 -column 0 -sticky w
grid $sidebar.files -row 5 -column 0 -sticky ew -pady {2 14}
grid $sidebar.changesLabel -row 6 -column 0 -sticky w
grid $sidebar.changes -row 7 -column 0 -sticky ew -pady {2 14}
grid $sidebar.runtimeLabel -row 8 -column 0 -sticky w
grid $sidebar.runtime -row 9 -column 0 -sticky ew -pady {2 0}

set changes [ttk::frame $notebook.changes -padding 10]
grid columnconfigure $changes 0 -weight 1
grid rowconfigure $changes 0 -weight 1
set ::pino::changesTree [ttk::treeview $changes.tree -columns {status path size object} -show headings -height 14]
$::pino::changesTree heading status -text "Status"
$::pino::changesTree heading path -text "Path"
$::pino::changesTree heading size -text "Size"
$::pino::changesTree heading object -text "Object"
$::pino::changesTree column status -width 110 -stretch false
$::pino::changesTree column path -width 460 -stretch true
$::pino::changesTree column size -width 90 -stretch false -anchor e
$::pino::changesTree column object -width 120 -stretch false
set changesScroll [ttk::scrollbar $changes.scroll -orient vertical -command "$::pino::changesTree yview"]
$::pino::changesTree configure -yscrollcommand "$changesScroll set"
ttk::label $changes.messageLabel -text "Commit message"
ttk::entry $changes.message -textvariable ::pino::commitMessageVar
set ::pino::commitButton [ttk::button $changes.commit -text "Commit" -style Pino.Primary.TButton -command ::pino::commitSnapshot]

grid $::pino::changesTree -row 0 -column 0 -sticky nsew
grid $changesScroll -row 0 -column 1 -sticky ns
grid $changes.messageLabel -row 1 -column 0 -sticky w -pady {12 4}
grid $changes.message -row 2 -column 0 -sticky ew -pady {0 8}
grid $changes.commit -row 3 -column 0 -sticky e
$notebook add $changes -text "Changes"

set history [ttk::frame $notebook.history -padding 10]
grid columnconfigure $history 0 -weight 1
grid rowconfigure $history 0 -weight 1
grid rowconfigure $history 2 -weight 1
set ::pino::historyTree [ttk::treeview $history.tree -columns {commit created message files} -show headings -height 14]
$::pino::historyTree heading commit -text "Commit"
$::pino::historyTree heading created -text "Created"
$::pino::historyTree heading message -text "Message"
$::pino::historyTree heading files -text "Files"
$::pino::historyTree column commit -width 140 -stretch false
$::pino::historyTree column created -width 170 -stretch false
$::pino::historyTree column message -width 380 -stretch true
$::pino::historyTree column files -width 70 -stretch false -anchor e
set historyScroll [ttk::scrollbar $history.scroll -orient vertical -command "$::pino::historyTree yview"]
$::pino::historyTree configure -yscrollcommand "$historyScroll set"
grid $::pino::historyTree -row 0 -column 0 -sticky nsew
grid $historyScroll -row 0 -column 1 -sticky ns
bind $::pino::historyTree <<TreeviewSelect>> ::pino::selectHistoryCommit

ttk::label $history.restoreLabel -textvariable ::pino::restoreCommitVar -style Pino.Meta.TLabel
set ::pino::restoreTree [ttk::treeview $history.restoreTree -columns {path size object} -show headings -height 8]
$::pino::restoreTree heading path -text "Snapshot File"
$::pino::restoreTree heading size -text "Size"
$::pino::restoreTree heading object -text "Object"
$::pino::restoreTree column path -width 520 -stretch true
$::pino::restoreTree column size -width 90 -stretch false -anchor e
$::pino::restoreTree column object -width 120 -stretch false
set restoreScroll [ttk::scrollbar $history.restoreScroll -orient vertical -command "$::pino::restoreTree yview"]
$::pino::restoreTree configure -yscrollcommand "$restoreScroll set"
bind $::pino::restoreTree <<TreeviewSelect>> ::pino::selectRestoreFile

set restoreActions [ttk::frame $history.restoreActions]
grid columnconfigure $restoreActions 1 -weight 1
ttk::label $restoreActions.selectedLabel -text "Selected file"
ttk::entry $restoreActions.selected -textvariable ::pino::restoreFileVar -state readonly
set ::pino::restoreButton [ttk::button $restoreActions.restore -text "Restore File" -style Pino.Primary.TButton -command ::pino::restoreSelectedFile]
$::pino::restoreButton state disabled
grid $restoreActions.selectedLabel -row 0 -column 0 -sticky w -padx {0 8}
grid $restoreActions.selected -row 0 -column 1 -sticky ew -padx {0 8}
grid $restoreActions.restore -row 0 -column 2 -sticky e

grid $history.restoreLabel -row 1 -column 0 -columnspan 2 -sticky w -pady {12 4}
grid $::pino::restoreTree -row 2 -column 0 -sticky nsew
grid $restoreScroll -row 2 -column 1 -sticky ns
grid $restoreActions -row 3 -column 0 -columnspan 2 -sticky ew -pady {8 0}
$notebook add $history -text "History"

if {[::pino::hasArg "--gui-check"] && [::pino::repoExists] && [::pino::headValue] ne ""} {
	$notebook select $history
}

grid $main.title -row 0 -column 0 -sticky w
grid $main.status -row 0 -column 0 -sticky e
grid $toolbar -row 1 -column 0 -sticky ew -pady {10 10}
grid $main.rule -row 2 -column 0 -sticky ew -pady {0 12}
grid $body -row 3 -column 0 -sticky nsew

::pino::refresh
::pino::startGuiAutomation

if {[::pino::hasArg "--gui-check"]} {
	vwait ::pino::guiCheckDone
	catch {destroy .}
	exit $::pino::guiCheckExitCode
}
