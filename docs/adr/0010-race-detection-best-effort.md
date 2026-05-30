---
type: adr
title: "ADR-0010: Race detection is a best-effort cooperative checked-cell, not a TSan-style detector"
status: accepted
created: 2026-05-30
deciders: [ikari]
tags: [concurrency, race-detection, runtime, async, best-effort]
related:
  - "[[0002-runtime-layered]]"
  - "[[0003-gc-boehm-for-v1]]"
  - "[[0004-scheduler-libco-for-v1]]"
  - "[[0009-ravenscar-conditional-spark]]"
---

# ADR-0010: Race detection is a best-effort cooperative checked-cell, not a TSan-style detector

## Context

`roadmap/03-concurrency.md` carries the item "Race detector integration
(best-effort)", whose done-when is explicit about the fork in the road:
*"an intentional data race is detected and reported (or documented as a
known limitation in an ADR)."* The phrase "best-effort" is load-bearing.

Go's own race detector is ThreadSanitizer (TSan): a happens-before
engine backed by per-byte shadow memory and per-goroutine vector
clocks. It instruments every memory access in the program and is sound
within its observed execution (no false positives) at a 5-10x runtime
and 5-10x memory cost. Reproducing TSan for GADA would mean (a)
instrumenting every load/store the transpiler emits, (b) a shadow-memory
allocator that shadows the Boehm GC heap, the Ada secondary stack, and
every goroutine's libco stack, and (c) a vector-clock implementation
threaded through every channel send/receive, mutex, and `WaitGroup` so
the happens-before graph is complete. That is a research effort on the
order of the precise-GC effort `CLAUDE.md` explicitly defers past 1.0
("Writing our own GC... A precise GC may be a research effort later; it
is not a 1.0 deliverable"). The same honesty applies here: a sound,
complete race detector is not a 1.0 deliverable.

The question is therefore not "TSan or nothing" but "what is the
smallest *honest* best-effort artifact that catches a real intentional
race, ships at 100% coverage, and does not pretend to be more than it
is."

## Decision

We ship `Gada.Async.Race` — a **cooperative checked-cell** race monitor,
and we document its envelope here rather than implying TSan parity.

1. **The unit of detection is an explicitly-wrapped cell, not all of
   memory.** `Gada.Async.Race.Checked_Cell` is a generic that wraps one
   value behind a protected `Monitor`. There is no shadow memory and no
   instrumentation of arbitrary loads/stores. Only data the programmer
   (or, later, the transpiler) routes through a `Checked_Cell` is
   watched.

2. **Detection is access-section overlap, not happens-before.** Each
   access brackets with `Begin_Access (Mode, Who)` / `End_Access (Who)`,
   where `Mode in (Read, Write)` and `Who` is a `Scheduler.Goroutine_Id`.
   The monitor records the current holder and its mode. When
   `Begin_Access` arrives from a goroutine that is **not** the current
   holder while a section is still open, and at least one of the two
   modes is `Write`, the monitor latches a `Race_Report`. This is
   exactly Go's data-race definition — "two goroutines access the same
   variable concurrently and at least one access is a write" — narrowed
   to one instrumented cell and to the cooperative Begin/End bracket as
   the proxy for "concurrently".

3. **A detected race is data, not an exception.** `Begin_Access` never
   raises and never blocks; the verdict surfaces via `Race_Detected` /
   `Report` / `Image`. The first race latches (subsequent collisions do
   not overwrite it) so the report names the originating collision.

4. **Re-entrancy from the same goroutine is not a race.** Nested
   `Begin_Access` calls from the current holder bump a depth counter and
   may escalate the holder's mode `Read → Write`; the holder only clears
   on the balancing outermost `End_Access`. This keeps a goroutine that
   legitimately reads-then-writes its own cell from flagging itself.

5. **The roadmap item is satisfied by detection, not by the ADR
   fallback.** The done-when's OR is resolved on the *detect* side: the
   `race_suite` test `Test_Goroutine_Driven_Intentional_Race` spawns two
   real goroutines that hold overlapping `Write` sections on one shared
   cell (held open by a two-party protected-entry rendezvous) and asserts
   the monitor reports the race. This ADR documents the *envelope* of
   that detector, not a decision to ship nothing.

## Consequences

- **What now becomes easier.** Phase 4's transpiler can opt specific
  Go variables known to be shared (e.g. a package-level `var` captured by
  multiple `go` statements, or a struct field a static escape pass flags)
  into a `Checked_Cell` and get a deterministic, cheap, allocation-free
  race signal in tests and in `-race`-style debug builds — without
  paying TSan's whole-program instrumentation tax. The monitor is a
  protected object, so it is also a candidate for the Ravenscar/SPARK
  posture discussion in [[0009-ravenscar-conditional-spark]] later.

- **What now becomes harder.** The cooperative contract puts the burden
  on whoever wraps the cell to bracket *every* access with Begin/End. A
  cell read outside its bracket is invisible to the monitor (false
  negative), and a program that brackets too coarsely — holding a
  section open across an unrelated channel rendezvous — can manufacture a
  false positive. Neither failure mode exists in TSan. Documentation and,
  later, transpiler-generated brackets must carry this weight; hand-
  written brackets are a foot-gun and are documented as such in the spec.

- **What is now off-limits.** A PR that markets `Gada.Async.Race` as a
  general race detector, an `-mode=race` build that claims TSan-equivalent
  guarantees, or a test that asserts "no race detected ⇒ program is
  race-free" is rejected — the detector is sound only for the wrapped
  cells under correct bracketing, and complete for nothing. Replacing
  this with a real happens-before engine is a future research effort and
  must supersede this ADR with its own design (shadow memory, vector
  clocks, instrumentation strategy, and a measured runtime/memory cost
  against the [[0006-runtime-performance-bar]]).

## What it catches and does not catch

| Scenario | Verdict | Why |
|---|---|---|
| Two distinct goroutines, overlapping Write/Write on one wrapped cell | **Detected** | Distinct holder while held + a Write |
| Distinct goroutines, overlapping Read/Write on one wrapped cell | **Detected** | At least one Write |
| Distinct goroutines, overlapping Read/Read | Not flagged | Concurrent reads are not a race (matches Go) |
| Same goroutine, nested Begin/End (re-entrant) | Not flagged | Holder unchanged; re-entrancy, not a race |
| Non-overlapping access (each ends before the next begins) | Not flagged | No concurrent access — correct synchronisation |
| A race on memory **not** wrapped in a `Checked_Cell` | **Missed** (false negative) | No shadow memory; only wrapped cells are watched |
| A slice element, map bucket, struct field, pointer chase | **Missed** | The cell is a single value; there is no aggregate coverage |
| Happens-before established via a channel the bracket does not span | May **false-positive** | The bracket is the only ordering signal; no vector clock |

## Alternatives considered

- **Full TSan-style happens-before detector.** Rejected for v1: shadow
  memory over a Boehm-GC heap plus libco stacks, vector clocks threaded
  through every sync primitive, and whole-program access instrumentation
  is a research-scale effort with a 5-10x cost, on the same footing as
  the precise GC that `CLAUDE.md` defers past 1.0. It remains the
  long-term target and would supersede this ADR.

- **Pure documented-stub fallback (the done-when's OR branch).** A
  `gada-async-race.ads` stub plus this ADR, with a test asserting only
  the documented contract, was the floor the roadmap permitted. Rejected
  because the cooperative checked-cell is small, obviously correct, and
  catches a *genuine* intentional race deterministically — strictly more
  honest value than a stub for roughly the same code size, and it gives
  Phase 4 a real seam to wire transpiler-flagged shared variables into.

- **Lock-discipline detector (flag a cell touched without holding lock
  L).** Rejected for v1: it presumes a lock-to-data binding the runtime
  does not yet model, and Go code idiomatically synchronises via channels
  and `sync/atomic`, not just mutexes — a lockset detector would be a
  poor fit for the language we transpile. The access-section overlap
  model is channel-agnostic and matches Go's own data-race definition
  more directly.

- **Raise an exception on detection instead of latching a report.**
  Rejected: a race detector that aborts the program on the first race
  cannot report a second, cannot be queried non-fatally from a test, and
  conflates "diagnostic finding" with "runtime fault". Go's `-race`
  prints and continues (and only exits non-zero at the end); latching a
  data report mirrors that and keeps the monitor exception-free, which
  also keeps it closer to a future SPARK posture.
