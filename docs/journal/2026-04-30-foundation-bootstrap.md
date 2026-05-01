---
type: note
title: Foundation bootstrap (Phase 0 items 1–10)
created: 2026-04-30
tags: [bootstrap, foundation, journal, ci, coverage, lint]
related:
  - "[[roadmap/00-foundation]]"
  - "[[roadmap/01-minimal-transpiler]]"
  - "[[2026-04-30-phase00-done]]"
---

# Foundation bootstrap (Phase 0 items 1–10)

> **Note on numbering:** the body below uses the playbook-side numbering
> ("Phase 01" / "Phase 02") that this work was tagged with at the time;
> in roadmap-side numbering, **all of it is Phase 0** (items 1–4 in the
> first half of this entry, items 5–10 in the embedded "Phase 02" section).
> The retrospective at [[2026-04-30-phase00-done]] uses roadmap numbering
> end-to-end and is the canonical record. This entry is preserved as the
> first-run snapshot.

First-run summary of the GADA repo going from "design docs only" to two
buildable, testable skeletons: the Go transpiler frontend and the Ada
runtime backend. Tracker of record: [[roadmap/00-foundation]]. Full
captured run output: `.maestro/playbooks/Initiation/Working/phase-01-verification.log`.

## Roadmap items ticked

| # | Item ([[roadmap/00-foundation]]) | Verify command | Exit |
|---|----------------------------------|----------------|------|
| 1 | Initialize Go module for the compiler | `cd compiler && go build -o ./bin/gada ./cmd/gada && ./bin/gada --version && go vet ./...` | 0 |
| 2 | Initialize Alire crate for the runtime | `cd runtime && alr build` | 0 |
| 3 | Wire up AUnit for Ada unit testing | `cd runtime && tests/run_tests.sh` | 0 |
| 4 | Wire up Go test toolchain | `cd compiler && go test -race ./...` | 0 |
| 5 | Roadmap consistency check | `./tools/check_roadmap_consistency.sh` | 0 |

All five verifies were re-run end-to-end in a single shell session for
this phase; see the verification log for byte-exact stdout.

## Toolchain baseline (darwin/arm64, Darwin 25.5.0)

| Tool | Status | Version |
|------|--------|---------|
| `go` | AVAILABLE | 1.26.2 |
| `alr` | AVAILABLE* | 2.1.0 (via `~/src/gnatstudio/.tools/bin`) |
| `gprbuild` | AVAILABLE* | 25.0.0 (Alire-managed) |
| `gnat` / `gnatls` | AVAILABLE* | 15.0.1 prerelease (Alire `gnat_native_15.1.2`) |
| `gcov` (GNAT-paired) | AVAILABLE* | GCC 15.0.1 prerelease |
| `lcov` | MISSING | `brew install lcov` |
| `golangci-lint` | MISSING | `brew install golangci-lint` |

`*` = present on disk but not on `$PATH` by default; activate via the
`export PATH=…` block in `.maestro/playbooks/Initiation/Working/toolchain-baseline.txt`.

## Notable findings worth carrying forward

- **Alire manifest validator is ASCII-only** for `description` and caps
  it at 72 chars; em-dashes and other UTF-8 trip a misleading "invalid
  UTF-8" error. Empty `[[depends-on]]` arrays are also rejected — drop
  the section instead of leaving it empty.
- **`Gada.Core` needs `pragma Elaborate_Body`** for its empty-body spec
  to be legal under Ada's no-bodies-without-elaboration-need rule.
- **AUnit's `Test_Cases.Registration` is a nested package**, not a
  child library unit — `use` it inside `Register_Tests`; do not `with`
  it.
- **Stdout capture must use `Ada.Streams.Stream_IO`**, not
  `Ada.Text_IO.Get` — the latter loses the trailing LF when the file
  ends with `LF + file_terminator`, silently breaking byte-exact
  assertions.
- **macOS Sequoia (Darwin 25+) dyld aborts on duplicate `LC_RPATH`**
  load commands, which GNAT 15 + gprbuild 25 emit. `runtime/tests/run_tests.sh`
  post-links with `install_name_tool -delete_rpath` to strip the
  duplicate; on Linux and older macOS the strip is a no-op.

## Deferred to Phase 02 (and why)

- **Coverage tooling (Ada + Go)** — `lcov` not installed locally yet;
  Go side trivially gated on the same Make target landing.
- **Top-level Makefile + coverage gate** — depends on both coverage
  scripts existing first.
- **Linting (`golangci-lint`, `gnatcheck`)** — `golangci-lint` not
  installed locally; install before taking the item.
- **GitHub Actions CI** — depends on the top-level Makefile so the
  workflow can call `make ci`.
- **ADRs, style docs, CONTRIBUTING** — pure-documentation items
  intentionally batched into [[Phase-03-ADRs-Style-Contributing]] for
  one coherent review pass.

## Phase 02 — Build/Coverage/CI

Tracker of record: [[Phase-02-Build-Coverage-CI]]. Full `make ci` run
output: `.maestro/playbooks/Initiation/Working/phase-02-make-ci.log`.

This phase wired the **non-negotiable quality gates** the project manifest
calls out: a single `make ci` from the repo root that runs lint, tests,
coverage, the per-path coverage gate, and the roadmap-consistency check —
in that order, first-failure-aborts. The same pipeline now runs on every
push and PR via GitHub Actions.

### Roadmap items ticked

| # | Item ([[roadmap/00-foundation]]) | Verify command | Exit |
|---|----------------------------------|----------------|------|
| 1 | Coverage tooling — Ada (gcov + lcov) | `make -C runtime coverage` | 0 (100% / 3 lines) |
| 2 | Coverage tooling — Go (`go test -cover`) | `make -C compiler coverage` | 0 (100% / 13 statements) |
| 3 | Top-level `Makefile` orchestrating both | `make clean && make ci` | 0 |
| 4 | Coverage gate | `make coverage-gate` (synthetic regression → exit 1, revert → exit 0) | 0 |
| 5 | Linting | `make lint` (clean tree → 0; injected `unused := 42` → exit 2 with `file:line`; revert → 0) | 0 |
| 6 | GitHub Actions CI | structural validation only on this host (see *Note* below) | n/a |

Reconciliation pass (this entry's task): every Phase 02 verify command
re-run from a clean shell against the current tree — all green, no
roadmap items required unticking.

### Toolchain installs since Phase 01 baseline

| Tool | Version | Install path |
|------|---------|--------------|
| `lcov` | 2.4_1 | `brew install lcov` |
| `golangci-lint` | 2.11.4 | `brew install golangci-lint` |

Both were `MISSING` in the Phase 01 baseline table; both are now
prerequisites for `make ci` on macOS dev machines and are documented
as `apt-get install` / official-installer steps in the GitHub Actions
workflow for the Ubuntu runner.

### Architectural decisions worth carrying forward

- **`Build_Mode` scenario variable, not `-cargs/-largs`, for Ada
  coverage instrumentation.** The naive `gprbuild -cargs -fprofile-arcs
  -ftest-coverage` design poisoned Alire's shared AUnit build cache —
  the cache hash didn't depend on command-line `-cargs`, so subsequent
  non-coverage builds reused gcov-instrumented `libaunit.a` and failed
  at link with `Undefined symbols: ___gcov_.aunit__reporter__set_file`.
  Recovery required `rm -rf` on the cached AUnit build dir. The
  correct design declares `Build_Mode` (`"normal"` / `"coverage"`) in
  *only* the GADA-owned project files, plus `--subdirs=cov` so the two
  flavours land in separate object/lib trees and AUnit's cache is
  never instrumented.
- **`go tool cover -func` must run from inside `compiler/`.** It
  resolves package import paths against the caller's module, so
  invoking it from the repo root fails with `go.mod file not found`.
  Top-level `Makefile`'s `coverage` target `cd $(ROOT)/compiler &&
  go tool cover -func=...` to dodge this.
- **Go cover-profile dedup is non-optional.** `-coverpkg=./...`
  legitimately emits one block per test binary that loaded a package;
  the gate's parser dedups by `(file, sline, scol, eline, ecol)`
  keeping the max observed count — the same rule
  `go tool cover -func` itself applies. Without it, denominators
  inflate and coverage regressions hide behind double-counting.
- **`tools/coverage_thresholds.toml` matches by overlapping prefix.**
  A file under `compiler/internal/emit/` counts toward both that
  threshold and the parent `compiler/` threshold. This catches deep-
  package regressions that broad averages would mask — the synthetic
  ping.go regression dropped `compiler/` to 72.22%, and the gate
  reported the offending parent path correctly.
- **`tools/lint_ada.sh` soft-skips when `gnatcheck` is absent;
  `tools/lint_go.sh` hard-fails when `golangci-lint` is absent.** The
  asymmetry is deliberate: `gnatcheck` ships only with GNAT Pro /
  GNATstudio Pro, not the FSF GNAT distribution Alire installs by
  default. Hard-failing would break every macOS dev box and every
  Linux host without a paid AdaCore subscription. The CI workflow's
  Ubuntu job is the authoritative gnatcheck enforcement point.
- **`.golangci.yml` v2 schema, not v1.** `version: "2"` is mandatory at
  the top of the file; `gofmt`/`goimports` moved out of `linters` into
  a top-level `formatters` block in v2. `linters.default: none` makes
  the active set the *exact* enable list — adding a linter to v2's
  upstream defaults later cannot silently turn it on for this repo.

### Forced-by-verify side work

The coverage-gate task's "revert and confirm exit 0" verify clause
required `compiler/` to actually pass ≥90% on a clean tree. Phase 01
left `cmd/gada/main` and `internal/version/Describe` at 0%/0% pending
Phase 1; the gate's verify clause pulled the work forward. Added
`compiler/cmd/gada/main_test.go` (covers `--version`, no-args,
unknown-flag, and the trivial `main()` wrapper via an `osExit`
indirection swappable from tests) and
`compiler/internal/version/version_test.go` (covers `Describe()`'s
prefix/Version/Phase contract). `compiler/` now stands at 100% (13/13
statements). The lint pass also surfaced two latent bugs in
`cmd/gada/main.go` (unchecked `fmt.Fprintln` returns + a misindented
godoc continuation) — fixed via explicit `_, _ =` discard and a
one-character indent change.

### Deferred to later phases

- **GitHub Actions CI live verification.** The workflow is structurally
  validated (`ruby -ryaml`, top-level keys + step counts) on this
  host because `act` and `yamllint` aren't installed locally. The
  Alire-toolchain non-interactive flag, `lcov` 2.x availability on
  `ubuntu-latest`, AUnit community-index resolution, and
  sticky-PR-comment posting can only be exercised against a real
  GitHub-hosted runner. First PR push will confirm or surface fixes
  for the next agent. Documented as a `*Note:*` sub-bullet under the
  **GitHub Actions CI** roadmap item.
- **`compiler/internal/emit/` and `compiler/internal/translate/`
  thresholds (95% each).** Show as `SKIP` at the gate today because
  those packages don't exist yet — they land in [[Phase-01-Minimal-Transpiler]].
  The gate correctly treats "no files matched the prefix" as a skip
  rather than a failure (enforcing 95% on a 0-statement set is
  undefined). Once Phase 1 lands the first source files under either
  path, the thresholds start enforcing automatically — no script
  change needed.
- **`+RHeaders` rule in `tools/gnatcheck.rules`.** Commented-out
  placeholder pending [[Phase-03-ADRs-Style-Contributing]]'s
  `docs/style_ada.md`. Enabling it now would either flag every existing
  file or trap a future agent into thinking the rule is enforced when
  it has an empty header template.
- **Phase 1 onwards.** Phase 02's `Status:` flips to `DONE` with this
  reconciliation; Phase 1 (minimal transpiler) becomes the next active
  phase.
