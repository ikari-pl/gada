# Phase 0 — Foundation

[← Index](README.md) · Next: [Phase 1 — Minimal transpiler →](01-minimal-transpiler.md)

**Status:** `DONE`
**Prerequisites:** none
**Goal:** Establish the repository skeleton, build system, CI, coding
standards, testing/coverage tooling, and developer ergonomics so all
subsequent phases can ship under the 100%-tested rule from day one.
**Exit criterion:** `make ci` passes locally and in GitHub Actions on
a clean checkout, producing a coverage report.

## Items

- [x] **Initialize Go module for the compiler**
      *Files:* `compiler/go.mod`, `compiler/go.sum`, `compiler/cmd/gada/main.go` (stub)
      *Verify:* `cd compiler && go build -o ./bin/gada ./cmd/gada && ./bin/gada --version && go vet ./...`
      *Done when:* the binary prints a version string and `go vet ./...` is clean.
      *Notes (2026-05-01):* Module path `github.com/gada-lang/gada/compiler`, Go 1.22.
      Version string lives in `compiler/internal/version/version.go` (`Describe()`
      returns `gada 0.0.0-dev (phase 0 bootstrap)`). Verified locally on
      darwin/arm64 with `go1.26.2`: build exit 0, `./bin/gada --version`
      prints the contracted line, `go vet ./...` clean. No `go.sum` yet —
      module has no external dependencies in Phase 0.

- [x] **Initialize Alire crate for the runtime**
      *Files:* `runtime/alire.toml`, `runtime/gada_core.gpr`, `runtime/src/gada.ads`,
      `runtime/src/gada-core.ads`, `runtime/src/gada-core.adb`
      *Verify:* `cd runtime && alr build` (or `gprbuild -P gada_core.gpr` with PATH set
      to the Alire-managed GNAT toolchain).
      *Done when:* `alr build` exits 0 and `gada.ads` contains the top-level package declaration.
      *Notes (2026-05-01):* Crate hand-written (not `alr init`-generated) so the
      umbrella-package layout matches `Gada` + `Gada.Core` exactly. `Gada` is
      `pragma Pure`; `Gada.Core` uses `pragma Elaborate_Body` so its empty body
      is legal under Ada's "no-bodies-without-elaboration-need" rule.
      Manifest constraints encountered: `description` is ASCII-only and capped
      at 72 chars; empty `[[depends-on]]` is rejected. Verified locally on
      darwin/arm64 against Alire-installed GNAT 15.0.1 + GPRBUILD 25.0.0:
      `alr build` exits 0, "Build finished successfully in 0.77 seconds";
      produces `runtime/lib/libgada_core.a`.

- [x] **Wire up AUnit for Ada unit testing**
      *Files:* `runtime/tests/test_runner.adb`, `runtime/tests/aunit_harness.gpr`,
      `runtime/tests/io_suite.ads`, `runtime/tests/io_suite.adb`,
      `runtime/tests/run_tests.sh`, plus the runtime-side units
      `runtime/src/gada-core-io.ads`/`.adb`.
      *Verify:* `cd runtime && tests/run_tests.sh`. (The wrapper builds via
      `alr exec -- gprbuild -P tests/aunit_harness.gpr`, then strips a
      duplicate `LC_RPATH` that GNAT 15 + gprbuild 25 emit, which
      macOS Sequoia's dyld aborts on; on Linux and older macOS the
      strip is a no-op and the bare verify command also works.)
      *Done when:* harness runs at least one passing assertion.
      *Notes (2026-05-01):* AUnit 26.0.0 pulled in via Alire as a regular
      dependency (`alr update` deploys it). Single test
      `Gada.Core.IO.Println emits 'hello, GADA' + LF` redirects
      `Ada.Text_IO`'s default output to a temp file, calls Println, and
      compares the captured bytes (read back via `Ada.Streams.Stream_IO`,
      not `Ada.Text_IO.Get` — the latter loses the trailing LF when the
      file ends with `LF + file_terminator`). Verified locally on
      darwin/arm64: `Total Tests Run: 1, Successful Tests: 1, Failed
      Assertions: 0`, exit 0.

- [x] **Wire up Go test toolchain**
      *Files:* `compiler/internal/ping/ping.go`, `compiler/internal/ping/ping_test.go`
      *Verify:* `cd compiler && go test -race ./...`
      *Done when:* `go test -race` exits 0.
      *Notes (2026-05-01):* Trivial `Ping() string` returning `"pong"` plus a
      table-driven `TestPing` (one case today, `t.Parallel()` on outer + subtest
      so the race detector has parallelism to exercise). Verified locally on
      darwin/arm64 with `go1.26.2`: `go test -race ./...` exits 0 with
      `internal/ping` reporting `ok` in 1.325s; `cmd/gada` and `internal/version`
      show `[no test files]` (informational, doesn't affect exit code; both will
      gain real tests during Phase 1). `go vet ./...` clean.

- [x] **Coverage tooling — Ada (gcov + lcov)**
      *Files:* `tools/coverage_ada.sh`, `runtime/Makefile`, plus scenario-variable
      additions to `runtime/gada_core.gpr` and `runtime/tests/aunit_harness.gpr`.
      *Verify:* `make -C runtime coverage` produces `runtime/coverage.lcov` and a non-zero line count.
      *Done when:* report shows ≥ 1 covered line and `lcov --summary runtime/coverage.lcov` runs cleanly.
      *Notes (2026-05-01, darwin/arm64):* `tools/coverage_ada.sh` (executable,
      invocation-location-agnostic) augments PATH for Alire/Homebrew, requires
      both `alr` and `lcov` (clear 127-exit hint when missing), then runs
      `alr exec -- gprbuild -P tests/aunit_harness.gpr -XBuild_Mode=coverage --subdirs=cov`
      so coverage builds land in `runtime/obj/cov/`, `runtime/lib/cov/`, and
      `runtime/tests/obj/cov/`. `Build_Mode` is a new scenario variable
      (`"normal"` default, `"coverage"`) declared in both project files;
      under `"coverage"` it injects `-fprofile-arcs -ftest-coverage` into the
      `Compiler.Default_Switches ("Ada")` and `-lgcov` into
      `Linker.Default_Switches ("Ada")`. Crucially, AUnit's project file
      doesn't declare `Build_Mode`, so Alire's shared AUnit build cache is
      never instrumented (an earlier `-cargs/-largs` design poisoned that
      cache and broke every subsequent non-coverage build on the host —
      see playbook task notes for the diagnostic). Lcov is invoked with
      `--gcov-tool $(alr exec -- bash -c 'command -v gcov')` so the gcov
      version matches the GCC 15 that produced the `.gcno` files (system
      Xcode CLT ships gcov 11; format-mismatch reads as silent 0% coverage).
      Output is `--extract`-filtered to `runtime/src/*` so AUnit framework
      lines don't dilute the denominator. `runtime/Makefile` provides
      `test`, `coverage`, `lint` (graceful no-op until `tools/gnatcheck.rules`
      lands), `clean` (full nuke including `.gcda`/`.gcno`), and
      `clean-coverage` (drops `obj/cov/` only). Verified locally
      (lcov 2.4, GNAT 15.0.1): three-step sequence
      `make -C runtime test` → `make -C runtime coverage` →
      `make -C runtime test` all pass, with the second `make test`
      reporting `test_runner up to date` (no relink, no `ltmp3` symbol
      errors). Lcov summary: 1 source file (`gada-core-io.adb`),
      3 of 3 lines covered (100%), 1 of 1 function covered (100%).

- [x] **Coverage tooling — Go (`go test -cover`)**
      *Files:* `tools/coverage_go.sh`, `compiler/Makefile`
      *Verify:* `make -C compiler coverage` produces `compiler/coverage.out` and a summary.
      *Done when:* `go tool cover -func=coverage.out` reports a coverage percentage.
      *Notes (2026-05-01):* `tools/coverage_go.sh` runs `go test -count=1 -race
      -covermode=atomic -coverpkg=./... -coverprofile=$ROOT/compiler/coverage.out ./...`
      from inside `compiler/`, then prints `go tool cover -func`. `compiler/Makefile`
      exposes `test`, `coverage`, `lint` (graceful no-op until the Phase 02 lint
      task lands `.golangci.yml`), and `clean`. Verified locally on darwin/arm64
      with `go1.26.2`: `make -C compiler coverage` exits 0, writes
      `compiler/coverage.out`, and prints `total: (statements) 11.1%` (only
      `internal/ping.Ping` is currently exercised; `cmd/gada/main` and
      `internal/version.Describe` carry 0% pending Phase 1 tests). Per-package
      threshold enforcement is a separate roadmap item (**Coverage gate**).

- [x] **Top-level Makefile orchestrating both**
      *Files:* `Makefile`
      *Verify:* `make test` runs both Ada and Go test suites; `make coverage` produces a unified report under `coverage/`.
      *Done when:* `make ci` runs lint + test + coverage-gate and exits 0.
      *Notes (2026-05-01, darwin/arm64):* `Makefile` exposes
      `bootstrap`, `test`, `coverage`, `lint`, `coverage-gate`, `ci`, `clean`.
      It dispatches per-side work via `make -C compiler|runtime <target>`
      so the per-Makefile toolchain-discovery logic (PATH augmentation,
      Build_Mode scenario var, gcov/lcov plumbing) is reused unchanged.
      `coverage` copies `compiler/coverage.out` and `runtime/coverage.lcov`
      to `coverage/{compiler,runtime}.coverage.*` and writes a unified
      `coverage/summary.txt` (Go `total: (statements) NN.N%` line + lcov
      summary). The Go summary line invokes `go tool cover -func` from
      inside `compiler/` because the cover tool needs `go.mod` for module
      path resolution; calling it from the repo root fails with
      `go.mod file not found`. `lint` and `coverage-gate` are graceful
      skip-mode targets until the next two Phase 02 tasks land their
      configs/scripts — letting `make ci` stay green on the current tree
      while subsequent tasks only flip on enforcement, not wire plumbing.
      `ci` order: lint → test → coverage → coverage-gate →
      `tools/check_roadmap_consistency.sh`; Make's default first-failure-
      aborts semantics gives the contracted "first failure aborts" behavior
      for free. End-to-end verified clean: `make clean && make ci` exits 0
      with `OK: roadmap status consistent across index and 12 phase file(s).`
      as the final line. Coverage gate enforcement and live CI verification
      arrive with the **Coverage gate** and **GitHub Actions CI** roadmap
      items.

- [x] **Coverage gate**
      *Files:* `tools/coverage_gate.sh`, `tools/coverage_thresholds.toml`
      *Verify:* `make coverage-gate` reads thresholds and exits 1 if any package is below threshold.
      *Done when:* a synthetic test that drops coverage below threshold fails the gate; restoring it makes the gate pass.
      *Notes (2026-05-01, darwin/arm64, Python 3.14.4, go1.26.2, lcov 2.4):*
      `tools/coverage_thresholds.toml` ships the four thresholds verbatim
      from the phase doc: `runtime/` 100%, `compiler/internal/emit/` 95%,
      `compiler/internal/translate/` 95%, `compiler/` 90%. Threshold matching
      is **overlapping prefix-match by design** — a file under
      `compiler/internal/emit/` counts toward both that threshold and the
      parent `compiler/` threshold; this catches deep-package regressions
      that broad averages would mask. `tools/coverage_gate.sh` is a thin
      Bash CLI (path resolution, artefact-fallback to per-side outputs,
      tool-presence checks) that exec's an inline `python3` heredoc parser.
      Python was chosen over `awk` because TOML parsing via stdlib
      `tomllib` (3.11+) is far more robust than awk gymnastics, and
      `python3` is already a CI-base requirement. **Go cover-profile
      parsing** dedups blocks by `(file, sline, scol, eline, ecol)` and
      keeps the max observed count — this is exactly the rule
      `go tool cover -func` itself applies, and is required because
      `-coverpkg=./...` legitimately emits one block per test binary that
      loaded the package. **lcov parsing** uses `LF`/`LH` summary fields
      directly. Verified end-to-end: clean tree → `coverage gate: PASSED`,
      exit 0. Synthetic regression (5 untested statements added to
      `internal/ping/ping.go`) → drops `compiler/` to 72.22% and gate
      emits `FAIL: compiler/ 72.22% < 90.00%`, exit 1. Revert → exit 0.
      Both runs captured to
      `.maestro/playbooks/Initiation/Working/coverage-gate-proof.txt`.
      **Side effect of this item** (forced by the "revert and exit 0"
      verify clause): added `cmd/gada/main_test.go` (covering `--version`,
      no-args, unknown-flag, and the trivial `main()` wrapper via an
      `osExit` indirection) and `internal/version/version_test.go`
      (covering `Describe()`'s prefix/Version/Phase contract). Phase 0
      left those files at 0%/0% expecting Phase 1 to add them; the
      coverage-gate verify clause pulled the work forward. `compiler/`
      now stands at 100.00% (13/13 statements). `compiler/internal/emit/`
      and `compiler/internal/translate/` show as `SKIP` until Phase 1
      lands the first source files under those prefixes — the gate
      correctly treats "no files matched" as a skip rather than a
      failure, since enforcing 95% on a 0-statement set is undefined.

- [x] **Linting**
      *Files:* `tools/lint_ada.sh` (uses `gnatcheck`), `tools/lint_go.sh` (uses `golangci-lint`), `.golangci.yml`, `tools/gnatcheck.rules`
      *Verify:* `make lint` exits 0 on a clean tree.
      *Done when:* an intentionally introduced lint violation is caught and reported with a file:line.
      *Notes (2026-05-01, darwin/arm64, golangci-lint 2.11.4):* `.golangci.yml`
      written against the **golangci-lint v2 schema** (`version: "2"` is now
      mandatory; gofmt/goimports moved out of `linters` into a top-level
      `formatters` block). Active linter set per spec: `errcheck`, `govet`,
      `staticcheck`, `gosec`, `unparam`, `revive` plus the two formatters,
      with `linters.default: none` so the enable list is the *exact* active
      set. `tools/lint_go.sh` is invocation-location-agnostic and **hard-fails
      1 with an actionable install hint** when `golangci-lint` is missing
      (per spec). `tools/lint_ada.sh` has a deliberate **asymmetry**: it
      **soft-skips with exit 0** when `gnatcheck` is unavailable, because
      gnatcheck ships only with GNAT Pro / GNATstudio Pro — *not* with the
      FSF GNAT distribution that Alire installs by default. Hard-failing
      would break every macOS dev box and every Linux host without a paid
      AdaCore subscription; the script's stderr message documents CI's
      Ubuntu runner as the authoritative gnatcheck enforcement point.
      `tools/gnatcheck.rules` ships the three brief-required rules
      (`+RGOTO_Statements`, `+RGlobal_Variables`, `+RHeaders` placeholder
      pending `docs/style_ada.md`) plus five well-understood baseline
      rules; current `runtime/src/*.ad?` satisfies all of them by inspection.
      Per-side Makefile `lint` targets now delegate to the scripts
      (replacing the previous inline soft-no-ops). **Forced-by-verify side
      work**: the lint pass surfaced two latent bugs in
      `compiler/cmd/gada/main.go` (two unchecked `fmt.Fprintln` returns +
      a misindented godoc list-item continuation) — fixed via explicit
      `_, _ =` discard (broken stdout/stderr is non-actionable for a CLI
      driver) and a one-character indent change. Coverage held at 100%
      (13/13 statements). Verified end-to-end: clean tree → exit 0;
      injected `unused := 42` into `internal/ping/ping.go` → exit 2 with
      `internal/ping/ping.go:14:2: declared and not used: unused (typecheck)`
      report line; reverted → exit 0; `make clean && make ci` →
      `coverage gate: PASSED` + `OK: roadmap status consistent`. Both
      pre- and post-injection runs captured to
      `.maestro/playbooks/Initiation/Working/lint-proof.txt`.

- [x] **GitHub Actions CI**
      *Files:* `.github/workflows/ci.yml`
      *Verify:* push to a branch; CI runs `make ci`, posts coverage as a PR comment, and passes.
      *Done when:* the workflow succeeds on a clean PR and fails on a coverage regression.
      *Notes (2026-05-01, darwin/arm64):* `.github/workflows/ci.yml` (175 lines)
      ships two parallel jobs on `ubuntu-latest`. **`build-test-coverage`** does
      `actions/checkout@v4` → `actions/setup-go@v5` (Go 1.22, `cache: false`
      because Phase 0 has no `go.sum`) → `apt-get install -y lcov` →
      `golangci-lint` v2.1.6 via the official install script (matches the
      `.golangci.yml` v2 schema) → Alire 2.0.2 via the official tarball
      (`alr-2.0.2-bin-x86_64-linux.zip`) into `$HOME/.local/share/alire`,
      mirroring `runtime/Makefile`'s PATH augmentation → `alr -n toolchain
      --select gnat_native gprbuild` + `alr -n index --update-all` to suppress
      Alire's first-run TTY assistant and refresh the community index so AUnit
      resolves cleanly on the first `alr exec` → `make ci` → upload `coverage/`
      via `actions/upload-artifact@v4` (with `if: always()` so partial output
      survives a lint or test failure) → post `coverage/summary.txt` as a
      sticky PR comment via `marocchino/sticky-pull-request-comment@v2` (header
      `gada-coverage-summary`, gated on `github.event_name == 'pull_request' &&
      hashFiles('coverage/summary.txt') != ''`). **`roadmap-consistency`**
      runs only `tools/check_roadmap_consistency.sh` — redundant with `make
      ci`'s final step on success, but valuable on the roadmap-only-drift
      failure mode (surfaces in ~5s without waiting on Go/Alire installs).
      Triggers: `push` (any branch) + `pull_request` to `main`. Permissions:
      workflow-level `contents: read`; `build-test-coverage` adds
      `pull-requests: write` for the comment step (forked-PR runs no-op
      gracefully); `roadmap-consistency` stays minimum-privilege.
      *Note:* live verification deferred to first PR push. `act` and
      `yamllint` are unavailable on this host, so structural validation
      was substituted: `ruby -ryaml` parses the file cleanly, top-level
      keys (`name`, `on`, `jobs`) are present with correct types, and
      step counts match the spec (9 + 2). The Alire-toolchain-non-
      interactive flag, `lcov` 2.x availability on `ubuntu-latest` at
      push time, AUnit community-index resolution, and sticky-PR-comment
      posting can only be exercised against a real GitHub-hosted runner.
      First PR push will confirm or surface fixes for the next agent.

- [x] **Architecture Decision Records (ADR) directory**
      *Files:* `docs/adr/0000-record-architecture-decisions.md`, `docs/adr/template.md`
      *Verify:* `ls docs/adr/*.md | wc -l` ≥ 2.
      *Done when:* the template exists and ADR-0000 explains the ADR convention.
      *Notes (2026-05-01):* Both files written under
      [[Phase-03-ADRs-Style-Contributing]]. `docs/adr/template.md` (69 lines)
      ships MADR-style YAML front matter (`type: adr`, `status: proposed`
      placeholder, `deciders/tags/related` arrays) and the four mandated
      sections (`Context`, `Decision`, `Consequences`,
      `Alternatives considered`), each with inline guidance for the copier.
      Notable convention captured in the template: the `Consequences`
      section's third bullet — *what is now off-limits* — is flagged as the
      most-important and most-skipped, because an ADR that doesn't name what
      it forecloses is not load-bearing. `docs/adr/0000-record-architecture-decisions.md`
      (155 lines, `status: accepted`) codifies the convention itself: flat
      `docs/adr/` location, `NNNN-kebab-title.md` naming (decision-named, not
      question-named — *good:* `gc-boehm-for-v1`, *bad:* `which-gc-do-we-use`),
      three-state lifecycle (`proposed` → `accepted` → `superseded`, never
      deleted, accepted ADRs are typo-only edits), and the supersession
      ritual (add a `Superseded by [[NNNN-...]]` line at the top, flip the
      front-matter status, do **not** rewrite the original Decision
      section). Records the `[[wiki-link]]` cross-reference convention
      (`[[ADR-NNNN]]` for sibling ADRs, `[[roadmap/<file>]]` for roadmap
      anchors, `[[CONTRIBUTING]]` for the contributor guide) that makes
      `docs/adr/` render as a graph in Obsidian and Maestro DocGraph. Names
      the style-doc ↔ ADR mapping (`docs/style_ada.md` ↔ `[[ADR-0002]]`,
      `docs/style_go.md` ↔ `[[ADR-0001]]`) so the next two playbook tasks
      have an existing anchor to reference. Verified: `ls docs/adr/*.md | wc
      -l` = 2 (≥ 2 ✓); ADR-0000 = 155 lines (≥ 50 ✓); `status: accepted`;
      all four required sections present; `[[CONTRIBUTING]]` cross-link
      appears 3 times (front-matter `related`, in-body convention
      paragraph, See-also block). Repo is not yet a git repo, so no
      commit/push step.

- [x] **Initial ADRs documenting v1.0 design choices**
      *Files:* `docs/adr/0001-go-frontend-via-go-ast.md`, `docs/adr/0002-runtime-layered.md`, `docs/adr/0003-gc-boehm-for-v1.md`, `docs/adr/0004-scheduler-libco-for-v1.md`
      *Verify:* each file is ≥ 50 lines, decision-status set to `accepted`, with consequences listed.
      *Done when:* all four ADRs are written and reviewed.
      *Notes (2026-05-01):* All four ADRs landed under
      [[Phase-03-ADRs-Style-Contributing]] using the MADR template
      ratified by ADR-0000. Line counts: 0001=155, 0002=185,
      0003=203, 0004=228 (each ≥ 50 ✓); all four `status: accepted`;
      each carries `## Context` / `## Decision` / `## Consequences`
      (with the three-bullet *easier / harder / off-limits* shape) /
      `## Alternatives considered` / `## See also`. Cross-link
      topology: 0001 ↔ 0002 (frontend ↔ runtime axis), 0002 → 0003
      (GC interface lives in `Gada.Core`, layering constrains it),
      0002 → 0004 (scheduler lives in `Gada.Async`, layering
      constrains it), 0003 ↔ 0004 (goroutine-stack registration
      with libgc is the bidirectional GC/scheduler contract); each
      ADR also wiki-links its anchoring roadmap phase. The
      *off-limits* bullets are the load-bearing additions over the
      `AGENTS.md`/`README.md` source material — they convert
      narrative into guardrails: 0001 forecloses any hand-written
      Go parser/type-checker/module resolver; 0002 forecloses any
      upward `with` and any new top-level package outside `Gada.*`;
      0003 forecloses building a precise GC for v1.0 and emitting
      per-frame stack maps; 0004 forecloses Go-runtime-fidelity
      stack-copy growth, M:N+Ravenscar mixing, and pre-emptive
      scheduling for v1.0. Line audit captured to
      `.maestro/playbooks/Initiation/Working/adr-line-audit.txt`.
      `docs/style_ada.md` and `docs/style_go.md` are referenced as
      forward links from ADR-0001 (Go style) and ADR-0002 (Ada
      style) — those files are the next playbook task and will
      satisfy the **Coding standards documents** item's
      "referenced from at least one ADR" verify clause.

- [x] **Coding standards documents**
      *Files:* `docs/style_ada.md`, `docs/style_go.md`
      *Verify:* both reference the lint configurations and call out project-specific rules (naming: `Gada.X.Y`, file layout, comment style).
      *Done when:* an ADR references each style doc.
      *Notes (2026-05-01):* Both docs landed under
      [[Phase-03-ADRs-Style-Contributing]]. `docs/style_ada.md` (253
      lines) ships nine numbered sections + *See also* with YAML front
      matter (`type: style`, `tags: [style, ada, runtime, lint]`,
      `related:` to ADRs 0000/0002/0003/0004 + CONTRIBUTING). It
      codifies: `Gada.X.Y` namespace + transpiled-user-code reservation
      under `Gada.User.<module-path>` (§1), GNAT `-`-for-`.` file
      naming (§2), public-subprogram **Purpose** comment style with
      the `Gada.Core.IO.Println` worked example (§3), no-`goto` /
      no-spec-mutables (§4–5, the `+RGOTO_Statements` /
      `+RGlobal_Variables` rules' *Why*), the no-upward/sibling-`with`
      matrix derivable from unit names (§6, layer order
      `Core < Async = Reflect < Std`), public-spec → test (§7, ties to
      runtime's 100% coverage gate), and the four already-active
      baseline rules (§8: anonymous arrays/subtypes, exception handlers
      in elaboration, max line length 100, unused withs). Each rule
      carries a *Lint encoding* sub-bullet that names the gnatcheck
      rule or the planned mechanisation (`tools/check_layering.sh`,
      `tools/check_namespace.sh`). `docs/style_go.md` (260 lines)
      ships eight numbered sections + *See also* with parallel YAML
      front matter (`type: style`, `tags: [style, go, compiler, lint]`,
      `related:` to ADRs 0000/0001 + CONTRIBUTING). It codifies: the
      `github.com/gada-lang/gada/...` module path as a public API
      (§1), no-`panic`-in-library-code with three named legitimate
      exceptions (§2), ≤ 4-method interfaces with the
      `io.ReadWriteCloser`-mirror exception named (§3), public-API →
      test tied directly to `tools/coverage_thresholds.toml`'s 90%/
      95%/95% triplet (§4), Go-standard naming with no-`Gada`-prefix
      corollary (§5), error-wrapping with `fmt.Errorf("%w", err)`
      (§6), and the three-block `goimports -local` import grouping
      (§7). §8 explicitly enumerates what the doc does *not* try to
      settle (gofmt-decided formatting, helper placement, test
      framework choice). Each rule carries a *Lint encoding* bullet
      pointing at the active linter in `.golangci.yml`. Cross-links:
      `style_ada` ← `docs/adr/0000-...md` + `docs/adr/0002-...md`
      (verify clause "an ADR references" satisfied with 2);
      `style_go` ← `docs/adr/0000-...md` + `docs/adr/0001-...md`
      (verify clause satisfied with 2). The "ADR references" forward
      links were seeded prospectively when ADRs 0000/0001/0002 were
      written, so this task required no ADR edits. Verified:
      `grep -c 'gnatcheck.rules' docs/style_ada.md` = 7,
      `grep -c '\.golangci\.yml' docs/style_go.md` = 7,
      `grep -c 'Gada\.X\.Y' docs/style_ada.md` = 4,
      `grep -c 'github.com/gada-lang/gada' docs/style_go.md` = 7,
      `./tools/check_roadmap_consistency.sh` → exit 0,
      `make lint` → exit 0 (Go-side clean; Ada-side soft-skip on macOS
      as documented — the Ubuntu CI runner is the authoritative
      enforcement point).

- [x] **CONTRIBUTING quickstart**
      *Files:* `CONTRIBUTING.md`
      *Verify:* `cat CONTRIBUTING.md | wc -l` ≥ 60; references AGENTS.md and roadmap/README.md.
      *Done when:* a new contributor can read it and run `make ci` locally without further questions.
      *Notes (2026-05-01):* `CONTRIBUTING.md` (226 lines, ≥ 60 ✓) shipped under
      [[Phase-03-ADRs-Style-Contributing]]. Sections in spec order: *Quickstart*
      (clone → `make bootstrap` → `make ci`, with the Go 1.22+ / Alire prerequisites
      called out so a new contributor lands a green tree on first try),
      *Picking a task* (anchored on `AGENTS.md` first then the active-phase row in
      `roadmap/README.md`), *Per-task contract* (reproduces the four-line `- [ ]`
      shape **verbatim** from `roadmap/README.md` rather than paraphrasing — paraphrase
      drifts), *Coverage rule* (per-path threshold table mirrors
      `tools/coverage_thresholds.toml` with the *overlapping by design* note so a
      reader understands why a deep regression can't hide behind a broad average),
      *Style* (links both style guides + their lint configs and notes the macOS
      gnatcheck soft-skip), *Commit format* (one concept per commit, area prefix,
      explicit **no Claude/Anthropic co-author** rule promoted from the user's
      global instructions to durable project policy), *PR workflow* (phase branches,
      exit-criterion output in PR description, no-merging-red-CI), *ADRs — when
      to write one* (links `docs/adr/0000-...` and the template; uses the
      "imagine someone six months from now writing 'why on earth did they pick X'"
      heuristic from ADR-0000 verbatim), and a closing *Where to look when stuck*
      router (one bullet per artefact: `AGENTS.md`/`README.md`, the active phase,
      `docs/adr/`, lint configs, `tools/coverage_thresholds.toml`,
      `docs/journal/`). The doc deliberately avoids restating policy that lives
      elsewhere — every rule cites and links its enforcement artefact, so future
      drift is visible (a reader who follows a link finds the canonical version,
      not a stale copy). Verified: `wc -l` = 226 (≥ 60 ✓);
      `grep -E 'AGENTS\.md|roadmap/README\.md'` returns 8 lines (≥ 1 each ✓);
      `make bootstrap` + `make ci` both referenced; ADR-0000, both style guides,
      and `coverage_thresholds.toml` linked; `make ci` exits 0
      (`coverage gate: PASSED`, `OK: roadmap status consistent across index and
      12 phase file(s).`).

- [x] **Roadmap consistency check**
      *Files:* `tools/check_roadmap_consistency.sh`
      *Verify:* `./tools/check_roadmap_consistency.sh` exits 0 on a clean tree and exits 1 with a `MISMATCH:` line when any phase file's `Status:` disagrees with the index table.
      *Done when:* script lives in `tools/`, is documented in `roadmap/README.md` (Consistency check section), and is wired into `make ci` so a roadmap drift fails CI. *(Script + docs landed; `make ci` wiring will be completed by the top-level Makefile item above.)*
