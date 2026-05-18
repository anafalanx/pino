package main

import (
	"fmt"
	"os"

	"github.com/anafalanx/pino/internal/cli"
)

func main() {
	if err := cli.Run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
