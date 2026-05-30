package main

import (
	"bytes"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// TestRunBuild_NoArgs covers the usage-error branch: zero args ⇒ exit
// 2 with a "usage:" hint on stderr.
func TestRunBuild_NoArgs(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runBuild(nil, &stdout, &stderr)
	if code != 2 {
		t.Errorf("runBuild() exit = %d, want 2", code)
	}
	if got := stderr.String(); !strings.Contains(got, "usage:") {
		t.Errorf("stderr = %q, want substring %q", got, "usage:")
	}
	if got := stdout.String(); got != "" {
		t.Errorf("stdout = %q, want empty", got)
	}
}

// TestRunBuild_FlagLikeArg covers the case where the user passes a
// dash-prefixed token that we do not recognise as a path. We bail
// with the usage hint rather than passing it through to the loader.
func TestRunBuild_FlagLikeArg(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runBuild([]string{"--no-such-flag"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("runBuild(--no-such-flag) exit = %d, want 2", code)
	}
	if got := stderr.String(); !strings.Contains(got, "usage:") {
		t.Errorf("stderr = %q, want usage hint", got)
	}
}

// TestRunBuild_NonexistentPath exercises the resolve-stage failure: a
// path that does not exist on disk maps to exit 1 with a stage-tagged
// error.
func TestRunBuild_NonexistentPath(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runBuild([]string{"/this/path/does/not/exist/anywhere"}, &stdout, &stderr)
	if code != 1 {
		t.Errorf("runBuild() exit = %d, want 1", code)
	}
	if got := stderr.String(); !strings.Contains(got, "resolve:") {
		t.Errorf("stderr = %q, want substring %q", got, "resolve:")
	}
}

// TestRunBuild_NotADirectory exercises the resolve-stage check: a
// regular file is rejected because we only build directory-shaped
// packages.
func TestRunBuild_NotADirectory(t *testing.T) {
	tmp := t.TempDir()
	f := filepath.Join(tmp, "file.go")
	if err := os.WriteFile(f, []byte("package main\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	code := runBuild([]string{f}, &stdout, &stderr)
	if code != 1 {
		t.Errorf("runBuild(file) exit = %d, want 1", code)
	}
	if got := stderr.String(); !strings.Contains(got, "resolve:") || !strings.Contains(got, "not a directory") {
		t.Errorf("stderr = %q, want stage 'resolve' + 'not a directory'", got)
	}
}

// TestFindRuntimeProject_WalksUp exercises the success path of the
// runtime locator. From this test file's directory (compiler/cmd/gada)
// the locator must walk up to the repo root and find
// runtime/gada_core.gpr.
func TestFindRuntimeProject_WalksUp(t *testing.T) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	got, err := findRuntimeProject(cwd)
	if err != nil {
		t.Fatalf("findRuntimeProject(%q) error = %v", cwd, err)
	}
	if filepath.Base(got) != "gada_core.gpr" {
		t.Errorf("found %q, want a path ending in gada_core.gpr", got)
	}
	if !filepath.IsAbs(got) {
		t.Errorf("found %q, want an absolute path", got)
	}
}

// TestFindRuntimeProject_NotFound covers the error path: a directory
// far from any GADA checkout (the OS root) yields a clear failure
// pointing at the GADA_RUNTIME override.
func TestFindRuntimeProject_NotFound(t *testing.T) {
	t.Setenv("GADA_RUNTIME", "")
	root := "/"
	if runtime.GOOS == "windows" {
		root = `C:\`
	}
	_, err := findRuntimeProject(root)
	if err == nil {
		t.Fatal("expected error walking up from filesystem root, got nil")
	}
	if !strings.Contains(err.Error(), "GADA_RUNTIME") {
		t.Errorf("error = %v, want mention of GADA_RUNTIME override", err)
	}
}

// TestFindRuntimeProject_EnvOverrideHonoured: when $GADA_RUNTIME points
// at an existing file the locator returns it verbatim (no walk).
func TestFindRuntimeProject_EnvOverrideHonoured(t *testing.T) {
	tmp := t.TempDir()
	override := filepath.Join(tmp, "custom.gpr")
	if err := os.WriteFile(override, []byte("project Custom is end Custom;\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GADA_RUNTIME", override)

	got, err := findRuntimeProject("/some/unrelated/dir")
	if err != nil {
		t.Fatalf("findRuntimeProject error = %v", err)
	}
	if got != override {
		t.Errorf("got %q, want %q (override should be returned verbatim)", got, override)
	}
}

// TestFindRuntimeProject_EnvOverrideMissing: $GADA_RUNTIME pointing at
// a non-existent path is a hard error, not a silent fall-through to
// the upward walk. Treating it as an error catches typos that would
// otherwise pick up the wrong runtime by accident.
func TestFindRuntimeProject_EnvOverrideMissing(t *testing.T) {
	t.Setenv("GADA_RUNTIME", "/nope/not/a/real/path.gpr")
	_, err := findRuntimeProject(".")
	if err == nil {
		t.Fatal("expected error for missing GADA_RUNTIME, got nil")
	}
	if !strings.Contains(err.Error(), "does not exist") {
		t.Errorf("error = %v, want mention of 'does not exist'", err)
	}
}

// TestWriteProjectFile_Substitutes verifies the template renderer
// fills every {{.Field}} placeholder. Catches the easy regression of
// adding a field to the template without wiring projectFields.
func TestWriteProjectFile_Substitutes(t *testing.T) {
	tmp := t.TempDir()
	out := filepath.Join(tmp, "main.gpr")
	fields := projectFields{
		ProjectName:    "TestProj",
		RuntimeProject: "/path/to/gada_core",
		SourceDir:      "/src/dir",
		ObjectDir:      "/obj/dir",
		ExecDir:        "/exec/dir",
		MainFile:       "main.adb",
	}
	if err := writeProjectFile(out, fields); err != nil {
		t.Fatalf("writeProjectFile: %v", err)
	}
	body, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	rendered := string(body)
	for _, want := range []string{
		`with "/path/to/gada_core";`,
		"project TestProj is",
		`for Source_Dirs use ("/src/dir");`,
		`for Object_Dir  use "/obj/dir";`,
		`for Exec_Dir    use "/exec/dir";`,
		`for Main use ("main.adb");`,
		"end TestProj;",
	} {
		if !strings.Contains(rendered, want) {
			t.Errorf("rendered project missing %q\n--- rendered ---\n%s", want, rendered)
		}
	}
	if strings.Contains(rendered, "{{") || strings.Contains(rendered, "}}") {
		t.Errorf("rendered project still has unsubstituted placeholders:\n%s", rendered)
	}
}

// TestCopyExecutable_RoundTrip: copy a small file and verify the
// destination has the same bytes and is mode-0755.
func TestCopyExecutable_RoundTrip(t *testing.T) {
	tmp := t.TempDir()
	src := filepath.Join(tmp, "src")
	dst := filepath.Join(tmp, "dst")
	payload := []byte("not really an executable but close enough\n")
	if err := os.WriteFile(src, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := copyExecutable(src, dst); err != nil {
		t.Fatalf("copyExecutable: %v", err)
	}
	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, payload) {
		t.Errorf("dst contents = %q, want %q", got, payload)
	}
	info, err := os.Stat(dst)
	if err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS != "windows" && info.Mode().Perm() != 0o755 {
		t.Errorf("dst mode = %v, want 0755", info.Mode().Perm())
	}
}

// TestCopyExecutable_MissingSrc covers the obvious failure path so the
// error wrapping in buildPackage stays meaningful.
func TestCopyExecutable_MissingSrc(t *testing.T) {
	tmp := t.TempDir()
	err := copyExecutable(filepath.Join(tmp, "no-such-src"), filepath.Join(tmp, "dst"))
	if err == nil {
		t.Fatal("copyExecutable(missing src) error = nil, want non-nil")
	}
}

// TestStageError_Surface asserts the error string carries both the
// stage label and the underlying message; this is the contract every
// failing exit relies on.
func TestStageError_Surface(t *testing.T) {
	err := failStage("translate", os.ErrNotExist)
	if !strings.HasPrefix(err.Error(), "translate: ") {
		t.Errorf("error = %q, want a 'translate: ' prefix", err.Error())
	}
	se, ok := err.(*stageError)
	if !ok {
		t.Fatalf("failStage() type = %T, want *stageError", err)
	}
	if se.Unwrap() != os.ErrNotExist {
		t.Errorf("Unwrap() = %v, want os.ErrNotExist", se.Unwrap())
	}
}

// makeStandaloneModule turns dir into a self-contained Go module by
// dropping a minimal go.mod into it. packages.Load operates in module
// mode, so a tempdir without a module is a non-loadable input — these
// fixtures need their own module to surface the *intended* error
// (translate-stage rejection) instead of a generic "0 packages".
func makeStandaloneModule(t *testing.T, dir, name string) {
	t.Helper()
	body := "module " + name + "\n\ngo 1.22\n"
	if err := os.WriteFile(filepath.Join(dir, "go.mod"), []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
}

// withRuntimeOverride sets $GADA_RUNTIME to the in-repo gada_core.gpr
// for tests whose package directory lives in a tempdir outside the
// monorepo (so the upward-walk locator would otherwise fail at
// "resolve" before the test can reach the stage it actually exercises).
func withRuntimeOverride(t *testing.T) {
	t.Helper()
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	gpr, err := findRuntimeProject(cwd)
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("GADA_RUNTIME", gpr)
}

// stubGprbuild swaps runGprbuild for the duration of the test, with
// the supplied stub function. The stub is responsible for fabricating
// any artefacts (e.g. an exec_dir/main file) that buildPackage expects
// to exist on a real run. Restoration is registered via t.Cleanup.
func stubGprbuild(t *testing.T, stub func(gprPath string, stdout, stderr io.Writer) error) {
	t.Helper()
	old := runGprbuild
	runGprbuild = stub
	t.Cleanup(func() { runGprbuild = old })
}

// readGpr extracts the rendered project file's exec dir so stubs can
// fabricate the post-link binary in the right place.
func readGpr(t *testing.T, gprPath string) (execDir string) {
	t.Helper()
	body, err := os.ReadFile(gprPath)
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range strings.Split(string(body), "\n") {
		if i := strings.Index(line, `Exec_Dir    use "`); i >= 0 {
			rest := line[i+len(`Exec_Dir    use "`):]
			execDir = rest[:strings.Index(rest, `"`)]
		}
	}
	return execDir
}

// TestBuildPackage_HappyPathStubbed exercises the full driver against
// the testdata/hello fixture, with a stubbed gprbuild that fabricates
// an "exec_dir/main" file so the relocate step has something to copy.
// This covers translate → emit → render-gpr → relocate without
// requiring gprbuild on PATH.
func TestBuildPackage_HappyPathStubbed(t *testing.T) {
	pkg, err := filepath.Abs(filepath.Join("testdata", "hello"))
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(pkg, "hello")
	t.Cleanup(func() { _ = os.Remove(binary) })

	stubGprbuild(t, func(gprPath string, _, _ io.Writer) error {
		execDir := readGpr(t, gprPath)
		// Sanity-check the rendered .adb file is well-formed Ada.
		body, err := os.ReadFile(filepath.Join(filepath.Dir(gprPath), "main.adb"))
		if err != nil {
			return err
		}
		if !strings.Contains(string(body), "procedure Main is") {
			t.Errorf("emitted main.adb missing 'procedure Main is':\n%s", body)
		}
		if !strings.Contains(string(body), `Println ("hello, GADA")`) {
			t.Errorf("emitted main.adb missing fmt.Println translation:\n%s", body)
		}
		// Fabricate the binary that gprbuild would normally produce.
		return os.WriteFile(filepath.Join(execDir, "main"), []byte("#!/bin/sh\necho hello, GADA\n"), 0o755)
	})

	var stdout, stderr bytes.Buffer
	code := runBuild([]string{pkg}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("runBuild exit = %d\nstdout=%s\nstderr=%s", code, stdout.String(), stderr.String())
	}
	info, err := os.Stat(binary)
	if err != nil {
		t.Fatalf("expected binary at %s: %v", binary, err)
	}
	if info.Mode().Perm()&0o100 == 0 {
		t.Errorf("binary mode = %v, want exec bit set", info.Mode().Perm())
	}
}

// TestBuildPackage_GprbuildFailure: a gprbuild stub that returns an
// error must surface as a stage-tagged "gprbuild:" error.
func TestBuildPackage_GprbuildFailure(t *testing.T) {
	pkg, err := filepath.Abs(filepath.Join("testdata", "hello"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Remove(filepath.Join(pkg, "hello")) })

	wantErr := "stub: synthetic compile failure"
	stubGprbuild(t, func(string, io.Writer, io.Writer) error {
		return errSynthetic{msg: wantErr}
	})

	var stdout, stderr bytes.Buffer
	code := runBuild([]string{pkg}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit = %d, want 1", code)
	}
	if got := stderr.String(); !strings.Contains(got, "gprbuild:") || !strings.Contains(got, wantErr) {
		t.Errorf("stderr = %q, want stage 'gprbuild' + %q", got, wantErr)
	}
}

// errSynthetic is a tiny error type used by the stub above; declaring
// it inline keeps the test free of fmt.Errorf string-comparison games.
type errSynthetic struct{ msg string }

func (e errSynthetic) Error() string { return e.msg }

// TestBuildPackage_RelocateFailure: gprbuild "succeeds" but does not
// produce the expected exec_dir/main, so the post-build copy fails.
// This covers the gprbuild-stage relocate-error branch.
func TestBuildPackage_RelocateFailure(t *testing.T) {
	pkg, err := filepath.Abs(filepath.Join("testdata", "hello"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Remove(filepath.Join(pkg, "hello")) })

	stubGprbuild(t, func(string, io.Writer, io.Writer) error {
		// Do not fabricate the binary — copyExecutable will fail.
		return nil
	})

	var stdout, stderr bytes.Buffer
	code := runBuild([]string{pkg}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit = %d, want 1", code)
	}
	if got := stderr.String(); !strings.Contains(got, "gprbuild:") || !strings.Contains(got, "relocate binary") {
		t.Errorf("stderr = %q, want stage 'gprbuild' + 'relocate binary'", got)
	}
}

// TestBuildPackage_NotMain: a non-main package is rejected at the
// translate stage; we have not implemented Phase-1 emission for
// library packages.
func TestBuildPackage_NotMain(t *testing.T) {
	withRuntimeOverride(t)
	tmp := t.TempDir()
	makeStandaloneModule(t, tmp, "example.com/lib")
	src := filepath.Join(tmp, "lib.go")
	if err := os.WriteFile(src, []byte("package lib\n\nfunc Add(a, b int) int { return a + b }\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	var stdout, stderr bytes.Buffer
	code := runBuild([]string{tmp}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit = %d, want 1", code)
	}
	if got := stderr.String(); !strings.Contains(got, "translate:") || !strings.Contains(got, "package main") {
		t.Errorf("stderr = %q, want stage 'translate' + 'package main' message", got)
	}
}

// TestBuildPackage_MultipleFiles rejects multi-file packages at the
// translate stage. Phase 1 supports a single .go file per package; the
// next phase widens this.
func TestBuildPackage_MultipleFiles(t *testing.T) {
	withRuntimeOverride(t)
	tmp := t.TempDir()
	makeStandaloneModule(t, tmp, "example.com/multi")
	if err := os.WriteFile(filepath.Join(tmp, "a.go"),
		[]byte("package main\n\nfunc main() {}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmp, "b.go"),
		[]byte("package main\n\nfunc helper() {}\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	var stdout, stderr bytes.Buffer
	code := runBuild([]string{tmp}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit = %d, want 1", code)
	}
	if got := stderr.String(); !strings.Contains(got, "translate:") || !strings.Contains(got, "single .go file") {
		t.Errorf("stderr = %q, want stage 'translate' + 'single .go file'", got)
	}
}

// TestBuildPackage_PackageHasErrors covers the path where
// packages.Load returns a package object whose Errors slice is
// non-empty (e.g. a syntax error in the source).
func TestBuildPackage_PackageHasErrors(t *testing.T) {
	withRuntimeOverride(t)
	tmp := t.TempDir()
	makeStandaloneModule(t, tmp, "example.com/bad")
	if err := os.WriteFile(filepath.Join(tmp, "bad.go"),
		[]byte("package main\n\nfunc main( {\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	var stdout, stderr bytes.Buffer
	code := runBuild([]string{tmp}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit = %d, want 1", code)
	}
	if got := stderr.String(); !strings.Contains(got, "translate:") {
		t.Errorf("stderr = %q, want stage 'translate'", got)
	}
}

// TestBuildPackage_EmptyDir: a directory with no .go files is rejected
// (packages.Load returns zero packages, or one without sources).
func TestBuildPackage_EmptyDir(t *testing.T) {
	withRuntimeOverride(t)
	tmp := t.TempDir()

	var stdout, stderr bytes.Buffer
	code := runBuild([]string{tmp}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit = %d, want 1", code)
	}
	if got := stderr.String(); !strings.Contains(got, "translate:") {
		t.Errorf("stderr = %q, want stage 'translate'", got)
	}
}

// TestRunGprbuildDefault_NoBinary covers the production runGprbuild
// fallback when gprbuild is missing on PATH. We force the env to a
// minimal PATH that excludes gprbuild and assert the error mentions
// the missing tool.
func TestRunGprbuildDefault_NoBinary(t *testing.T) {
	if _, err := exec.LookPath("gprbuild"); err == nil {
		t.Skip("gprbuild on PATH; cannot exercise no-binary branch")
	}
	err := runGprbuild("/nonexistent.gpr", io.Discard, io.Discard)
	if err == nil {
		t.Fatal("runGprbuild error = nil, want non-nil")
	}
	if !strings.Contains(err.Error(), "gprbuild not found") {
		t.Errorf("error = %v, want mention of 'gprbuild not found'", err)
	}
}

// TestParseOtoolRpaths_DuplicateDetected exercises the duplicate-LC_RPATH
// scanner against an `otool -l` output snippet. Two LC_RPATH commands
// list the same toolchain lib dir; one LC_RPATH lists a different
// path; one LC_LOAD_DYLIB has a `path` field that must NOT be picked
// up. Only the duplicate should be reported.
func TestParseOtoolRpaths_DuplicateDetected(t *testing.T) {
	otool := `bin:
Load command 0
          cmd LC_LOAD_DYLIB
      cmdsize 56
         name /usr/lib/libSystem.B.dylib (offset 24)
   time stamp 2 Wed Dec 31 19:00:02 1969
Load command 1
          cmd LC_RPATH
      cmdsize 80
         path /home/u/.local/share/alire/toolchains/gnat_native_15/lib (offset 12)
Load command 2
          cmd LC_RPATH
      cmdsize 80
         path /home/u/.local/share/alire/toolchains/gnat_native_15/lib (offset 12)
Load command 3
          cmd LC_RPATH
      cmdsize 48
         path /opt/some-other/dir (offset 12)
`
	dups, err := parseOtoolRpaths(otool)
	if err != nil {
		t.Fatalf("parseOtoolRpaths: %v", err)
	}
	if len(dups) != 1 {
		t.Fatalf("dups = %v, want exactly 1 entry", dups)
	}
	want := "/home/u/.local/share/alire/toolchains/gnat_native_15/lib"
	if dups[want] != 2 {
		t.Errorf("dups[%q] = %d, want 2", want, dups[want])
	}
}

// TestParseOtoolRpaths_NoDuplicates: every LC_RPATH path is unique, so
// the result map is empty.
func TestParseOtoolRpaths_NoDuplicates(t *testing.T) {
	otool := `bin:
Load command 0
          cmd LC_RPATH
      cmdsize 32
         path /a (offset 12)
Load command 1
          cmd LC_RPATH
      cmdsize 32
         path /b (offset 12)
`
	dups, err := parseOtoolRpaths(otool)
	if err != nil {
		t.Fatalf("parseOtoolRpaths: %v", err)
	}
	if len(dups) != 0 {
		t.Errorf("dups = %v, want empty", dups)
	}
}

// TestParseOtoolRpaths_PathInOtherSection covers the "stray path
// keyword in a non-LC_RPATH section" guard: a `cmd LC_LOAD_DYLIB`
// followed by a path-shaped line must NOT be accumulated into the
// rpath set.
func TestParseOtoolRpaths_PathInOtherSection(t *testing.T) {
	otool := `bin:
Load command 0
          cmd LC_LOAD_DYLIB
      cmdsize 56
         path /not/an/rpath (offset 12)
Load command 1
          cmd LC_RPATH
      cmdsize 32
         path /real/rpath (offset 12)
`
	dups, err := parseOtoolRpaths(otool)
	if err != nil {
		t.Fatalf("parseOtoolRpaths: %v", err)
	}
	if _, found := dups["/not/an/rpath"]; found {
		t.Errorf("non-rpath path leaked into dups: %v", dups)
	}
	if len(dups) != 0 {
		t.Errorf("dups = %v, want empty", dups)
	}
}

// TestStripDuplicateRpaths_NonDarwinNoop: on non-darwin GOOS the
// helper returns nil without invoking otool. On darwin we skip — the
// integration test exercises the real path.
func TestStripDuplicateRpaths_NonDarwinNoop(t *testing.T) {
	if runtime.GOOS == "darwin" {
		t.Skip("non-darwin no-op only validated off darwin; integration test covers darwin")
	}
	var stderr bytes.Buffer
	if err := stripDuplicateRpaths("/this/binary/does/not/exist", &stderr); err != nil {
		t.Errorf("stripDuplicateRpaths on non-darwin returned %v, want nil", err)
	}
	if stderr.Len() != 0 {
		t.Errorf("stderr = %q, want empty (no-op should not warn)", stderr.String())
	}
}

// TestStripDuplicateRpaths_OtoolFailureWarnsButSucceeds: on darwin a
// missing path makes otool fail with non-zero exit. The helper logs
// to stderr and returns nil so the build still succeeds (the
// non-fatal cases — e.g. a binary that happens to be free of the
// dyld bug — still link cleanly). On non-darwin the function exits
// before invoking otool, so this assertion only fires on darwin.
func TestStripDuplicateRpaths_OtoolFailureWarnsButSucceeds(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("otool only present on darwin in CI matrices we care about")
	}
	// Use a path that doesn't exist — otool errors with non-zero exit
	// in that case (a non-Mach-O file is a softer failure: otool prints
	// 'is not an object file' to stderr and exits 0).
	missing := filepath.Join(t.TempDir(), "no-such-binary")
	var stderr bytes.Buffer
	if err := stripDuplicateRpaths(missing, &stderr); err != nil {
		t.Errorf("stripDuplicateRpaths returned %v, want nil (best-effort)", err)
	}
	if got := stderr.String(); !strings.Contains(got, "rpath fixup skipped") {
		t.Errorf("stderr = %q, want substring 'rpath fixup skipped'", got)
	}
}

// stubStripDuplicateRpaths swaps the package-level helper for the test
// duration, restoring on cleanup. Used by the happy-path test so the
// stubbed shell-script binary doesn't generate a stderr warning that
// other assertions would otherwise have to tolerate.
func stubStripDuplicateRpaths(t *testing.T, stub func(bin string, stderr io.Writer) error) {
	t.Helper()
	old := stripDuplicateRpaths
	stripDuplicateRpaths = stub
	t.Cleanup(func() { stripDuplicateRpaths = old })
}

// TestBuildPackage_RpathStripCalled asserts buildPackage invokes
// stripDuplicateRpaths against the relocated binary path. We swap the
// helper for a recorder; the recorder captures the path it is called
// with, which must match the destination binary location.
func TestBuildPackage_RpathStripCalled(t *testing.T) {
	pkg, err := filepath.Abs(filepath.Join("testdata", "hello"))
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(pkg, "hello")
	t.Cleanup(func() { _ = os.Remove(binary) })

	stubGprbuild(t, func(gprPath string, _, _ io.Writer) error {
		execDir := readGpr(t, gprPath)
		return os.WriteFile(filepath.Join(execDir, "main"), []byte("#!/bin/sh\necho hello, GADA\n"), 0o755)
	})

	var seen string
	stubStripDuplicateRpaths(t, func(bin string, _ io.Writer) error {
		seen = bin
		return nil
	})

	var stdout, stderr bytes.Buffer
	if code := runBuild([]string{pkg}, &stdout, &stderr); code != 0 {
		t.Fatalf("runBuild exit = %d\nstderr=%s", code, stderr.String())
	}
	if seen != binary {
		t.Errorf("rpath strip called with %q, want %q", seen, binary)
	}
}

// TestBuildPackage_RpathStripFailureSurfaces: a hard error from
// stripDuplicateRpaths must be reported as a "gprbuild:" stage failure
// (the post-link rpath fixup is part of producing a runnable binary).
func TestBuildPackage_RpathStripFailureSurfaces(t *testing.T) {
	pkg, err := filepath.Abs(filepath.Join("testdata", "hello"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Remove(filepath.Join(pkg, "hello")) })

	stubGprbuild(t, func(gprPath string, _, _ io.Writer) error {
		execDir := readGpr(t, gprPath)
		return os.WriteFile(filepath.Join(execDir, "main"), []byte("#!/bin/sh\necho hello\n"), 0o755)
	})
	stubStripDuplicateRpaths(t, func(string, io.Writer) error {
		return errSynthetic{msg: "synthetic install_name_tool failure"}
	})

	var stdout, stderr bytes.Buffer
	code := runBuild([]string{pkg}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit = %d, want 1", code)
	}
	if got := stderr.String(); !strings.Contains(got, "gprbuild:") || !strings.Contains(got, "rpath fixup") {
		t.Errorf("stderr = %q, want 'gprbuild:' + 'rpath fixup'", got)
	}
}

// TestRunBuild_ViaMainDispatch walks the dispatch one level up: `gada
// build` (with no path) should still surface the usage hint via the
// run() entry point that production main() calls.
func TestRunBuild_ViaMainDispatch(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"build"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("run(build) exit = %d, want 2", code)
	}
	if got := stderr.String(); !strings.Contains(got, "usage:") {
		t.Errorf("stderr = %q, want usage hint from runBuild", got)
	}
}

// TestGprArchArg_HostMapping pins the host-arch → libco ARCH scenario
// mapping. The host running the test is necessarily one gada build
// supports (the test binary itself is native), so on amd64/arm64 the
// mapping must resolve; anything else is a host we don't ship a libco
// backend for and correctly returns ok=false.
func TestGprArchArg_HostMapping(t *testing.T) {
	arch, ok := gprArchArg()
	switch runtime.GOARCH {
	case "amd64":
		if !ok || arch != "amd64" {
			t.Errorf("gprArchArg() = (%q, %v), want (\"amd64\", true)", arch, ok)
		}
	case "arm64":
		if !ok || arch != "aarch64" {
			t.Errorf("gprArchArg() = (%q, %v), want (\"aarch64\", true)", arch, ok)
		}
	default:
		if ok {
			t.Errorf("gprArchArg() = (%q, true) on unsupported host %q, want ok=false",
				arch, runtime.GOARCH)
		}
	}
}
