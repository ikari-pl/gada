---
type: note
title: Phase 3 sub-item 3a — async context concurrency hazards (retro)
created: 2026-05-03
tags: [phase-3, concurrency, retro, scheduler, async, spark]
related:
  - "[[roadmap/03-concurrency]]"
  - "[[ADR-0002]]"
  - "[[ADR-0004]]"
  - "[[ADR-0008]]"
  - "[[ADR-0009]]"
---

# Phase 3 sub-item 3a — async context concurrency hazards

Captured 2026-05-03 from the scheduler agent's hand-off after closing
sub-item 3a (minimal single-worker scheduler + 8-test AUnit suite).
Eleven canonical concurrency hazards surfaced during the Phase 2 →
Phase 3 transition, when single-thread-shaped runtime primitives
(`Hashed_Maps` registry, `Workers_Active` counter, `Shutting_Down`
flag) met the M:N scheduler's task pool for the first time.

The retro is preserved here verbatim because the *cross-language*
shape (Ada-task + libco + Boehm-GC vs Go's purpose-built runtime)
makes the hazard list a reusable lookup table for future work:
"did we re-introduce hazard X?" beats "let's discover the canonical
list from scratch." The accompanying [[ADR-0009]] documents the
conditional verification consequence — three of the HIGH items
become statically provable if the scheduler design picks Ravenscar.

## Scheduler agent's retro (verbatim)

> Go inherits decades of CSP-runtime engineering; we are re-walking
> that road on a substrate (Ada tasks + libco + Boehm GC) that
> doesn't share Go's runtime assumptions. Most of these bugs are not
> "Ada is bad" — they're "we are building a goroutine runtime, and
> goroutine runtimes have a fixed list of canonical hazards that
> show up in any language." Each entry below names what Go does to
> avoid it so future debugging can ask "did we re-introduce hazard
> X?" rather than rediscover it.

### #1 — Hashed_Maps tampering across tasks

**Bug surfaced:** `Hashed_Maps` (`Entries` / `Exits`) accessed
concurrently from main + worker tasks — `Spawn` calls `Make` →
`Entries.Insert` from main; worker's trampoline calls `Take_Entry`
/ `Lookup_Exit` / `Drop_*` from worker task. Surfaces as
`Tampering_Check_Failure` ("attempt to tamper with cursors"), or
worse, silent corruption. Fixed by wrapping both maps in a single
protected `State`, lock released across every `Co_Switch`.

**Severity:** HIGH — would have shipped silent UB on every
multi-goroutine run.

**What Go does:** Go's runtime maps for goroutine bookkeeping
(`allgs`, `P.runq`, etc.) are protected by per-P spinlocks or are
designed for lock-free reads with atomic CAS on writes. The "single
mutex" we ship is the v1 simple version; if it shows up on
profiles, sub-item 3c's per-worker deque kills the contention
naturally.

### #2 — Worker task not yet scheduled at Init return

**Bug surfaced:** `Init` returned before its `Worker_Task` got CPU
time → `Drain` barrier `Workers_Active = 0` fired prematurely →
`Shutdown` returned with the worker still asleep behind it.

**Severity:** HIGH — would have looked random ("test sometimes
passes"), disastrous to debug downstream.

**What Go does:** Go's `runtime.schedinit` is synchronous on the
bootstrap M; workers are pre-allocated. We pre-bumped
`Workers_Active` in `Init` for the same effect.

### #3 — Sticky `Shutting_Down` across Init/Shutdown cycles

**Bug surfaced:** `Shutting_Down` flag sticky across Init/Shutdown
cycles — second `Init` reused state from first `Shutdown`; new
worker popped `Stop=True` from an empty-but-shutting-down queue and
exited before any work.

**Severity:** HIGH — silent test-skipping; nothing logs an error;
result looks like "the goroutine just didn't run."

**What Go does:** Go's runtime doesn't have an Init/Shutdown cycle
— the process is the runtime. We do, because GADA programs may
construct/tear down the scheduler from a non-main entry point
(e.g., a Go program embedded as an Ada library). The fix
(`Reset_Lifecycle` in `Init`) is GADA-specific.

### #4 — Lock held across Co_Switch (avoided)

**Bug surfaced:** Lock held across `Co_Switch` would deadlock the
moment a peer task tried to `Make`/`Free` — avoided by design but
worth naming because it's the easy mistake to make in v2 of any of
these protected wrappers.

**Severity:** CRITICAL if introduced — every cothread holds the
lock for as long as it runs (potentially forever for a long
goroutine).

**What Go does:** Go runs all goroutine-bookkeeping under
stop-the-world or per-P locks that are not held across `gosched`.
Same hazard, same answer: the lock release is invariant of the
scheduler.

### #5 — Yield from non-goroutine context

**Bug surfaced:** `Yield` reading `Current_Goroutine_Attr.Value`
returns `null` in non-goroutine context — by design, but only safe
because we documented "Yield from non-goroutine = no-op." A future
generated-code emit that called `Yield` from elaboration-time code
would hit this.

**Severity:** MEDIUM — currently a feature; becomes a hazard once
compiler emits cross go/non-go calls indistinguishably.

**What Go does:** Go's `runtime.Gosched` checks `getg().m.curg`
and is also a no-op when called from a system-stack context. Same
shape, intentional.

### #6 — Goroutine state writes without explicit atomic

**Bug surfaced:** Goroutine state writes (`G.State := DONE`) from
worker stack → read by worker after `Switch_To` returns — relies
on the protected-object happens-before chain (`Reap` → `Pop` →
`Drain`). Works today; would break if anyone added a "race-free
fast path" that skipped the protected object.

**Severity:** MEDIUM — easy regression vector.

**What Go does:** Go uses explicit atomic writes on goroutine
state fields (`atomic.Store` of `_Grunnable`, `_Grunning`,
`_Gsyscall`, `_Gdead`). We rely on the protected-object barrier.
Sub-item 3b should consider `pragma Atomic` on `G.State` for the
same explicitness.

### #7 — Single-worker contention bottleneck

**Bug surfaced:** Single-worker contention bottleneck — `Pop`'s
protected-object lock is the only one. Won't bite until sub-item
3b adds N workers, then it caps at ~1 worker's worth of throughput
regardless of N.

**Severity:** MEDIUM, future.

**What Go does:** Go's per-P local runq is lock-free for the
owning P; only theft crosses the lock boundary. Sub-item 3c's
per-worker Chase-Lev deque is the equivalent; planned.

### #8 — No stack overflow detection

**Bug surfaced:** No stack overflow detection — libco gives each
goroutine a 64 KiB fixed stack; running off the bottom is a
SIGSEGV with no Go-shaped panic.

**Severity:** MEDIUM, by ADR.

**What Go does:** Go grows stacks dynamically (start ~8 KiB, can
reach GiBs). [[ADR-0004]] explicitly forecloses this for v1
(stacks are fixed; overflow panics, not grows); the compiler will
need to emit a stack-headroom check at function entry.

### #9 — No preemption

**Bug surfaced:** No preemption — a tight loop with no `Yield`
starves siblings forever.

**Severity:** MEDIUM, by ADR.

**What Go does:** Go ≥ 1.14 has signal-based preemption;
[[ADR-0004]] documents we ship Go ≤ 1.13's cooperative-only model
in v1.

### #10 — Goroutine leak on panic-without-recover

**Bug surfaced:** Goroutine leak on panic-without-recover — body
panics, trampoline tail never sets `State := DONE`, worker never
reaps, stack + `Goroutine_Record` never freed. Not yet present
(no panics in `Body_Proc` paths today), but a hazard the moment
Phase 2's panic/defer wires through.

**Severity:** MEDIUM, latent.

**What Go does:** Go's runtime catches goroutine-level panics at
the scheduler boundary and either propagates to `os.Exit`
(uncaught) or marks the goroutine `_Gdead`. Need similar wrapping
in `Goroutine_Trampoline` once panic crosses goroutine boundaries.

### #11 — Ada.Task_Attributes overhead per Switch

**Bug surfaced:** `Ada.Task_Attributes` overhead per Switch —
currently unmeasured; if it's a syscall-equivalent it'll dominate
context-switch cost.

**Severity:** LOW, measure-then-decide.

**What Go does:** Go uses `g0.m.curg` — a single pointer load,
hot in cache. If `Ada.Task_Attributes` is a TLS slot it's ~1
instruction; if it's a hashmap lookup, sub-item 3b should use
`pragma Thread_Local_Storage` on a global pointer instead.

### Pattern observation

> The high-severity ones (1, 2, 3) all came from "this is a real
> M:N runtime now, but the underlying primitive (`Hashed_Maps`,
> `Workers_Active`, `Shutting_Down`) was designed assuming the v0
> single-thread world." Phase 2 was right to defer the hardening
> until Phase 3 forced the issue — speculative concurrency-proofing
> of single-threaded code is exactly the over-engineering CLAUDE.md
> warns against. The cost was paid here, in one sitting, with
> tests as the discovery vehicle.

> The MEDIUM/LOW items (5–11) are all documented either in
> [[ADR-0004]] or in inline comments — they're known costs of
> "GADA is not Go, it's Go-on-Ada." The only one I'd flag for
> follow-up before sub-item 3b is #6 (`pragma Atomic` on `G.State`),
> since multi-worker writes to the state field across cores will
> need an explicit fence and "the protected object is implicit"
> gets harder to argue once N > 1.

## SPARK verification analysis

For each hazard above, the question this section answers is: *if
we had had SPARK on the relevant unit, would it have caught this
before the test failure?* The answer informs both [[ADR-0008]]
(SPARK opt-in policy) and [[ADR-0009]] (Ravenscar conditional).

| #  | SPARK could catch? | How                                                              | Cost                                |
|----|--------------------|------------------------------------------------------------------|-------------------------------------|
| 1  | YES (Ravenscar)    | Flow analysis flags any unprotected variable shared across tasks | Whole-Async opt-in to Ravenscar     |
| 2  | NO                 | Liveness/temporal property; outside SPARK's auto-prover scope    | —                                   |
| 3  | YES                | State-machine invariant on a `Lifecycle` enum, `Pre/Post` on Init/Shutdown — spec-level only, body stays Off | Small: ~15 LOC of contract glue     |
| 4  | YES (Ravenscar)    | Ravenscar bans blocking calls (incl. `Co_Switch`) inside protected actions | Same as #1                          |
| 5  | YES                | `Pre => In_Goroutine_Context` on `Yield` with a Ghost helper     | Small: ~10 LOC                      |
| 6  | YES (Ravenscar)    | Ravenscar requires `pragma Atomic` on shared scalars; gnatprove enforces | Same as #1                          |
| 7  | NO                 | Performance, not correctness                                     | —                                   |
| 8  | YES (sibling tool) | `gcc -fstack-usage` per-function `.su` files; aggregator script  | Medium: `tools/stackcheck.sh`       |
| 9  | NO                 | By ADR; not a verification target                                | —                                   |
| 10 | MAYBE              | SPARK ownership / `Pointer_Borrowing_Profile` if `Goroutine_Record` is modeled as owned | Large; deferred                     |
| 11 | NO                 | Performance                                                      | —                                   |

### Three load-bearing observations

1. **Items 1, 4, 6 — the HIGH-severity ones — all flip from "test
   discovers" to "compile-time error" if the scheduler picks a
   Ravenscar-compatible design.** That is the verification
   consequence of a scheduler-design choice that has not been made
   yet, and is the subject of [[ADR-0009]]. The retro frames the
   choice as performance/flexibility vs proof-of-correctness; the
   ADR makes the proof side concrete.

2. **Items 3 and 5 are achievable today, no Ravenscar required.**
   Spec-level `Pre/Post` contracts with body kept `SPARK_Mode (Off)`
   — the "Mixed" posture this PR adds to [[runtime/PROOF.md]].
   Body still touches libco; spec contracts gate callers regardless.

3. **Item 8 is the only one with a vendor-tool gap.** `gnatstack`
   is GNAT Pro / commercial only. The open-source equivalent is
   `gcc -fstack-usage` plus an aggregator script — `tools/stackcheck.sh`
   in this PR. Catches "function uses too much stack" before any
   call-chain analysis lands.

## Cross-references and follow-ups

- **[[ADR-0009]]** — verification consequence of the scheduler-
  design choice between Ravenscar and a fully-dynamic M:N.
- **[[runtime/PROOF.md]]** — Mixed-posture recipe for items 3 and 5,
  applicable to `Gada.Async.*` once Phase 3 lands on `main`.
- **[[runtime/STACK.md]]** — `tools/stackcheck.sh` budget ledger
  for hazard #8; first numbers populated against Phase 2 runtime.
- **Item #6 (`pragma Atomic` on `G.State`)** — flagged by the
  scheduler agent themselves as a sub-item 3b prereq. Not addressed
  here; left to scheduler-side follow-up.
- **Item #10 (panic-leaked goroutine)** — latent until Phase 2
  panic/defer wires across goroutine boundaries; revisit when
  `Goroutine_Trampoline` learns to catch unhandled exceptions.
