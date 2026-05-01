// Command gada is the GADA compiler driver.
//
// Phase 0 implemented `gada --version`; Phase 1 added the `gada build
// <path>` subcommand (see build.go). Every additional flag, subcommand,
// and behavior is added in later phases under its own roadmap item
// with its own verify command.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/gada-lang/gada/compiler/internal/version"
)

// osExit is taken via an indirection so tests can intercept process exit
// when exercising main(). Tests must restore it on cleanup.
var osExit = os.Exit

func main() {
	osExit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run is the testable compiler entry point. It returns the process exit
// code instead of calling os.Exit directly so the same code path is
// reachable from unit tests.
//
// Contract:
//   - `--version`           prints the Describe() string to stdout, returns 0
//   - `build <path>`        runs the transpile-compile pipeline (see build.go)
//   - any other invocation  prints a hint to stderr and returns 2 so wrappers
//     that forget the flag fail loudly
func run(args []string, stdout, stderr io.Writer) int {
	if len(args) > 0 && args[0] == "build" {
		return runBuild(args[1:], stdout, stderr)
	}

	fs := flag.NewFlagSet("gada", flag.ContinueOnError)
	fs.SetOutput(stderr)
	showVersion := fs.Bool("version", false, "print version and exit")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	if *showVersion {
		// Errors writing to stdout/stderr are non-actionable for a CLI
		// driver: if our own pipes are broken, panicking or returning a
		// distinct code helps no one. Discard the result explicitly so
		// errcheck stays satisfied without sprinkling noise across calls.
		_, _ = fmt.Fprintln(stdout, version.Describe())
		return 0
	}

	_, _ = fmt.Fprintln(stderr, "gada: no command given (try --version or build <path>)")
	return 2
}
