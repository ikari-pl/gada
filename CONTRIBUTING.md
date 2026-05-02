# Contributing to GADA

Welcome. This document is the **operational** entry point for new
contributors — human or agent. It tells you how to set up, how to
pick a task, and the rules every change must clear before it lands.

The **conceptual** entry point — what GADA is, what it is not, and
why we made the load-bearing design choices — lives in
[`AGENTS.md`](AGENTS.md) (also reachable as `CLAUDE.md`). Read that
first if you have not already; this document assumes you have.

## Quickstart

```sh
# Clone (replace with your fork URL when you have one)
git clone https://github.com/gada-lang/gada.git
cd gada

# One-time setup: fetch Go module deps + build the Ada runtime crate.
# Requires Go 1.22+, Alire (https://alire.ada.dev), pkg-config, and
# the Boehm-Demers-Weiser GC system library (package `bdw-gc` /
# `libgc-dev` / `gc-devel` / `boehm-gc` / `gc-dev` depending on your
# package manager). The runtime resolves libgc via `pkg-config bdw-gc`
# per docs/adr/0005-libgc-binding-via-pkgconfig.md; `make bootstrap`
# refuses to proceed if `bdw-gc.pc` is not discoverable and points at
# the install command for your platform.
make bootstrap

# The single gate every PR must pass — runs lint, both test suites,
# coverage with the per-path thresholds, and the roadmap consistency
# check. Exits 0 on success.
make ci
```

If `make ci` exits 0 from a clean checkout, your environment is
correctly set up and you are ready to pick a task. If it fails, the
first failure is the actionable line — fix it (or open an issue if
it looks environmental, e.g., missing `lcov`) before continuing.

The `Makefile` is the source of truth for every CI gate. Per-side
detail (Go-toolchain discovery, Ada coverage instrumentation, lint
plumbing) lives in [`compiler/Makefile`](compiler/Makefile) and
[`runtime/Makefile`](runtime/Makefile); the top-level `Makefile`
only orchestrates.

## Picking a task

1. Open [`AGENTS.md`](AGENTS.md) and confirm you understand the five
   *Pure goals* and the five *Design principles*. Every change must
   be traceable to one of those.
2. Open [`roadmap/README.md`](roadmap/README.md) and find the
   *active phase* — the row whose `Status` is `IN_PROGRESS` in the
   phase table. Click into its phase file (e.g.,
   [`roadmap/00-foundation.md`](roadmap/00-foundation.md)).
3. Pick the **lowest-numbered open `- [ ]` item** whose own
   prerequisites (if any) are checked off. Items are generally
   ordered to be tractable in sequence; do not skip without reason.
4. If no task in the active phase is open and you believe the phase
   is finished, follow the phase-completion ritual (see *PR
   workflow* below) — do not silently start the next phase.

If you encounter a roadmap item that does **not** follow the
per-task contract shape below, your *first* job is to fix it (in a
roadmap-only commit) before you start the underlying work. The
mechanical shape is what lets the next agent pick up safely.

## Per-task contract

Every roadmap item follows this exact shape, defined in
[`roadmap/README.md`](roadmap/README.md):

```
- [ ] **<title>**
      *Files:* <files / globs>
      *Verify:* `<one-shell-command>`
      *Done when:* <observable, not "I think">
```

Your job for one task is:

1. Implement what the title describes, touching only the files in
   *Files* unless you discover the list is wrong (in which case fix
   the list as a small roadmap-only commit first).
2. Run *Verify*. It must exit 0.
3. Confirm the *Done when* clause is observably satisfied — usually
   by an assertion in a test, a log line in CI output, or the
   verify command's own stdout.
4. Run `make ci` from the repo root. It must exit 0.
5. Tick the box (`- [ ]` → `- [x]`) and add a short *Notes (YYYY-MM-DD):*
   block underneath capturing what shipped and any non-obvious
   findings — the next agent reads these to avoid re-deriving them.
6. Commit (see *Commit format* below).

If the verify command fails after implementation, **read the
failure and find the real cause**. Do not "make it pass" by
weakening the test or the gate. If the failure surfaces a
roadmap-level wrong assumption (e.g., "this approach won't work on
macOS"), stop, document the finding as a sub-item in the phase
file, and request human review before proceeding.

## Coverage rule

Coverage is enforced mechanically by `tools/coverage_gate.sh` from
the thresholds in
[`tools/coverage_thresholds.toml`](tools/coverage_thresholds.toml):

| Path                            | Minimum line coverage |
|---------------------------------|-----------------------|
| `runtime/`                      | 100% (no exceptions)  |
| `compiler/internal/emit/`       | ≥ 95%                 |
| `compiler/internal/translate/`  | ≥ 95%                 |
| `compiler/`                     | ≥ 90%                 |

Matching is **overlapping by design**: a file under
`compiler/internal/emit/` counts toward both the `emit/` threshold
*and* the parent `compiler/` threshold. This catches deep-package
regressions that broad averages would mask.

A change that drops coverage below threshold blocks merge. The fix
is **more tests**, not a threshold edit. Threshold edits require an
ADR (see below) — they are load-bearing changes, not paperwork.

The runtime's 100% rule is anchored in `AGENTS.md` Design principle
#1 ("Every behavior is unit-tested before it ships"). Every fixed
bug ships with a regression test in the same commit; no exceptions.

## Style

The two style guides are the human-readable companion to the
machine-checked lint configs:

- [`docs/style_ada.md`](docs/style_ada.md) — the canonical Ada
  style reference. Codifies the `Gada.X.Y` namespace, the `-`-for-`.`
  file-naming rule, the `--  Purpose` comment style for public
  subprograms, and the no-upward-/sibling-`with` layering rule
  derived from [[ADR-0002]]. Lint encoding lives in
  [`tools/gnatcheck.rules`](tools/gnatcheck.rules).
- [`docs/style_go.md`](docs/style_go.md) — the canonical Go style
  reference. Codifies the `github.com/gada-lang/gada/...` module
  path, the no-`panic`-in-library-code rule, the ≤ 4-method
  interface limit, and the public-API → test rule tied to the
  coverage thresholds above. Lint encoding lives in
  [`.golangci.yml`](.golangci.yml).

`make lint` runs both linters. On macOS the Ada side soft-skips
because `gnatcheck` ships only with GNAT Pro; the CI Ubuntu runner
is the authoritative enforcement point. The Go side runs locally on
every supported platform.

## Commit format

- **One concept per commit.** A commit message body that has to use
  "and" to describe what changed is usually two commits.
- **The body explains *why*, not *what*.** The diff already says
  what changed; the commit message is for the rationale a future
  reader needs. Reference the roadmap file and item by name
  (e.g., `roadmap/00-foundation.md item: CONTRIBUTING quickstart`).
- **First line is a short summary, prefixed by area** —
  `compiler:`, `runtime:`, `roadmap:`, `docs:`, `tools:`, `ci:`,
  etc. Keep the summary under 72 characters.
- **Every commit must compile and pass `make ci`.** No "I'll add
  tests in the next commit" — that breaks `git bisect` and the
  100%-tested rule.
- **No Claude / Anthropic co-author lines.** Do not add
  `Co-Authored-By: Claude` (or any AI/tool attribution) to commit
  trailers, and do not add "Generated with Claude Code" or
  equivalents to PR descriptions. The contributor named in the
  `Author:` field is responsible for the change.
- **No `--no-verify` to skip hooks.** If a hook fails, fix the
  underlying issue.

## PR workflow

1. **Branch per phase.** Each roadmap phase lives on
   `phase/NN-description` (e.g., `phase/00-foundation`,
   `phase/03-concurrency`). Each completed item pushes a commit to
   that branch.
2. **`main` is always green.** CI gates: build, both test suites,
   coverage threshold, lint, and roadmap consistency. A PR that
   leaves `main` red is reverted.
3. **Phase completion = a PR to `main`** with the phase's
   exit-criterion output pasted into the PR description. The
   exit-criterion command is the `Exit criterion:` field at the top
   of the phase file. The PR is the only place that command's
   output is recorded; reviewers verify by re-running it.
4. **Flip phase status as its own commit.** When a phase finishes,
   update the phase file's `Status:` from `IN_PROGRESS` to `DONE`,
   flip the next phase from `NOT_STARTED` to `IN_PROGRESS`, and
   update the table in [`roadmap/README.md`](roadmap/README.md) to
   match. Run `./tools/check_roadmap_consistency.sh` before
   committing — CI runs it on every PR and there is no override.
5. **Never merge red CI.** "Pre-existing failure" is not an excuse;
   fix it first. If a check is genuinely irrelevant, that decision
   belongs to a maintainer, not to the PR author.

## ADRs — when to write one

Load-bearing technical decisions are recorded as Architecture
Decision Records under [`docs/adr/`](docs/adr/). The convention
itself is documented in
[`docs/adr/0000-record-architecture-decisions.md`](docs/adr/0000-record-architecture-decisions.md);
read it once and refer back to it when you propose a new ADR.

The shorthand is: **if you can imagine someone six months from now
writing "why on earth did they pick X over Y" in a PR comment,
write the ADR before they have to ask.** Use
[`docs/adr/template.md`](docs/adr/template.md) as your starting
point. Keep status `proposed` while the discussion is open, flip to
`accepted` when it lands, and never delete — superseded ADRs are
kept and linked to their replacements.

Routine implementation choices (which loop construct, which helper
name) do **not** warrant an ADR — those go in code review.

## Where to look when stuck

- *What is GADA, conceptually?* → [`AGENTS.md`](AGENTS.md) and
  [`README.md`](README.md).
- *What's next on the roadmap?* →
  [`roadmap/README.md`](roadmap/README.md) and the phase file with
  `Status: IN_PROGRESS`.
- *Why was X decided that way?* → grep `docs/adr/` for the topic.
- *How is this rule enforced?* → check the lint configs
  ([`tools/gnatcheck.rules`](tools/gnatcheck.rules),
  [`.golangci.yml`](.golangci.yml)) or the coverage thresholds
  ([`tools/coverage_thresholds.toml`](tools/coverage_thresholds.toml)).
- *What have we learned recently?* → `docs/journal/` carries the
  narrative entries.
- *What architectural rough edges are we deliberately living with?* →
  [`docs/imperfections.md`](docs/imperfections.md) — running list of
  accepted trade-offs, mitigations, and enabling-work-for-future-phases
  with the resolution criterion for each.

If after all of that you are still stuck, open a draft PR with what
you have and a short note describing what you tried. A blocked
contributor is a project bug; tell us so we can fix it.
