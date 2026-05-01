# Phase 01: Foundation Bootstrap — First Working Artifacts

This phase brings GADA from "design documents only" to "two visible, testable artifacts": a working `gada` Go binary that prints its version, and an Ada runtime crate with a `Println` package that already prints `hello, GADA` from a unit test. By the end of this phase, both halves of the toolchain (the Go transpiler frontend and the Ada runtime backend) exist as buildable, testable skeletons — exactly the foundation that every later phase depends on. This phase is fully autonomous: it detects available toolchains (`go`, `alr`, `gprbuild`), creates the directory layout described in `AGENTS.md`, and ticks the matching items in `roadmap/00-foundation.md` as it goes. If a toolchain is missing on this machine, the phase still completes the parts that *can* run and clearly reports what was skipped, so the user sees concrete progress immediately.

## Tasks

- [x] Inspect the existing repo and capture a baseline:
  - Read `AGENTS.md`, `roadmap/README.md`, and `roadmap/00-foundation.md` end-to-end so subsequent edits stay consistent with the per-task contract (`Files / Verify / Done when`).
  - Run `./tools/check_roadmap_consistency.sh` once and confirm it exits 0 (it is the only `[x]` item today).
  - Detect available tooling and print a one-line summary for each: `go version`, `alr --version`, `gprbuild --version`, `gnatls --version`, `lcov --version`, `gcov --version`, `golangci-lint --version`. Capture the results into a temp note `.maestro/playbooks/Initiation/Working/toolchain-baseline.txt` (create the `Working/` folder if missing). This determines which subsequent tasks can fully verify versus stub-and-document. We have a full GNAT Studio in ~/src/gnatstudio .

  *Notes (2026-05-01, gada agent):*
  - Read all three orientation files; the per-task contract is *Files / Verify / Done when* and item 2 of `roadmap/00-foundation.md` is the only `[x]` (the Go-module bootstrap, completed by a previous run).
  - `./tools/check_roadmap_consistency.sh` → `OK: roadmap status consistent across index and 12 phase file(s).` (exit 0).
  - `Working/` folder already existed; baseline file was overwritten with revised, accurate contents.
  - Toolchain summary captured at `.maestro/playbooks/Initiation/Working/toolchain-baseline.txt` (86 lines). Key correction vs. the prior pass: searching `~/src/gnatstudio/.tools/bin/` revealed shims into a working Alire-managed GNAT 15.x toolchain, so the entire Ada side is in fact AVAILABLE on this host once `PATH` is set. Specifically:
    - `~/src/gnatstudio/.tools/bin/alr` → Alire 2.1.0
    - `~/src/gnatstudio/.tools/bin/gprbuild` → GPRBUILD 25.0.0 (aarch64-apple-darwin23.6.0)
    - `~/src/gnatstudio/.tools/bin/gnat` → GNAT 15.0.1 20250418 (prerelease)
    - `~/.local/share/alire/toolchains/gnat_native_15.1.2_60748c54/bin/{gnatls,gcov,gnatmake,gnatbind,gnatlink}` — full GNAT 15.0.1 toolchain
    - `gprbuild_25.0.1_c2b4ada4` toolchain dir at the same Alire root.
  - Still missing on this host: `lcov` (HTML coverage report generator) and `golangci-lint`. Both are install-only (`brew install lcov golangci-lint`) and gate later items, not the next few Phase 01 tasks.
  - Implication for the next two tasks: the Ada-runtime bootstrap and the AUnit smoke test can be fully verified locally — the prior baseline's "stub-and-document, defer to CI" plan no longer applies. Activate the toolchain with the `PATH` export documented in the baseline file before running `alr build` / `gprbuild`.

- [x] Bootstrap the Go compiler module with a runnable `gada --version` binary. This corresponds to the **Initialize Go module for the compiler** item in `roadmap/00-foundation.md`:
  - Create `compiler/go.mod` with module path `github.com/gada-lang/gada/compiler` and `go 1.22`.
  - Create `compiler/cmd/gada/main.go` containing a `main` function that parses one flag `--version` and prints `gada 0.0.0-dev (phase 0 bootstrap)` to stdout, exiting 0. No other flags yet — keep it minimal.
  - Create `compiler/internal/version/version.go` exposing `const Version = "0.0.0-dev"` and `func Describe() string` returning the full string above. Wire `main.go` to use it.
  - Build and verify: `cd compiler && go build -o ./bin/gada ./cmd/gada && ./bin/gada --version` must exit 0 and print the expected line. Run `go vet ./...` — must be clean.
  - When green, mark the matching `- [ ]` item in `roadmap/00-foundation.md` as `- [x]`.

  *Notes (2026-05-01, gada agent):*
  - Files created: `compiler/go.mod`, `compiler/cmd/gada/main.go`, `compiler/internal/version/version.go`. No `go.sum` yet (no external deps).
  - `version.Describe()` returns the exact contracted line `gada 0.0.0-dev (phase 0 bootstrap)`.
  - Verification on darwin/arm64 with `go1.26.2`:
    - `go build -o ./bin/gada ./cmd/gada` → exit 0 (binary at `compiler/bin/gada`).
    - `./bin/gada --version` → prints `gada 0.0.0-dev (phase 0 bootstrap)`, exit 0.
    - `go vet ./...` → clean, exit 0.
  - Matching roadmap item in `roadmap/00-foundation.md` ticked `[x]` with verify-command updated to the playbook's `./bin/gada` form (the original used Go's default `./cmd/gada/gada` path).
  - `os.Exit(2)` on missing flag follows POSIX usage-error convention so future scripts fail loudly.

- [x] Bootstrap the Ada runtime crate with a top-level `Gada` package. This corresponds to the **Initialize Alire crate for the runtime** item:
  - If `alr` is available: run `cd runtime && alr init --in-place --lib gada_core` to scaffold; otherwise hand-write the equivalent `runtime/alire.toml` with name `gada_core`, version `0.0.0-dev`, dependencies left empty.
  - Create `runtime/gada_core.gpr` declaring a library project named `Gada_Core` with source dir `src/`, object dir `obj/`, language Ada.
  - Create `runtime/src/gada.ads` containing `package Gada is end Gada;` (top-level umbrella package).
  - Create `runtime/src/gada-core.ads` and `runtime/src/gada-core.adb` for the `Gada.Core` child package — empty body for now, just the declaration.
  - Verify: `cd runtime && (alr build || gprbuild -P gada_core.gpr)` must exit 0. If neither toolchain is available, document this clearly in the task notes and move on — the file structure must still be in place so a CI host with GNAT can build it.
  - Mark the matching roadmap item `[x]` only if the build actually succeeded; otherwise leave `[ ]` and add a sub-bullet explaining the missing tool.

  *Notes (2026-05-01, gada agent):*
  - Hand-wrote the crate skeleton (didn't use `alr init` — wanted explicit umbrella-package layout `gada.ads` + child `gada-core.ads/.adb`, not the default `gada_core.ads` Alire would have generated).
  - Files created: `runtime/alire.toml`, `runtime/gada_core.gpr`, `runtime/src/gada.ads`, `runtime/src/gada-core.ads`, `runtime/src/gada-core.adb`.
  - `gada_core.gpr` is a `library project` (static, `gada_core` library name), source `src/`, object `obj/`, library `lib/`, Ada 2022, `-gnatwa -gnatyy -O0 -g`.
  - `gada.ads` is a `pragma Pure` umbrella; `gada-core.ads` declares the `Gada.Core` child with `pragma Elaborate_Body` so the empty body is legal (without it GNAT errors with *"spec of this package does not allow a body"* — Ada forbids bodies on specs that have no declarations requiring elaboration).
  - Three Alire-manifest gotchas surfaced and were fixed:
    1. `alr` rejected the em-dash in the description as "invalid UTF-8" — the file *was* valid UTF-8, but Alire's manifest validator only accepts ASCII in the `description` field. Replaced `—` with `-`.
    2. `alr` enforces a 72-char cap on `description`. Trimmed to 60 chars.
    3. An empty `[[depends-on]]` array entry is malformed TOML; dropped it entirely (a comment now explains the absence).
  - Verified on darwin/arm64 with `PATH` activated to the Alire-installed GNAT 15.0.1 + GPRBUILD 25.0.0:
    - `gprbuild -P gada_core.gpr` → exit 0; produces `obj/{gada,gada-core}.{ali,o}` and `lib/libgada_core.a`.
    - `alr build` → exit 0, "Build finished successfully in 0.77 seconds".
  - The `clang: warning: overriding deployment version from '16.0' to '26.0'` lines are benign — Alire's GNAT was built against macOS SDK 16.0 but this host has SDK 26.0; warning only, no link failure.
  - Roadmap row in `roadmap/00-foundation.md` ticked `[x]`.

- [x] Add a working `Gada.Core.IO.Println` package and an AUnit smoke test that prints `hello, GADA`. This pulls forward the **GADA.Core.IO — minimal Println** item from Phase 1 of the roadmap, because it is the most motivating early artifact and is needed to wire AUnit anyway:
  - Create `runtime/src/gada-core-io.ads` declaring `procedure Println (Text : String)` in package `Gada.Core.IO`.
  - Create `runtime/src/gada-core-io.adb` implementing it via `Ada.Text_IO.Put_Line`.
  - Create `runtime/tests/aunit_harness.gpr` (an AUnit project file extending `gada_core.gpr` with `aunit` as a dependency).
  - Create `runtime/tests/test_runner.adb` (the AUnit `Main`) that registers one test suite.
  - Create `runtime/tests/io_suite.ads` and `io_suite.adb` with a single test that calls `Gada.Core.IO.Println ("hello, GADA")` and asserts a captured-output string equals `"hello, GADA" & ASCII.LF`. (Use `Ada.Text_IO.Set_Output` to a `String_Stream` for capture, or simpler: redirect via the test runner.)
  - Verify: `cd runtime && (alr exec -- gprbuild -P tests/aunit_harness.gpr && tests/obj/test_runner) || gprbuild -P tests/aunit_harness.gpr && tests/obj/test_runner` must run with at least one passing assertion. If the toolchain is unavailable on this host, leave a `Done when` sub-bullet in the roadmap noting that CI will exercise it.
  - Mark the **Wire up AUnit for Ada unit testing** roadmap item `[x]` if the harness ran green.

  *Notes (2026-05-01, gada agent):*
  - Files created:
    - `runtime/src/gada-core-io.ads` / `gada-core-io.adb` — `Gada.Core.IO.Println (Text : String)` via `Ada.Text_IO.Put_Line`. No layering violations; only `Ada.Text_IO` is withed.
    - `runtime/tests/aunit_harness.gpr` — *standalone* executable project. Withs `../gada_core.gpr` and `aunit`. Deliberately not an extending project (extension inherits source dirs, which would mix runtime sources into the harness object tree).
    - `runtime/tests/test_runner.adb` — main; registers one suite via `AUnit.Run.Test_Runner` generic.
    - `runtime/tests/io_suite.ads` / `io_suite.adb` — single test `Test_Println_Hello`.
    - `runtime/tests/run_tests.sh` — build+run wrapper (see *macOS dyld workaround* below).
  - `runtime/alire.toml`: added `[[depends-on]] aunit = "^26.0.0"`. `alr update` resolves to `aunit 26.0.0`. (Same em-dash UTF-8 trap as before — Alire's manifest validator rejects non-ASCII even though the file is valid UTF-8; comments are ASCII-only.)
  - **AUnit API gotcha:** `AUnit.Test_Cases.Registration` is a *nested* package, not a child library unit, so the body uses `use AUnit.Test_Cases.Registration;` inside `Register_Tests` and does NOT `with` it explicitly. (My first pass tried `with AUnit.Test_Cases.Registration;` and got *"file not found"*.)
  - **Stdout-capture gotcha:** initial implementation read the captured temp file via `Ada.Text_IO.Get` in a loop, but `End_Of_File` returns True when the next bytes are `LF + file_terminator` — so the trailing `LF` written by `Put_Line` was lost and the test failed with `expected [hello, GADA\n] got [hello, GADA]`. Switched the reader to `Ada.Streams.Stream_IO` for byte-exact capture; test went green.
  - **macOS dyld workaround:** GNAT 15 + gprbuild 25 emit two identical `LC_RPATH` load commands pointing at the Alire-managed GNAT `lib/` directory. macOS Sequoia (Darwin 25+) dyld now ABORTs on duplicate `LC_RPATH` (SIGABRT, exit 134) instead of just warning. `runtime/tests/run_tests.sh` post-links with `install_name_tool -delete_rpath` to strip the duplicate before exec. On Linux and older macOS the strip step is a no-op (the duplicate path isn't there).
  - Verification on darwin/arm64 with the toolchain `PATH` activated:
    - `cd runtime && tests/run_tests.sh` → `OK Gada.Core.IO suite : Gada.Core.IO.Println emits 'hello, GADA' + LF`, `Total Tests Run: 1`, `Successful Tests: 1`, `Failed Assertions: 0`, exit 0.
  - Roadmap row in `roadmap/00-foundation.md` ticked `[x]` for **Wire up AUnit for Ada unit testing**, with `Verify` updated to point at the wrapper script (the original verify command works on Linux but aborts in dyld on macOS Sequoia).
  - Remaining minor warning: `test_runner.adb:24:25: warning: use of an anonymous access type allocator [-gnatw_a]`. Idiomatic AUnit style — fixing it requires introducing a named access type purely to suppress a warning. Left as-is; will revisit if `[-gnatw_a]` becomes part of the project's hard-error list.

- [x] Add a single Go test to validate the Go test toolchain. This corresponds to the **Wire up Go test toolchain** roadmap item:
  - Create `compiler/internal/ping/ping.go` with a single exported function `func Ping() string { return "pong" }`.
  - Create `compiler/internal/ping/ping_test.go` with one table-driven test asserting `Ping() == "pong"`.
  - Verify: `cd compiler && go test -race ./...` exits 0.
  - Mark the matching roadmap item `[x]`.

  *Notes (2026-05-01, gada agent):*
  - Files created:
    - `compiler/internal/ping/ping.go` — package `ping` with `func Ping() string { return "pong" }`. Doc comment explains its sole purpose is to give the Phase 0 verify command an exported symbol to call; flagged for likely deletion once Phase 1 emits real internal packages.
    - `compiler/internal/ping/ping_test.go` — table-driven `TestPing` with one case (`"returns pong"` → `"pong"`). Both the outer test and each `t.Run` subtest call `t.Parallel()` so the race detector has parallelism to exercise — a single sequential test would still satisfy the contract, but `go test -race` is most meaningful with concurrent goroutines, and table-driven `t.Parallel()` is the idiomatic way to scale that up later. Loop variable captured into local `tc := tc` (mandatory pre-Go 1.22 to avoid the classic loop-variable-capture race; Go 1.22+ scopes it per-iteration but the project is on `go 1.22` exactly so the explicit shadow stays as a safety belt and a hint to readers).
  - Verification on darwin/arm64 with `go1.26.2`:
    - `cd compiler && go test -race ./...` →
      ```
      ?   github.com/gada-lang/gada/compiler/cmd/gada           [no test files]
      ok  github.com/gada-lang/gada/compiler/internal/ping       1.325s
      ?   github.com/gada-lang/gada/compiler/internal/version    [no test files]
      ```
      exit 0.
    - `go vet ./...` → clean, exit 0.
  - The two `[no test files]` lines on `cmd/gada` and `internal/version` are informational only — `go test` reports them with `?` (not failure) and does not affect the exit code. Adding noop tests there to silence the marker would violate the project's "no scaffolding tests" implicit norm; the markers will go away naturally once Phase 1 wires real tests for both packages (driver flag parsing for `cmd/gada`, `Describe()` formatting for `internal/version`).
  - Roadmap row in `roadmap/00-foundation.md` ticked `[x]` for **Wire up Go test toolchain**.

- [x] Run the roadmap consistency check and ensure phase index reflects the work in flight:
  - Edit `roadmap/00-foundation.md`: change `Status:` from `NOT_STARTED` to `IN_PROGRESS`.
  - Edit `roadmap/README.md` phase table: change the Phase 0 row's `Status` cell from `NOT_STARTED` to `IN_PROGRESS`. Both must match exactly — this is the contract `tools/check_roadmap_consistency.sh` enforces.
  - Run `./tools/check_roadmap_consistency.sh` — must exit 0.
  - Run the verification commands for every item just ticked off, end-to-end, in a single shell session, and write the captured output to `.maestro/playbooks/Initiation/Working/phase-01-verification.log`. Any non-zero exit means rollback the corresponding `[x]` to `[ ]` and add a `*Note:* <reason>` line under it before proceeding.

  *Notes (2026-05-01, gada agent):*
  - Flipped Phase 0 status to `IN_PROGRESS` in both sources of truth: `roadmap/00-foundation.md` (line 5) and the phase table in `roadmap/README.md` (line 39). `./tools/check_roadmap_consistency.sh` → `OK: roadmap status consistent across index and 12 phase file(s).` (exit 0).
  - End-to-end verification log captured at `.maestro/playbooks/Initiation/Working/phase-01-verification.log` (49 lines). PATH was activated up front to the Alire-managed GNAT 15.0.1 + GPRBUILD 25.0.0 (`~/src/gnatstudio/.tools/bin` + Alire toolchain dirs) so the Ada-side commands resolve.
  - Five commands run in a single shell, each with `exit=$?` printed immediately after; intentionally no `set -e` so a failure wouldn't short-circuit downstream commands and hide drift. All five exited 0:
    1. `./tools/check_roadmap_consistency.sh` → `OK: roadmap status consistent...`, exit 0.
    2. `cd compiler && go build -o ./bin/gada ./cmd/gada && ./bin/gada --version && go vet ./...` → prints `gada 0.0.0-dev (phase 0 bootstrap)`, vet clean, exit 0.
    3. `cd compiler && go test -race ./...` → `internal/ping` reports `ok (cached)`; `cmd/gada` and `internal/version` show `[no test files]` (informational); exit 0. The `(cached)` is a legitimate cache hit (race-flag is part of the cache key), not a skipped run.
    4. `cd runtime && alr build` → "Build finished successfully in 0.99 seconds", exit 0. Benign `clang: warning: overriding deployment version from '16.0' to '26.0'` (Alire GNAT was built against macOS SDK 16.0; host runs SDK 26.0).
    5. `cd runtime && tests/run_tests.sh` → `OK Gada.Core.IO suite : Gada.Core.IO.Println emits 'hello, GADA' + LF`, `Total Tests Run: 1, Successful Tests: 1, Failed Assertions: 0`, exit 0.
  - No rollbacks needed; every `[x]` ticked earlier in this phase is genuinely green from a clean shell.

- [x] Capture a phase-completion summary as a structured markdown note for later reference. This is the only documentation artifact this phase produces; it lives outside `roadmap/` so it does not pollute the canonical tracker:
  - Create folder `docs/journal/` if missing.
  - Create `docs/journal/2026-04-30-phase01-bootstrap.md` with YAML front matter:
    ```yaml
    ---
    type: note
    title: Phase 01 — Foundation Bootstrap
    created: 2026-04-30
    tags: [bootstrap, foundation, journal]
    related:
      - "[[Phase-00-Foundation]]"
      - "[[Phase-01-Minimal-Transpiler]]"
    ---
    ```
  - Body: list each roadmap item ticked, the verify command and its captured exit code, the toolchain summary, and any items deferred to Phase 02 with a one-line reason. Use `[[wiki-links]]` for cross-references to roadmap files (e.g., `[[roadmap/00-foundation]]`). Keep it under 80 lines — this is a journal entry, not a report.

  *Notes (2026-05-01, gada agent):*
  - Created `docs/journal/` (the `docs/` tree did not exist yet — this is the first artifact under it) and wrote `docs/journal/2026-04-30-phase01-bootstrap.md`.
  - Filename uses `2026-04-30` (the playbook authoring date, per the contract); the work itself landed on 2026-05-01, recorded in the per-task `*Notes*` blocks above.
  - YAML frontmatter matches the contract exactly: `type: note`, `title: Phase 01 — Foundation Bootstrap`, `created: 2026-04-30`, `tags: [bootstrap, foundation, journal]`, and the two `related` wiki-links (`[[Phase-00-Foundation]]`, `[[Phase-01-Minimal-Transpiler]]`).
  - Body sections (78 lines total, under the 80-line cap):
    1. *Roadmap items ticked* — 5-row table mapping each item to its verify command and captured exit code (all 0). Pointer to `Working/phase-01-verification.log` for byte-exact stdout, so the journal stays summary-grade and the log carries full fidelity.
    2. *Toolchain baseline* — compact 7-row table; documents the `*` = "on disk, not on `$PATH`" convention and references the `export PATH=…` block in `Working/toolchain-baseline.txt`.
    3. *Notable findings worth carrying forward* — 5 gotchas surfaced this phase (Alire ASCII-only `description`, `pragma Elaborate_Body` requirement, AUnit nested registration package, `Stream_IO` for byte-exact capture, macOS Sequoia duplicate-`LC_RPATH` dyld abort).
    4. *Deferred to Phase 02* — 5 unticked roadmap items with a one-line reason each (lcov/golangci-lint missing, top-level Makefile dependency, batched ADRs/style/CONTRIBUTING).
  - Wiki-links chosen for graph navigation: `[[roadmap/00-foundation]]` for the canonical tracker, `[[Phase-00-Foundation]]` and `[[Phase-01-Minimal-Transpiler]]` for sibling-phase context. Targets don't have to exist as files for DocGraph to render the edges as stubs.
  - Verification: `wc -l docs/journal/2026-04-30-phase01-bootstrap.md` → 78 (under cap); frontmatter parses (head -10 confirms); `./tools/check_roadmap_consistency.sh` still exits 0 (no roadmap files were touched, just `docs/` and this playbook).
