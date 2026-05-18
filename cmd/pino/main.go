package main

import (
	"fmt"
	"os"

	"github.com/anafalanx/pino/internal/launcher"
)

func main() {
	if err := launcher.Run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
