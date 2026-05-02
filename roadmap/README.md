# GADA Roadmap

This directory holds the phase-by-phase work plan. Each phase lives in
its own file. This index is the navigation entry point and the
cross-cutting policy that applies to every phase.

## How to read these files (agents)

Each phase file has a `Status` field
(`NOT_STARTED`, `IN_PROGRESS`, `DONE`) and an `Exit criterion`
(a single verification command that proves the phase is complete).
Inside each phase, items are `- [ ]` (open) or `- [x]` (done).
Each item carries: a one-line description, the files it touches,
a verify command (exit 0 = success), and a "done when" criterion.

An agent picks the lowest-numbered open item in the active phase
whose own prerequisites are met, implements it until the verify
command passes, runs `make test` and `make coverage-gate` (both
green), then marks the item `[x]` and commits.

## Per-task contract

Every item in every phase file follows this exact shape:

```
- [ ] **<title>**
      *Files:* <files / globs>
      *Verify:* `<one-shell-command>`
      *Done when:* <observable, not "I think">
```

If you encounter an item that does not follow this shape, your *first*
job is to fix it.

## Phases

| # | Phase | Status | File |
|---|---|---|---|
| 0 | Foundation | DONE | [00-foundation.md](00-foundation.md) |
| 1 | Minimal transpiler (hello, GADA) | DONE | [01-minimal-transpiler.md](01-minimal-transpiler.md) |
| 2 | Core runtime: memory & errors | DONE | [02-core-runtime.md](02-core-runtime.md) |
| 3 | Concurrency runtime: goroutines, channels, select | IN_PROGRESS | [03-concurrency.md](03-concurrency.md) |
| 4 | Interfaces & reflection | NOT_STARTED | [04-interfaces-reflection.md](04-interfaces-reflection.md) |
| 5 | Stdlib wave 1: pure-Go foundations | NOT_STARTED | [05-stdlib-wave1.md](05-stdlib-wave1.md) |
| 6 | Stdlib wave 2: system wrappers | NOT_STARTED | [06-stdlib-wave2.md](06-stdlib-wave2.md) |
| 7 | Stdlib wave 3: network | NOT_STARTED | [07-stdlib-wave3-network.md](07-stdlib-wave3-network.md) |
| 8 | Stdlib wave 4: crypto, hash, encoding | NOT_STARTED | [08-stdlib-wave4-crypto.md](08-stdlib-wave4-crypto.md) |
| 9 | Verification track: Go → SPARK | NOT_STARTED | [09-verification-spark.md](09-verification-spark.md) |
| 10 | Mixed Ada/Go codebases | NOT_STARTED | [10-mixed-codebases.md](10-mixed-codebases.md) |
| 11 | Real-world validation & 1.0 | NOT_STARTED | [11-validation-1.0.md](11-validation-1.0.md) |

[Future / post-1.0](future.md) — items not in the 1.0 roadmap.

## Operating notes for agents

- **The active phase** is the one with `Status: IN_PROGRESS`. Only one
  phase is `IN_PROGRESS` at a time. If two are claimed in-progress in
  any phase files, fix the inconsistency first.
- **Item ordering within a phase** is generally a useful execution
  order but not strictly enforced. Items with implicit dependencies
  state them in their "Done when" line; otherwise, lowest-numbered
  open item first.
- **If a verify command is wrong** (no longer reflects the right test,
  or asks for something nonsensical), the item's first work is to
  *fix the verify command* in a roadmap-only commit. Then proceed.
- **Coverage drops are not negotiable.** A PR that drops coverage
  below threshold blocks merge. The fix is more tests, not a
  threshold change.
- **Phase exit criteria are mandatory.** A phase is not `DONE` until
  the exit-criterion command passes from a clean build.
- **Update this index when phase status changes.** When you flip a
  phase from `NOT_STARTED` to `IN_PROGRESS`, update both the phase
  file's `Status:` line *and* the table above. Same for `DONE`. The
  table is the at-a-glance dashboard; it must not drift.
- **Run the consistency check before committing roadmap changes.**
  See *Consistency check* below — it is mechanical and takes < 1
  second. CI runs it on every PR; if it fails, the PR is blocked.

## Consistency check

The roadmap has two sources of truth for phase status: the table at
the top of this file and the `Status:` line in each phase file. They
must agree. The script `tools/check_roadmap_consistency.sh` enforces
this:

```sh
$ ./tools/check_roadmap_consistency.sh
OK: roadmap status consistent across index and 12 phase file(s).
```

On mismatch it prints which phase disagrees, what each side says,
and exits non-zero:

```
MISMATCH: phase 5 (05-stdlib-wave1.md)
    index says:      NOT_STARTED
    phase file says: IN_PROGRESS

FAIL: 1 roadmap status mismatch(es).
```

Run it locally after any roadmap edit. CI runs it as part of `make ci`
and blocks merge on failure. There is no override.

## Working sub-tasks

If an item is too large to fit one commit, decompose it into sub-items
*in the phase file itself*, each with its own verification command.
Update the file, commit the update, then begin work on the sub-items.
Never decompose silently — the file should always reflect the current
decomposition so the next agent can pick up where you left off.

## Failures

If a verification command fails after implementation:

1. Do not "make it pass" by gaming the test. Read the failure, find
   the real cause, fix it.
2. If the failure surfaces a roadmap-level wrong assumption (e.g.,
   "this approach won't work on macOS"), stop, document the finding
   in the phase file as a sub-item, and request human review before
   proceeding.

## Branch & PR workflow

- Each phase lives on a branch: `phase/NN-description` (e.g.,
  `phase/03-concurrency`).
- Each completed item pushes a commit to that branch.
- Phase completion = PR to `main` with the phase's exit-criteria
  output pasted in the PR description.
- `main` is always green. CI gates: build, test, coverage threshold,
  lint.
