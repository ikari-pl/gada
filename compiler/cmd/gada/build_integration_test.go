//go:build integration

// Integration test for the `gada build` driver: end-to-end exercise
// of translate → emit → gprbuild against the testdata/hello fixture.
//
// Build-tagged integration so the default `go test ./...` invocation
// does not pull in gprbuild as a hard dependency. Run with:
//
//	go test -tags=integration ./cmd/gada/...
//
// The test skips (rather than fails) when gprbuild is missing so a
// developer with only Go installed can still run unit tests.

package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestBuildIntegration_Hello(t *testing.T) {
	if _, err := exec.LookPath("gprbuild"); err != nil {
		t.Skip("gprbuild not installed on PATH; integration test skipped")
	}

	pkg, err := filepath.Abs(filepath.Join("testdata", "hello"))
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(pkg, "hello")
	t.Cleanup(func() { _ = os.Remove(binary) })

	var stdout, stderr bytes.Buffer
	code := runBuild([]string{pkg}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("runBuild exit = %d\nstdout=%s\nstderr=%s", code, stdout.String(), stderr.String())
	}
	if _, err := os.Stat(binary); err != nil {
		t.Fatalf("expected binary at %s: %v", binary, err)
	}

	out, err := exec.Command(binary).Output()
	if err != nil {
		t.Fatalf("run produced binary: %v", err)
	}
	got := strings.TrimRight(string(out), "\n")
	if got != "hello, GADA" {
		t.Fatalf("output = %q, want %q", got, "hello, GADA")
	}
}
