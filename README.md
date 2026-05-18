# Pino

Pino is a local-first plain-text version control system for notes. It is aimed at writers who want durable snapshots, simple history, and safe restore without needing to operate a full software-development VCS.

## Current Status

Pino is early, but the foundation is in place:

- Go application shell that embeds the Tcl source and Tcl/Tk runtime into one executable.
- Repository bootstrap layout under `.pino/`.
- Project-local Tcl/Tk 9.0.3 runtime committed under `tcltk/` and embedded by the Go shell.
- Tcl/Tk UI that opens on the current workspace, initializes `.pino`, shows changes, and creates the first JSON snapshot commits.
- Vendored Tcllib 2.0 SHA-256 and JSON packages under `tcl/vendor/tcllib`.
- Product and architecture design in `docs/design.md`.

## Run The App

From the repository root:

```powershell
go run ./cmd/pino
```

For a smoke test that loads the embedded Tcl/Tk runtime without leaving the UI open:

```powershell
go run ./cmd/pino --check
```

To build a single executable:

```powershell
go build -o pino.exe ./cmd/pino
```

The executable materializes its embedded `tcl/` and `tcltk/` files into the user cache, then starts the Tcl/Tk app from there. The current Go role is packaging and launching; product behavior lives in Tcl for now. Later releases may move repository functionality into Go once the app model settles.

## Source Launchers

The source-tree launchers are still useful during Tcl UI development. They use the checked-out runtime in `tcltk/`, so a system Tcl/Tk install is not required on Windows.

```powershell
.\scripts\pino-ui.cmd
```

For a smoke test that loads Tcl and Tk without leaving the UI open:

```powershell
.\scripts\pino-ui.cmd --check
```

PowerShell users can also run:

```powershell
pwsh -NoProfile -File .\scripts\pino-ui.ps1
```

## Repository Model

Pino stores local history in a `.pino/` directory inside the notes folder.

```text
.pino/
	HEAD
	commits/
	objects/
	refs/
		main
```

The app can currently initialize that layout from the Tcl UI and create full snapshot commits. Commit manifests are JSON, file contents are stored as SHA-256-addressed objects, and `refs/main` points to the latest snapshot.

## Development

Run tests with:

```powershell
go test ./...
```

The Tcl/Tk runtime was built from Tcl/Tk 9.0.3 source with MSYS2 UCRT64 tools in `C:\msys64`. The source tree is not required after installation because the runtime artifacts are committed under `tcltk/`.

Pino also vendors a minimal subset of Tcllib 2.0 for pure-Tcl SHA-256 and JSON support. App functionality should not depend on host OS utilities.

## Design

See `docs/design.md` for the product goals, repository format, command behavior, Tcl UI direction, data-safety rules, and implementation milestones.
