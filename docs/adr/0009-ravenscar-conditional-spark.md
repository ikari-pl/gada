---
type: adr
title: "ADR-0009: Ravenscar scheduler design unlocks SPARK on three concurrency hazards"
status: accepted
created: 2026-05-03
deciders: [ikari]
tags: [spark, ravenscar, scheduler, concurrency, verification]
related:
  - "[[0002-runtime-layered]]"
  - "[[0004-scheduler-libco-for-v1]]"
  - "[[0008-spark-policy]]"
  - "[[2026-05-03-async-context-concurrency]]"
---

# ADR-0009: Ravenscar scheduler design unlocks SPARK on three concurrency hazards

## Context

[[0008-spark-policy]] established that `Gada.Async.*` is permanently
opted out of SPARK because the runtime needs raw addresses, C
bindings, finalisation, and **non-Ravenscar tasking**. That last
clause was written before the scheduler design was settled. Phase 3
sub-item 3a (single-worker scheduler + 8-test AUnit suite) has now
surfaced eleven canonical concurrency hazards (see
[[2026-05-03-async-context-concurrency]]); three of the HIGH-severity
ones — Hashed_Maps tampering across tasks (#1), lock held across
`Co_Switch` (#4), goroutine-state writes without explicit atomic
(#6) — are exactly the class SPARK can statically forbid **provided
the runtime is in the Ravenscar profile**.

The scheduler-design choice between **Ravenscar** (fixed worker pool,
protected objects, no dynamic priorities, no abort, no relative
delays) and **fully-dynamic M:N** (rendezvous, `delay until`,
priorities, dynamic worker spawn) has not been made yet. Both
support the M:N-over-fixed-pool shape sub-item 3 commits to. The
two paths have different verification consequences, and that
consequence has not been on the table during scheduler-design
discussion to date.

The cost of *making the consequence visible* is one ADR. The cost
of *deciding incorrectly without it on the table* is silently
foreclosing a verification capability that aligns with Pure Goal
#5 ("Cross-compilation reach... ARM Cortex-M with Ravenscar,
anything GCC supports") and Pure Goal #4 ("the verification path
is real").

## Decision

1. **The scheduler-design choice is a verification choice.** A
   Ravenscar-compatible scheduler unlocks compile-time discovery
   of hazards #1, #4, and #6. A non-Ravenscar scheduler ships
   those hazards as test-discoverable only. Both are defensible
   trade-offs; the choice is not.

2. **If sub-item 3b (multi-worker) lands a Ravenscar-compatible
   design, the [[0008-spark-policy]] entry for `Gada.Async.Scheduler`
   flips from `Off` (permanent) to `On` (Ravenscar profile).** No
   change to spec / body source needed beyond the
   `pragma Profile (Ravenscar);` configuration pragma and the
   matching `SPARK_Mode => On` aspect. `runtime/PROOF.md` gains a
   row. `tools/prove.sh` gains the unit name in `OPT_IN_UNITS`.

3. **If sub-item 3b lands a non-Ravenscar design, the [[0008-spark-policy]]
   entry stays `Off` permanently.** Hazards #1, #4, #6 remain
   test-discoverable (which is where they live today, post-
   sub-item 3a hardening). This ADR documents that the choice was
   made knowingly, not by oversight.

4. **The decision belongs to the scheduler agent, not this ADR.**
   This ADR records the *consequence*; the *choice* is theirs to
   make based on the performance, flexibility, and certification-
   path trade-offs that this ADR does not weigh in on. A follow-up
   ADR (or roadmap note) will record which path was taken.

## Consequences

- **What now becomes easier.** The scheduler-design discussion
  gains a fourth axis: verification capability. Currently the
  trade-off is being framed as performance (lock-free deque, work
  stealing) vs simplicity (single mutex, fixed pool). Adding "and
  if Ravenscar, hazards #1/#4/#6 become impossible by construction"
  to the trade-off is the value this ADR adds. A scheduler PR that
  ships Ravenscar gets the SPARK opt-in for free; the scheduler
  spec already has to choose protected-object discipline, and
  Ravenscar is the SPARK-provable subset of that discipline.

- **What now becomes harder.** The scheduler agent now has to
  weigh verification capability against the design constraints
  Ravenscar forecloses: no `delay until` with absolute time
  computed dynamically (the scheduler may want this for fair
  scheduling), no abort (which we don't need but which the
  Ravenscar profile bans wholesale), no priority changes after
  task creation (which the Phase 4 priority-inheritance feature
  will need a workaround for). Each of those is documented but
  not fatal. The cost is one extra design-review pass.

- **What is now off-limits.** A scheduler PR that picks
  non-Ravenscar without a one-paragraph rationale ("we accept
  that hazards #1/#4/#6 stay test-discoverable because feature X
  requires Y, which Ravenscar forbids") is rejected at PR review.
  The choice does not need to favour Ravenscar; it does need to
  be explicit.

## Alternatives considered

- **Decide for the scheduler agent in this ADR.** Rejected: the
  scheduler-design trade-offs (performance, fair scheduling,
  certification path) sit outside the verification axis this ADR
  is qualified to weigh. Pre-empting that decision from a
  verification ADR would be process drift — verification is one
  input to scheduler design, not the only one.

- **Defer the verification analysis until sub-item 3b ships.**
  Rejected: the consequence has to be visible *during* the
  scheduler-design discussion, not after. Once non-Ravenscar code
  is on `main`, retrofitting Ravenscar means rewriting the
  scheduler — a much higher cost than evaluating the trade-off
  upfront.

- **Pick Ravenscar by fiat as a verification dictate.** Rejected:
  Ravenscar's restrictions (no abort, no relative delays beyond
  the simplest form, no dynamic priority changes) may force
  scheduler-design choices that hurt other Pure Goals. The
  verification value is real, but it is not lexicographically
  superior to the other goals.

- **Make this an inline comment on the scheduler ADR (which does
  not yet exist).** Rejected: the verification consequence is
  cross-cutting and survives a scheduler-design ADR rewrite. ADR-
  level visibility ensures it isn't lost in a comment refactor.
