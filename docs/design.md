# Pino Design

Pino is a local-first plain-text version control system for notes. It is optimized for writers who want confidence that their work is preserved without needing to learn or operate a full software-development VCS.

The first implementation is a Go-built desktop app shell around a Tcl/Tk application. Go currently embeds the Tcl/Tk runtime and Tcl source into a single executable, materializes those assets at startup, and launches the Tcl app. Repository behavior can live in Tcl while the interaction model is young; later, stable functionality may move into Go. The repository format should stay simple enough to inspect and repair with a text editor and ordinary filesystem tools.

## Product Goals

- Never lose writing.
- Make history, comparison, and restore simple.
- Keep repository metadata human-inspectable.
- Work fully offline by default.
- Favor predictable behavior over clever automation.
- Support plain-text notes first; treat binary files as a later capability.

## Non-Goals

- Pino is not a distributed collaboration system in the first version.
- Pino is not a Git wrapper.
- Pino is not a rich-text editor.
- Pino does not need branching, merging, remotes, or conflict resolution for the initial release.
- Pino should not require a background service for core operations.

## User Model

The primary user keeps a folder of notes and wants durable snapshots at meaningful moments. They may not know which files changed, may rename notes, and may need to recover text from an earlier point in time.

Pino should make the safe action obvious:

- `pino init` starts tracking a notes folder.
- `pino status` explains what changed in plain language.
- `pino commit` records the current state with an optional message.
- `pino log` shows previous snapshots.
- `pino diff` shows text changes.
- `pino restore` recovers a file or entire snapshot.
- `pino verify` checks repository integrity.

## Current State

The current repository contains the initial app scaffold:

- `cmd/pino/main.go` starts the embedded app launcher.
- `assets.go` embeds `tcl/` and `tcltk/` into the Go executable.
- `internal/launcher/run.go` materializes the embedded runtime and starts the Tcl app.
- `internal/cli/run.go` and `internal/repo/init.go` remain as early Go experiments for possible future repository logic.
- `internal/repo/init_test.go` verifies the bootstrap layout.
- `tcl/app.tcl` is the Tcl/Tk app shell. It opens on the current workspace, can initialize `.pino`, displays working changes, writes SHA-256-addressed objects, and creates JSON snapshot commits.
- `tcl/vendor/tcllib/` vendors the minimal Tcllib 2.0 SHA-256 and JSON packages required by the app.
- `scripts/pino-gui-check.ps1` launches the real GUI for automated visual checks, captures screenshots, records visible window geometry, and collects stdout, stderr, and Tcl diagnostics.
- `tcltk/` contains the committed Tcl/Tk 9.0.3 runtime.

The implemented `.pino` layout is:

```text
.pino/
  HEAD
  commits/
  objects/
  refs/
	 main
```

## Design Principles

- Local-first: all core operations run against local files.
- Human-inspectable: metadata uses plain text formats where practical.
- Append-friendly: history should be easy to preserve and hard to corrupt.
- Atomic writes: repository updates should either complete or leave the previous state valid.
- Explicit recovery: restore operations should preview or clearly describe what they will overwrite.
- Small core: repository operations live below the CLI so the future Tcl UI can reuse the same behavior.

## Architecture

Pino is currently split into three layers:

1. Go launcher layer
	- Embeds `tcl/` and `tcltk/` into one executable.
	- Extracts embedded files into a versioned user-cache directory.
	- Starts `wish90.exe` or `tclsh90.exe --check` from the embedded runtime.
	- Passes workspace and runtime paths through environment variables.

2. Tcl application layer
	- Owns the desktop UI.
	- Starts with workspace selection, repository initialization, file listing, snapshot commits, and commit history.
	- Can implement early repository behavior directly while the product shape is still changing.
	- Logs startup and background errors through a diagnostics channel so automation captures failures that would otherwise appear only in Tk dialogs.
	- Supports `--gui-check` for deterministic GUI verification with a ready marker and clean automated exit.

3. Repository layer
	- Owns `.pino` layout and file IO.
	- Computes file snapshots.
	- Writes and reads objects, commits, and refs.
	- Performs integrity checks.
	- May begin in Tcl and move to Go when the behavior becomes stable.

The repository layer should remain free of widget and presentation concerns no matter which language hosts it.

## Repository Format

Pino stores snapshots in a content-addressed object store and links them through commit manifests.

### Objects

Objects contain file content. The object ID should be the SHA-256 digest of the raw file bytes, encoded as lowercase hex.

Proposed path layout:

```text
.pino/objects/ab/cdef...rest
```

This keeps large repositories from placing every object in one directory.

Object writes should be atomic:

1. Write bytes to a temporary file inside `.pino/tmp`.
2. Flush and close the file.
3. Rename into the final object path.
4. Treat an existing object with the same digest as success.

### Commits

A commit records a full snapshot of tracked files. A full snapshot keeps restore simple and makes every commit independently understandable.

Commit IDs should be the SHA-256 digest of the canonical commit manifest bytes.

Proposed commit manifest format:

```json
{
  "version": 1,
  "parent": "",
  "created": "2026-05-18T12:00:00Z",
  "message": "Initial notes snapshot",
  "files": [
	 {
		"path": "notes/example.txt",
		"mode": "file",
		"object": "sha256-hex",
		"size": 1234
	 }
  ]
}
```

Canonicalization rules should be explicit:

- UTF-8 JSON.
- Stable object field order from Go's encoder or a dedicated manifest writer.
- Files sorted by normalized relative path.
- Timestamps stored in UTC RFC 3339 format.
- Paths use `/` separators in metadata on every platform.

### Refs

`.pino/HEAD` currently contains `refs/main`. The active ref file stores the latest commit ID for the linear history.

Proposed ref behavior:

- Empty ref means the repository has no commits.
- `commit` writes the new commit first, then atomically updates the active ref.
- `log` walks parent links from `HEAD`.

## Tracked Files

The first release can track all regular files below the workspace root except ignored paths.

Default ignored paths:

- `.pino/`
- `.git/`
- common editor temp files
- OS metadata files such as `.DS_Store` and `Thumbs.db`

An explicit `.pinoignore` file can be added later if users need control. Until then, the implementation should keep ignore behavior conservative and documented.

Symlinks need an explicit decision before support. The safest first version is to skip symlinks and report them in `status`.

## Commands

### `pino init`

Creates `.pino` in the current directory. It should fail if a Pino repository already exists at that root.

Future enhancement: detect when the current directory is already inside another Pino repository and print a clear message.

### `pino status`

Compares the working tree with the current `HEAD` snapshot.

Output should group changes as:

- Added
- Modified
- Deleted
- Untracked or skipped, if applicable

Status should be read-only.

### `pino commit`

Creates a new snapshot from the current working tree.

Options:

- `-m <message>` records a short message.
- Without `-m`, use a default message such as `Snapshot` for the first version, or open editor support later.

Behavior:

- Ensure `.pino` exists.
- Scan tracked files.
- Write missing objects.
- Build and write a commit manifest.
- Atomically update the active ref.
- Print the new commit ID and change summary.

If no files changed from `HEAD`, `commit` should avoid creating an empty commit unless a future `--allow-empty` flag is added.

### `pino log`

Shows commits from newest to oldest.

Initial output can include:

- Short commit ID.
- Timestamp.
- Message.
- Number of files changed compared with parent, if available cheaply.

### `pino diff`

Shows text differences between the working tree and `HEAD`, or between two commits in a later version.

The first implementation can use Go text diff support or a small internal diff package. Diff output should be stable and readable rather than feature-complete.

Binary files are out of scope for the first version.

### `pino restore`

Restores a file or snapshot from history.

Initial forms:

```text
pino restore <path>
pino restore --from <commit> <path>
```

Safety behavior:

- Refuse to overwrite local changes unless `--force` is provided.
- Print exactly what was restored.
- Create parent directories as needed.

Full-tree restore can come later after the file-level flow is safe.

### `pino verify`

Checks repository consistency.

Verification should include:

- `.pino` layout exists.
- `HEAD` points to a valid ref.
- Ref commit exists or is empty for a repository with no commits.
- Every commit manifest parses.
- Every object referenced by every commit exists.
- Object bytes hash to their recorded digest.
- Parent links point to existing commits.

## Tcl UI Direction

The Tcl UI is the actual app surface for the first phase. It should keep repository behavior small and explicit until the workflows feel right. The first useful UI can provide:

- Repository status overview.
- Commit message entry and commit button.
- Commit history list.
- File change list.
- Restore action with confirmation.

Once behavior stabilizes, Go can take over lower-level repository operations behind a stable boundary. Until then, Tcl may own simple operations such as repository initialization and workspace scanning.

## Error Handling

Errors should be plain and actionable. Prefer messages like:

```text
not a Pino repository: run `pino init` first
cannot restore notes/today.txt: local changes would be overwritten
repository verification failed: missing object <id>
```

Implementation errors should wrap lower-level errors with context, as the current `repo.Init` code already does.

## Data Safety

Pino's core promise is that writing is preserved. That leads to these implementation rules:

- Never delete objects during normal commands.
- Write content before publishing refs.
- Use temporary files and atomic rename for commits and refs.
- Keep restore conservative when working-tree files have local changes.
- Make `verify` available before any future cleanup or compaction command.
- Avoid background mutation in the first version.

## Testing Strategy

Tests should focus on repository behavior rather than CLI formatting first.

Priority tests:

- `init` creates the expected layout and refuses to overwrite an existing repo.
- Repository discovery finds `.pino` from nested directories.
- Commit writes objects, manifest, and ref atomically enough for normal failures.
- Status detects added, modified, and deleted files.
- Log walks parent commits in order.
- Restore refuses to overwrite local changes by default.
- Verify detects missing objects and malformed commits.

CLI tests can cover command dispatch and user-facing error messages once repository behavior is stable.

## Implementation Milestones

1. Repository foundation
	- Add repository discovery.
	- Add manifest types and path normalization.
	- Add object writer and reader.

2. First snapshot workflow
	- Implement `commit -m`.
	- Implement `status` against `HEAD`.
	- Add tests for added, modified, and deleted files.

3. History and recovery
	- Implement `log`.
	- Implement file-level `restore`.
	- Implement `verify`.

4. Comparison
	- Implement text `diff` for working tree versus `HEAD`.
	- Add commit-to-commit diff later.

5. UI
	- Define stable machine-readable CLI output.
	- Build Tcl status, commit, history, and restore views.

## Open Questions

- Should commits require explicit messages, or should frictionless snapshots be allowed?
- Should Pino track every file by default, or only known note extensions such as `.txt` and `.md`?
- Should renames be detected, or represented as delete plus add?
- Should line ending normalization be part of the object model, or should exact bytes always win?
- Should `.pinoignore` be included in the first usable release?
- Should the Tcl UI shell out to `pino --json`, or should the Go app expose a long-lived local process interface?

## First Release Definition

The first useful release is complete when a user can initialize a notes folder, commit snapshots, see what changed, view history, restore an earlier version of a file, and verify that the stored history is intact.

That release can be CLI-only. The Tcl UI becomes valuable once the repository model has stable read operations and safe restore behavior.
