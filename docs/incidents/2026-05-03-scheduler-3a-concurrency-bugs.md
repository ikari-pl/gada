---
type: incident
title: "Scheduler 3a — concurrency bugs surfaced (and fixed) during the first multi-task scheduler bring-up"
created: 2026-05-03
tags: [incident, retro, scheduler, concurrency, phase3, threading, ada-tasks, libco]
related:
  - "[[roadmap/03-concurrency]]"
  - "[[adr/0004-scheduler-libco-for-v1]]"
  - "[[adr/0002-runtime-layered]]"
  - "[[2026-04-30-phase00-done]]"
---

# Scheduler 3a — concurrency bugs surfaced (and fixed) during the first multi-task scheduler bring-up

## TL;DR

Implementing `Gada.Async.Scheduler` sub-item (a) — the minimum-viable
single-worker scheduler — surfaced **three high-severity concurrency
bugs** in code that had been correct under the prior single-thread
assumption. All three were caught by the AUnit suite *before* commit
(no production damage), all three were fixed in the same session, and
all three are exactly the canonical hazards a goroutine-runtime
implementer would expect to hit. This document records them so the
next agent walking into Phase 3 sub-items (b)–(f) doesn't
rediscover them, and so anyone touching `Gada.Async` later understands
*why* the seemingly-overbuilt synchronisation is load-bearing.

The fixes are in commits `5163fa0` (Context thread-safety) and
`f8e796f` (Scheduler 3a). Run `git show 5163fa0 f8e796f` to see the
shipped code.

## Context

Until 2026-05-03, every line of `runtime/src/gada-*` ran from a single
OS thread. `Gada.Core.{Slices,Maps,Hash,Defer,Panic}` are pure data
structures; `Gada.Async.Context` (Phase 3 item 2, completed 2026-05-02)
is a userspace-coroutine wrapper around libco — it switches *stacks*
on the same OS thread, but it doesn't introduce a second OS thread.
Per-package documentation (e.g. `gada-async-context.adb`'s package
head) says explicitly: *"libco is single-thread-context — cothreads
cannot be switched between OS threads. The registry mirrors that
constraint: it is a plain thread-local-shaped global."*

Sub-item 3a is the first place that assumption breaks. The scheduler
introduces a `Worker_Task` (an Ada task, mapped 1:1 to an OS thread on
hosted targets), and the main task continues to call `Spawn` (which
calls `Gada.Async.Context.Make`, which writes the bookkeeping maps).
Two threads now drive the same package — and the previously-safe code
became unsafe in the moment we wired it up.

## Bugs found and fixed

The numbering matches the severity table in the user-facing summary
delivered alongside this incident.

### #1 — `Hashed_Maps` accessed concurrently from main + worker

**Severity: HIGH** — silent runtime UB on every multi-goroutine run.

**Symptom.** First failed test:
```
PROGRAM_ERROR
Exception Message: Gada.Async.Context.Entry_Maps.HT_Types.Implementation
                   .TC_Check: attempt to tamper with cursors
```

**Diagnosis.** `Gada.Async.Context` had two file-scope
`Ada.Containers.Hashed_Maps` instances (`Entries`, `Exits`) protecting
the libco trampoline registry and the per-cothread "exit context" map.
Single-thread access was safe. Multi-thread access is *not*: GNAT's
Hashed_Maps run a `Tampering_Check` whose internal counter is
incremented on each mutation; concurrent mutations from two tasks
race on the counter and the runtime fires the check. Even without
the tamper-check, the underlying bucket array would corrupt.

**Why it surfaced now.** Sub-item 3a's `Spawn` runs
`Gada.Async.Context.Make → Entries.Insert` from the main task; the
`Worker_Task` runs `Trampoline.Take_Entry → Entries.Delete` from its
own OS thread. The two ops can interleave on the same `Entries.Map`.

**Fix (commit `5163fa0`).** Wrap both maps in a single `protected
State` with thin `Register/Take/Drop_Entry`, `Record_If_Absent /
Lookup_Exit / Drop_Exit` operations. Single-mutex serialisation.
Lock is **released across every `Co_Switch`** (critical — see #4).
Per-call hold time is microseconds; the existing 1M-iteration
ping-pong stays well inside its 1 s budget.

**Go comparison.** Go's runtime maps for goroutine bookkeeping
(`allgs`, `P.runq`, etc.) are protected by per-P spinlocks or
designed for lock-free reads with atomic CAS on writes. Our
single-mutex version is the v1 simple choice; if it shows up on
profiles, sub-item 3c's per-worker Chase-Lev deque kills the
contention naturally because it removes the need for a global queue
in the hot path.

**Lessons.** Phase 2 was right to defer this hardening. Speculative
concurrency-proofing of single-threaded code is exactly the
over-engineering AGENTS.md warns against — the cost would have been
paid as confusing API shape ("why are these maps in a protected
object?") long before there was any threat. Pay the cost when the
threat materialises.

### #2 — `Init` returned before `Worker_Task` had bumped `Workers_Active`

**Severity: HIGH** — looked random ("test sometimes passes"),
disastrous to debug downstream.

**Symptom.** The first single-spawn test reported `Counter = 0` after
`Shutdown`. Worker debug prints showed:
```
[DBG] Worker_Task starts
[DBG] Worker_Task Pop returned, Stop=TRUE   ← exited without doing work
```

**Diagnosis.** Original `Init` did:
```ada
Run_Queue.Set_Initialised (True);
The_Worker := new Worker_Task;       -- task starts asynchronously
```
And `Worker_Task` started its body with `Run_Queue.Worker_Started;`
to bump `Workers_Active := 1`. The `Drain` entry's barrier is
`when Workers_Active = 0`. If the freshly-allocated task hadn't yet
got CPU time when the next `Shutdown` fired, `Workers_Active` was
still 0, the Drain barrier fired immediately, and `Shutdown` returned
with the worker still asleep behind it — silent failure.

**Why it surfaced now.** Test ordering. `Test_Init_Shutdown_Empty`
ran first, executing the race in microseconds. The next spawn-using
test then saw an already-stopped worker and `Counter = 0`.

**Fix (commit `f8e796f`).** Bump `Workers_Active` synchronously in
`Init`, *before* allocating the task:
```ada
Run_Queue.Reset_Lifecycle;
Run_Queue.Set_Initialised (True);
Run_Queue.Worker_Started;            -- synchronous, before "new"
The_Worker := new Worker_Task;
```
`Worker_Stopped` at the tail of `Worker_Task` balances the bump.
The Drain barrier now correctly waits even when the worker hasn't
yet touched the run queue.

**Go comparison.** Go's `runtime.schedinit` is synchronous on the
bootstrap M; workers (Ms / Ps) are pre-allocated. The "did the
worker exist yet?" race doesn't appear in Go because there is no
asynchronous "task is being created" window equivalent to Ada's
`new Worker_Task`.

**Lessons.** "Allocate then assume it's running" is a generic
asynchronous-start hazard. Prefer synchronous resource accounting
*at the synchronisation point* (in `Init`, before the asynchronous
constructor) over after-the-fact ("constructor will eventually
register itself").

### #3 — `Shutting_Down` flag sticky across Init/Shutdown cycles

**Severity: HIGH** — silent test-skipping; nothing logs an error.

**Symptom.** With #2 fixed, the first single-spawn test still failed
with `Counter = 0`. Worker debug printed `Pop returned, Stop=TRUE`
immediately on the new worker, again before processing any work.

**Diagnosis.** `Run_Queue.Mark_Shutdown` set `Shutting_Down := True`,
and nothing ever cleared it. The next `Init` started a fresh worker;
that worker's `Pop` re-evaluated its barrier:
```ada
when not Items.Is_Empty
  or else (Shutting_Down and then In_Flight = 0)
```
With no items yet (Spawn hadn't fired), `Shutting_Down=True` (sticky
from prior Shutdown), and `In_Flight=0`, the barrier fired
immediately and `Pop` returned `Stop=True`. Worker exited. The
goroutine queued by the subsequent `Spawn` then sat in the queue
indefinitely, with no consumer.

**Why it surfaced now.** Same test ordering as #2. The first test
called `Init; Shutdown;` — leaving `Shutting_Down=True`. Every
subsequent test inherited that state.

**Fix (commit `f8e796f`).** New `Reset_Lifecycle` protected
procedure called from `Init`:
```ada
procedure Reset_Lifecycle is
begin
   Shutting_Down := False;
   In_Flight := 0;
   while not Items.Is_Empty loop
      Items.Delete_First;
   end loop;
end Reset_Lifecycle;
```
The `Items` drain is defensive — under correct Shutdown semantics it
should already be empty, but a cheap belt-and-braces against future
sub-items that might leave items in the queue on abnormal exit.

**Go comparison.** Go's runtime doesn't have an Init/Shutdown cycle
— the process *is* the runtime. We do, because GADA programs may
construct/tear down the scheduler from a non-`main` entry point
(e.g., a Go program embedded as an Ada library, or a test suite that
needs scheduler isolation between cases). The fix is GADA-specific.

**Lessons.** Lifecycle flags need an *explicit* reset point, not
"some later operation will overwrite them." Document this as a class
of bug for any future stateful-protected-object review.

### #4 — Lock held across `Co_Switch` (avoided by design, named to prevent regression)

**Severity: CRITICAL if introduced.**

This bug did **not** ship — but the protected-State refactor in #1
made it possible to introduce in two characters' worth of typo. If
any operation were to hold the State protected-object lock across
`Libco.Co_Switch`, the cothread that resumes on the other side would
inherit the lock for as long as it ran (potentially forever, for a
long-running goroutine body). Every other thread's access to the
maps would deadlock.

The shipped code carefully shapes every path so the lock is acquired
+ released *before* `Co_Switch`, never around it:
```ada
procedure Switch_To (Target : Context) is ...
begin
   State.Record_Exit_If_Absent (Tgt, Libco.Co_Active);  -- lock + release
   Libco.Co_Switch (Tgt);                                -- no lock held
end Switch_To;
```
And the trampoline tail-loop:
```ada
loop
   Libco.Co_Switch (State.Lookup_Exit (Self));  -- function call
                                                -- evaluates fully
                                                -- before Co_Switch
end loop;
```

**Go comparison.** Go runs all goroutine-bookkeeping under
stop-the-world or per-P locks that are *not* held across `gosched`.
Same hazard, same answer; same invariant must hold in any future
GADA refactor.

**Lessons.** Document this as an inline invariant in
`gada-async-context.adb` — already done in commit `5163fa0`.

## Bugs *not* fixed in this session — items deferred with explicit owner

### #6 — `Goroutine_Record.State` lacks an explicit fence

**Severity: MEDIUM, will become HIGH at sub-item 3b.**

Today, the State writes (`G.State := DONE` in the trampoline,
`G.State := YIELDED` in `Yield`, `G.State := RUNNING` in the worker)
are visible to the worker's post-`Switch_To` read because of the
implicit happens-before chain through the protected `Run_Queue`
operations (`Reap → Pop → Drain`). With **one** worker this is
correct: every State write happens on the same OS thread that later
reads it.

With **N** workers (sub-item 3b), the same goroutine handle can be
written on one OS core and read on another, especially once Park/Unpark
(sub-item 3d) start handing goroutines between workers. The implicit
protected-object barrier no longer covers every write/read pair.

**Action item filed.** Roadmap entry sub-item 3b now carries a
`*Prereq:*` line requiring `pragma Atomic` (or an explicit fence) on
`Goroutine_Record.State` *before* the worker count is grown past 1.
Failing to do this would surface as a Heisenbug under load — the
worst category to debug after the fact.

### Other deferred items

Items #5 (`Yield` from non-goroutine context), #7–11 (single-worker
contention, no stack-overflow detection, no preemption, leak on
panic-without-recover, `Ada.Task_Attributes` overhead) are documented
either in ADR-0004 or in inline comments. They are *known costs of
"GADA is not Go, it's Go-on-Ada"* and are scheduled as their own
roadmap items rather than incident-class issues. See the user-facing
summary appended to PR #2 for the full table.

## Verification

After all fixes landed:

```
$ make ci
...
  PASS: 'runtime/'                100.00%  (>= 100.00%, 435/435 lines, 12 files)
  PASS: 'compiler/internal/emit/'  96.31%  (>= 95.00%, 913/948 lines, 1 files)
  PASS: 'compiler/internal/translate/'
                                   97.12%  (>= 95.00%, 303/312 lines, 1 files)
  PASS: 'compiler/'                95.74%  (>= 90.00%, 1820/1901 lines, 7 files)
=== coverage gate: PASSED ===
```

65 AUnit cases total (8 new scheduler + 57 prior). The eight scheduler
cases include precondition tests for both Init-twice and
Spawn-before-Init, ensuring the documented contracts are themselves
covered.

## Patterns to watch for in sub-items 3b–3f (and beyond)

Each sub-item that lands new goroutine-touching code should answer:

1. **Are any new shared-mutable fields visible across worker boundaries?**
   If yes, name them and decide on the fence/atomic story before merge.
2. **Are any new lifecycle flags introduced?** If yes, ensure
   `Reset_Lifecycle` (or the equivalent) clears them at `Init`.
3. **Are there any new asynchronous "constructor will register itself"
   patterns?** If yes, prefer synchronous accounting at the
   synchronisation point.
4. **Does any new code path hold a protected lock across `Co_Switch`?**
   If yes, it is wrong; refactor to release before switch.
5. **Is the AUnit suite ordered such that a stateful leak from one case
   would visibly poison the next?** Test ordering caught all three
   HIGH bugs above; preserve that property.

## See also

- [[roadmap/03-concurrency]] — Phase 3 tracker, item 3 + sub-items.
- [[adr/0004-scheduler-libco-for-v1]] — the M:N scheduler design ADR
  this work implements.
- [[adr/0002-runtime-layered]] — the layering invariant
  (Gada.Async.Context is a peer of Gada.Async.Scheduler within
  Gada.Async; the scheduler may use Context, channels and select
  build on Park/Unpark exposed by the scheduler, not on raw Context).
- Commit `5163fa0` — Gada.Async.Context protected-State refactor.
- Commit `f8e796f` — Scheduler 3a + Init/Shutdown synchronisation +
  scheduler_suite.
