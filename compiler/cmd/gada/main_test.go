package main

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

// TestRun_VersionFlag covers the --version branch: stdout gets the version
// string, stderr stays empty, exit code is 0.
func TestRun_VersionFlag(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"--version"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("run --version exit = %d (stderr=%q), want 0", code, stderr.String())
	}
	if got := stdout.String(); !strings.HasPrefix(got, "gada ") {
		t.Errorf("run --version stdout = %q, want a 'gada '-prefixed line", got)
	}
	if got := stderr.String(); got != "" {
		t.Errorf("run --version stderr = %q, want empty", got)
	}
}

// TestRun_NoArgs covers the default branch: stderr gets the hint, exit
// code is 2 so scripts that forget the flag fail loudly.
func TestRun_NoArgs(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run(nil, &stdout, &stderr)
	if code != 2 {
		t.Errorf("run with no args exit = %d, want 2", code)
	}
	if got := stderr.String(); !strings.Contains(got, "no command given") {
		t.Errorf("run with no args stderr = %q, want substring 'no command given'", got)
	}
	if got := stdout.String(); got != "" {
		t.Errorf("run with no args stdout = %q, want empty", got)
	}
}

// TestRun_UnknownFlag covers the parse-error branch: an unrecognised flag
// makes flag.ContinueOnError return an error, which run() converts to 2.
func TestRun_UnknownFlag(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"--definitely-not-a-flag"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("run with unknown flag exit = %d, want 2", code)
	}
}

// TestMain_DispatchesViaOsExit covers the trivial main() wrapper. We swap
// osExit so the test process is not actually torn down, drive --version
// through os.Args, and verify the exit code that main() forwarded.
func TestMain_DispatchesViaOsExit(t *testing.T) {
	oldExit := osExit
	oldArgs := os.Args
	t.Cleanup(func() {
		osExit = oldExit
		os.Args = oldArgs
	})

	captured := -1
	osExit = func(code int) { captured = code }
	os.Args = []string{"gada", "--version"}

	main()

	if captured != 0 {
		t.Errorf("main(--version) os.Exit code = %d, want 0", captured)
	}
}
