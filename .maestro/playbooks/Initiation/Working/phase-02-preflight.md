---
type: note
title: Phase 02 Preflight — Existing Repo State Survey
created: 2026-05-01
tags:
  - phase-02
  - preflight
  - build-system
  - coverage
  - ci
related:
  - '[[Phase-02-Build-Coverage-CI]]'
  - '[[00-foundation]]'
---

# Phase 02 Preflight — Existing Repo State Survey

Performed before writing any new build-system code, per the first task of
`Phase-02-Build-Coverage-CI.md`. The point of the survey is to decide
*extend vs. create* for every artifact this phase will produce.

## Files searched for and result

| Artifact | Path | Present? |
|---|---|---|
| Top-level Makefile | `Makefile` | **no** |
| Compiler Makefile | `compiler/Makefile` | **no** |
| Runtime Makefile | `runtime/Makefile` | **no** |
| Coverage scripts | `tools/coverage_*.sh` | **no** |
| Lint scripts | `tools/lint_*.sh` | **no** |
| Coverage thresholds | `tools/coverage_thresholds.toml` | **no** |
| Coverage gate | `tools/coverage_gate.sh` | **no** |
| golangci config | `.golangci.yml` | **no** |
| gnatcheck rules | `tools/gnatcheck.rules` | **no** |
| GitHub Actions workflow | `.github/workflows/ci.yml` | **no** |
| Roadmap consistency check | `tools/check_roadmap_consistency.sh` | **yes** (already used by `make ci` per the roadmap entry) |

`tools/` contents (whole directory):

```
tools/
└── check_roadmap_consistency.sh
```

`.github/` does not exist.

## Conclusion: no extend-vs-replace decisions

Nothing in this phase needs to extend a pre-existing artifact. Every file
this phase creates is a clean addition. The single exception is `tools/`,
which already holds `check_roadmap_consistency.sh`; the new shell scripts
will sit alongside it.

## Roadmap items this phase must satisfy verbatim

These are the *Verify* contracts each subsequent task in the phase must
make pass. Quoted from `roadmap/00-foundation.md`:

- **Coverage tooling — Ada (gcov + lcov):**
  `make -C runtime coverage` produces `runtime/coverage.lcov` and a non-zero line count.
- **Coverage tooling — Go (`go test -cover`):**
  `make -C compiler coverage` produces `compiler/coverage.out` and a summary.
- **Top-level Makefile:**
  `make test` runs both Ada and Go suites; `make coverage` produces a unified report under `coverage/`.
- **Coverage gate:**
  `make coverage-gate` reads thresholds and exits 1 if any package is below threshold.
- **Linting:**
  `make lint` exits 0 on a clean tree; an intentional violation is reported with `file:line`.
- **GitHub Actions CI:**
  Push to a branch; CI runs `make ci`, posts coverage as a PR comment, passes/fails honestly.

## Toolchain availability on this host (darwin/arm64)

Carried forward from `toolchain-baseline.txt` in this same Working folder.
Relevant for Phase 02:

- `go` 1.26.x — present.
- `golangci-lint` — to confirm at the lint task; absence handled by
  `tools/lint_go.sh` printing an install message and exiting 1 (per playbook).
- Alire-managed `gnat` 15.0.1 + `gprbuild` 25.0.0 — present (used in Phase 01
  for `alr build` and the AUnit harness).
- `gnatcoverage` — almost certainly absent on this host. The Ada coverage
  task explicitly allows the `gcov + lcov` fallback.
- `lcov` — to confirm at the Ada-coverage task; if absent, the playbook
  permits leaving the script in place with a `*Note:*` line on the
  roadmap item explaining the host limitation, deferring live verification
  to CI.

## Note for next agent

The next unchecked task in `Phase-02-Build-Coverage-CI.md` is
**"Add Go coverage tooling and per-package Makefile target"**. It can
proceed without any reconciliation work — there is nothing to extend.
