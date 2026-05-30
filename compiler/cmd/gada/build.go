// build.go implements the `gada build <path>` subcommand: the
// end-to-end pipeline that ties translate → emit → gprbuild together
// for the first time. Phase 1 scope: one Go source file, package
// main, the `hello, GADA` corpus.
//
// The pipeline:
//
//  1. Load the Go package at <path> via golang.org/x/tools/go/packages.
//  2. Translate its single AST file to GADA-IR (compiler/internal/translate).
//  3. Emit Ada source for that IR (compiler/internal/emit) into a
//     fresh tempdir under os.TempDir()/gada-build-<rand>/.
//  4. Render emit.ProjectTemplate to main.gpr in the same tempdir,
//     pointing at the in-repo runtime project (located by walking up
//     from <path> for runtime/gada_core.gpr; overridable by
//     $GADA_RUNTIME).
//  5. Invoke gprbuild -P main.gpr; on success copy the produced
//     binary to <path>/<basename-of-path>.
//
// All non-zero exits are tagged with the failing stage (resolve,
// translate, emit, gprbuild) so callers can act on the boundary.

package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"text/template"

	"github.com/gada-lang/gada/compiler/internal/emit"
	"github.com/gada-lang/gada/compiler/internal/translate"
	"golang.org/x/tools/go/packages"
)

// runBuild parses `gada build <path>` arguments and dispatches to
// buildPackage. Returns a process exit code in the same convention as
// run(): 0 success, 2 usage error, 1 stage failure.
func runBuild(args []string, stdout, stderr io.Writer) int {
	if len(args) != 1 || strings.HasPrefix(args[0], "-") {
		_, _ = fmt.Fprintln(stderr, "usage: gada build <path>")
		return 2
	}
	if err := buildPackage(args[0], stdout, stderr); err != nil {
		_, _ = fmt.Fprintln(stderr, "gada build:", err)
		return 1
	}
	return 0
}

// stageError tags an error with the pipeline stage that produced it
// (resolve / translate / emit / gprbuild). The stage label appears in
// the error message so log scrapers and humans can localise failures
// without parsing free-form text.
type stageError struct {
	stage string
	err   error
}

func (e *stageError) Error() string { return e.stage + ": " + e.err.Error() }
func (e *stageError) Unwrap() error { return e.err }

func failStage(stage string, err error) error { return &stageError{stage: stage, err: err} }

// buildPackage runs the full driver against the directory at pkgPath.
// It writes gprbuild's stdout to stdout and gprbuild's stderr to
// stderr; everything else is returned as a stageError.
func buildPackage(pkgPath string, stdout, stderr io.Writer) error {
	abs, err := filepath.Abs(pkgPath)
	if err != nil {
		return failStage("resolve", err)
	}
	info, err := os.Stat(abs)
	if err != nil {
		return failStage("resolve", err)
	}
	if !info.IsDir() {
		return failStage("resolve", fmt.Errorf("%s is not a directory", abs))
	}

	runtimeProj, err := findRuntimeProject(abs)
	if err != nil {
		return failStage("resolve", err)
	}

	// Stage: translate (load + IR conversion).
	cfg := &packages.Config{
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedSyntax |
			packages.NeedTypes | packages.NeedTypesInfo,
		Dir: abs,
	}
	loaded, err := packages.Load(cfg, ".")
	if err != nil {
		return failStage("translate", fmt.Errorf("packages.Load: %w", err))
	}
	if len(loaded) != 1 {
		return failStage("translate", fmt.Errorf("expected 1 package, got %d", len(loaded)))
	}
	p := loaded[0]
	if len(p.Errors) > 0 {
		return failStage("translate", fmt.Errorf("package %s has errors: %v", p.PkgPath, p.Errors))
	}
	if len(p.Syntax) == 0 {
		return failStage("translate", fmt.Errorf("no Go source files in %s", abs))
	}
	if len(p.Syntax) != 1 {
		return failStage("translate",
			fmt.Errorf("phase 1 supports a single .go file per package, got %d", len(p.Syntax)))
	}

	irPkg, err := translate.File(p.Syntax[0], p.TypesInfo)
	if err != nil {
		return failStage("translate", err)
	}
	if irPkg.Name != "main" {
		return failStage("translate",
			fmt.Errorf("phase 1 supports `package main` only, got %q", irPkg.Name))
	}
	irPkg.Files[0].Name = p.GoFiles[0]

	// Stage: emit (Ada source + project file in tempdir).
	tmp, err := os.MkdirTemp("", "gada-build-")
	if err != nil {
		return failStage("emit", err)
	}
	objDir := filepath.Join(tmp, "obj")
	execDir := filepath.Join(tmp, "exec")
	for _, d := range []string{objDir, execDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return failStage("emit", err)
		}
	}

	mainAdb := filepath.Join(tmp, "main.adb")
	out, err := os.Create(mainAdb)
	if err != nil {
		return failStage("emit", err)
	}
	if err := emit.Package(irPkg, out); err != nil {
		_ = out.Close()
		return failStage("emit", err)
	}
	if err := out.Close(); err != nil {
		return failStage("emit", err)
	}

	gprPath := filepath.Join(tmp, "main.gpr")
	if err := writeProjectFile(gprPath, projectFields{
		ProjectName:    "Main",
		RuntimeProject: strings.TrimSuffix(runtimeProj, ".gpr"),
		SourceDir:      tmp,
		ObjectDir:      objDir,
		ExecDir:        execDir,
		MainFile:       "main.adb",
	}); err != nil {
		return failStage("emit", err)
	}

	// Stage: gprbuild (invoke + relocate binary). The runner is stored
	// as a package-level variable so tests can stub it without
	// requiring an installed gprbuild — see build_test.go.
	if err := runGprbuild(gprPath, stdout, stderr); err != nil {
		return failStage("gprbuild", err)
	}

	binBase := filepath.Base(abs)
	finalBin := filepath.Join(abs, binBase)
	if err := copyExecutable(filepath.Join(execDir, "main"), finalBin); err != nil {
		return failStage("gprbuild", fmt.Errorf("relocate binary: %w", err))
	}

	// macOS Sequoia (Darwin 25+) dyld aborts on duplicate LC_RPATH load
	// commands. GNAT 15 + gprbuild 25 emit two identical rpath entries
	// pointing at the toolchain lib dir, so the resulting binary fails
	// to launch with `dyld: duplicate LC_RPATH '<path>'` and exit 134.
	// Mirror the post-link fixup `runtime/tests/run_tests.sh` already
	// applies to the AUnit test runner: detect duplicate LC_RPATH
	// entries via `otool -l` and `install_name_tool -delete_rpath` each
	// duplicate once. On Linux / older macOS this is a no-op.
	if err := stripDuplicateRpaths(finalBin, stderr); err != nil {
		return failStage("gprbuild", fmt.Errorf("rpath fixup: %w", err))
	}

	// Tempdir is removed only on success — keep it around on failure
	// so a developer can reproduce the gprbuild invocation by hand.
	_ = os.RemoveAll(tmp)
	return nil
}

// stripDuplicateRpaths is a no-op on non-darwin platforms. On darwin it
// inspects the binary's LC_RPATH load commands via otool, and for any
// path that appears more than once invokes `install_name_tool
// -delete_rpath <path> <bin>` (which removes a single occurrence per
// call) until the duplicate count is gone. Returning a non-nil error
// only on hard failures: missing tools surface a stderr warning and
// return nil so a binary that happens to be free of the dyld bug still
// links cleanly. Stored as a package-level variable so tests can stub.
var stripDuplicateRpaths = func(bin string, stderr io.Writer) error {
	if runtime.GOOS != "darwin" {
		return nil
	}
	dups, err := duplicateRpaths(bin)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "gada build: rpath fixup skipped (%v)\n", err)
		return nil
	}
	for path, count := range dups {
		// install_name_tool removes one occurrence per invocation; loop
		// until the duplicate is collapsed to a single entry.
		for n := count; n > 1; n-- {
			cmd := exec.Command("install_name_tool", "-delete_rpath", path, bin)
			if out, err := cmd.CombinedOutput(); err != nil {
				return fmt.Errorf("install_name_tool -delete_rpath %s: %w (%s)",
					path, err, strings.TrimSpace(string(out)))
			}
		}
	}
	return nil
}

// duplicateRpaths runs `otool -l <bin>` and returns a map of LC_RPATH
// path → occurrence count, restricted to paths that appear more than
// once. Parsing is delegated to parseOtoolRpaths so the textual
// scanning is unit-testable on every platform.
func duplicateRpaths(bin string) (map[string]int, error) {
	out, err := exec.Command("otool", "-l", bin).Output()
	if err != nil {
		return nil, fmt.Errorf("otool -l %s: %w", bin, err)
	}
	return parseOtoolRpaths(string(out))
}

// parseOtoolRpaths scans `otool -l` output and returns LC_RPATH paths
// that appear more than once. The Mach-O load-command shape for an
// LC_RPATH section reads like:
//
//	Load command N
//	          cmd LC_RPATH
//	      cmdsize 56
//	         path /some/dir (offset 12)
//
// We scan for `cmd LC_RPATH` lines and read the next `path <p>` line,
// stripping the trailing " (offset N)" decoration. Any other `cmd <X>`
// line resets the in-rpath state so a stray `path` keyword in an
// unrelated section can't be misattributed.
func parseOtoolRpaths(otoolOutput string) (map[string]int, error) {
	counts := make(map[string]int)
	scanner := bufio.NewScanner(strings.NewReader(otoolOutput))
	inRpath := false
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		switch {
		case strings.HasPrefix(line, "cmd LC_RPATH"):
			inRpath = true
		case inRpath && strings.HasPrefix(line, "path "):
			rest := strings.TrimPrefix(line, "path ")
			if i := strings.Index(rest, " (offset "); i >= 0 {
				rest = rest[:i]
			}
			counts[rest]++
			inRpath = false
		case strings.HasPrefix(line, "cmd "):
			inRpath = false
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan otool output: %w", err)
	}
	for k, v := range counts {
		if v < 2 {
			delete(counts, k)
		}
	}
	return counts, nil
}

// gprArchArg maps the host Go architecture to the `ARCH` scenario
// value gada_core.gpr uses to pick libco's per-arch context-switch
// backend (amd64.c vs aarch64.c — see ADR-0007 §5). It returns
// ("", false) for architectures the runtime does not yet ship a libco
// backend for, in which case we leave the project's own default in
// place rather than force an invalid value.
//
// This MUST be passed to gprbuild: gada_core.gpr declares
// `Arch : Arch_Type := external ("ARCH", "amd64")`, defaulting to
// amd64. The runtime Makefile exports ARCH from `uname -m` for its own
// builds, but the `gada build` pipeline has no such environment, so
// without an explicit `-XARCH` every goroutine binary on an arm64 host
// silently links the amd64 co_swap blob and dies with
// EXC_BAD_INSTRUCTION the first time a goroutine context-switches.
func gprArchArg() (string, bool) {
	switch runtime.GOARCH {
	case "amd64":
		return "amd64", true
	case "arm64":
		return "aarch64", true
	default:
		return "", false
	}
}

// runGprbuild invokes `gprbuild -P <gprPath> [-XARCH=<arch>]`, streaming
// stdout/stderr to the supplied writers. It is a package-level variable
// so tests can substitute a stub when gprbuild is not installed;
// production code always uses the real exec call below.
var runGprbuild = func(gprPath string, stdout, stderr io.Writer) error {
	if _, err := exec.LookPath("gprbuild"); err != nil {
		return fmt.Errorf("gprbuild not found on PATH: %w", err)
	}
	args := []string{"-P", gprPath}
	if arch, ok := gprArchArg(); ok {
		args = append(args, "-XARCH="+arch)
	}
	cmd := exec.Command("gprbuild", args...)
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	return cmd.Run()
}

// projectFields are the substitution variables consumed by
// emit.ProjectTemplate.
type projectFields struct {
	ProjectName    string
	RuntimeProject string
	SourceDir      string
	ObjectDir      string
	ExecDir        string
	MainFile       string
}

// writeProjectFile renders emit.ProjectTemplate into path.
func writeProjectFile(path string, fields projectFields) error {
	tpl, err := template.New("gpr").Parse(emit.ProjectTemplate)
	if err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()
	return tpl.Execute(f, fields)
}

// findRuntimeProject locates runtime/gada_core.gpr by walking up from
// start. $GADA_RUNTIME (an absolute path to gada_core.gpr) overrides
// the search and is the deployment escape hatch for builds outside
// the monorepo. Phase 5+ will replace this with a packaged runtime
// resolved relative to the gada binary itself.
func findRuntimeProject(start string) (string, error) {
	if v := os.Getenv("GADA_RUNTIME"); v != "" {
		if _, err := os.Stat(v); err == nil {
			return v, nil
		}
		return "", fmt.Errorf("GADA_RUNTIME=%s does not exist", v)
	}
	dir := start
	for {
		cand := filepath.Join(dir, "runtime", "gada_core.gpr")
		if _, err := os.Stat(cand); err == nil {
			return cand, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("runtime/gada_core.gpr not found walking up from %s; set GADA_RUNTIME=<abs path to gada_core.gpr> to override", start)
		}
		dir = parent
	}
}

// copyExecutable copies src to dst preserving 0755 permissions. Used
// to relocate gprbuild's output from exec_dir/main to <pkg>/<base>.
func copyExecutable(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer func() { _ = in.Close() }()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o755)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		_ = out.Close()
		return err
	}
	return out.Close()
}
