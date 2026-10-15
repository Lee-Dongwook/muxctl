package cmd

import (
	"fmt"
	"io"
)

var version = "dev"

func usage(w io.Writer) {
	_, _ = fmt.Fprintln(w, "Usage:")
}

func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		usage(stderr)
		return 2
	}

	switch args[0] {
	case "version":
		_, _ = fmt.Fprintln(stdout, version)
		return 0
	default:
		usage(stderr)
		return 2
	}
}
