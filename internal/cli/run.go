package cli

import (
	"errors"
	"flag"
	"fmt"
	"io"

	"github.com/anafalanx/pino/internal/repo"
)

func Run(args []string) error {
	if len(args) == 0 {
		printUsage(flag.CommandLine.Output())
		return nil
	}

	switch args[0] {
	case "help", "-h", "--help":
		printUsage(flag.CommandLine.Output())
		return nil
	case "init":
		if len(args) > 1 {
			return fmt.Errorf("init: unexpected arguments: %v", args[1:])
		}
		return repo.Init(".")
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func printUsage(w io.Writer) {
	_, _ = fmt.Fprintln(w, "Pino - plain-text notes VCS")
	_, _ = fmt.Fprintln(w)
	_, _ = fmt.Fprintln(w, "Usage:")
	_, _ = fmt.Fprintln(w, "  pino <command>")
	_, _ = fmt.Fprintln(w)
	_, _ = fmt.Fprintln(w, "Commands:")
	_, _ = fmt.Fprintln(w, "  init      initialize .pino repository")
	_, _ = fmt.Fprintln(w, "  help      show this help")
}

var ErrNotImplemented = errors.New("not implemented")
