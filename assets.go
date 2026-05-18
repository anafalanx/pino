// Package pino embeds the Tcl application assets used by the Go launcher.
package pino

import "embed"

// Assets contains the Tcl application and the project-local Tcl/Tk runtime.
// The Go executable is currently a packaging shell around these files.
//
//go:embed tcl tcltk
var Assets embed.FS
