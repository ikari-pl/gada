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
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
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

// TestBuildIntegration_SyncMethods compiles and runs a program that
// calls every sync method lowering (RLock/RUnlock/TryRLock, Lock/
// Unlock/TryLock, WaitGroup, Once.Do), runtime.Gosched/GOMAXPROCS and
// a go-free time.Tick receive. Before the PR #46 review fixes the
// emitted Ada did not compile (wrong member names, Do without
// 'Access) and a Tick-only main never exited; the output is Go's.
func TestBuildIntegration_SyncMethods(t *testing.T) {
	if _, err := exec.LookPath("gprbuild"); err != nil {
		t.Skip("gprbuild not installed on PATH; integration test skipped")
	}
	pkg, err := filepath.Abs(filepath.Join("testdata", "sync_methods"))
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(pkg, "sync_methods")
	t.Cleanup(func() { _ = os.Remove(binary) })

	var stdout, stderr bytes.Buffer
	if code := runBuild([]string{pkg}, &stdout, &stderr); code != 0 {
		t.Fatalf("runBuild exit = %d\nstdout=%s\nstderr=%s", code, stdout.String(), stderr.String())
	}
	out, err := exec.Command(binary).Output()
	if err != nil {
		t.Fatalf("run produced binary: %v", err)
	}
	if want := "once\nprocs ok\ndone\n"; string(out) != want {
		t.Fatalf("output = %q, want %q", out, want)
	}
}

// TestBuildIntegration_EarlyReturn compiles and runs a main that returns
// early while a goroutine is parked forever on a channel and an hourly
// ticker is live. Go prints "before" then the deferred line and exits 0;
// before the fix the Ada main's `return;` skipped Exit_Main and the
// program hung waiting on the worker pool (ADR-0011).
func TestBuildIntegration_EarlyReturn(t *testing.T) {
	if _, err := exec.LookPath("gprbuild"); err != nil {
		t.Skip("gprbuild not installed on PATH; integration test skipped")
	}
	pkg, err := filepath.Abs(filepath.Join("testdata", "early_return"))
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(pkg, "early_return")
	t.Cleanup(func() { _ = os.Remove(binary) })

	var stdout, stderr bytes.Buffer
	if code := runBuild([]string{pkg}, &stdout, &stderr); code != 0 {
		t.Fatalf("runBuild exit = %d\nstdout=%s\nstderr=%s", code, stdout.String(), stderr.String())
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, binary).Output()
	if ctx.Err() != nil {
		t.Fatalf("binary did not exit within 30s (early return hung); output so far %q", out)
	}
	if err != nil {
		t.Fatalf("run produced binary: %v", err)
	}
	if want := "before\ndeferred\n"; string(out) != want {
		t.Fatalf("output = %q, want %q", out, want)
	}
}
