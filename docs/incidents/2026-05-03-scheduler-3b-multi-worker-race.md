# 2026-05-03 — Scheduler sub-item 3b: multi-worker libco race investigation

## Summary

A first cut at sub-item 3b (GOMAXPROCS worker pool) surfaced an
intermittent crash under multi-worker that single-worker (3a) never hit.
Root cause is **not** the obvious cross-thread libco issue (libco
cothreads cannot migrate between OS threads — the README and our
`Gada.Async.Context.Libco` spec say so plainly); the failure mode
appeared even with strict goroutine-pinning to the worker that first
popped them. Investigation paused; the prereq fence (pragma Atomic on
`Goroutine_Record.State`) shipped on its own as commit `9082328` and
the roadmap entry for 3b grew a follow-up checklist for the next
attempt.

## Reproduction

`runtime/tests/scheduler_suite.adb` Test_Pool_Distributes_Across_Workers
with `Workers => 2, N_Spawns >= 2`, body just records
`Ada.Task_Identification.Current_Task` (no Yield). Runs 1–10 over the
isolated test on macOS arm64 / GNAT FSF 15.1:

| Outcome                                                  | Frequency |
|----------------------------------------------------------|-----------|
| `Successful Tests: 1`                                    | 6–7 / 10  |
| `TRAMP-TAIL FAIL: self=… — Self not in Exits map`        | 2 / 10    |
| Hang inside `Shutdown.Drain` (worker stuck on Switch_To) | 1–2 / 10  |

The TRAMP-TAIL FAIL message is the
`Gada.Async.Context.Trampoline` tail-stub
catching `Constraint_Error` from `Exit_Maps.Element` and re-raising
out of a `Convention => C, No_Return` frame — libco UB, surfaces as
SIGILL with no test summary.

The hang variant happens when an experimental fix (route the final
yield through `Goroutine_Trampoline` directly, bypassing the
Exits-map tail-stub) trips a different path: `Current_Goroutine_Attr.
Value` returns `null` on the goroutine's stack, the `if G /= null`
branch falls through to the defensive busy-loop guard, the worker
suspends on `Switch_To` waiting for a yield-back that never comes.

## What we ruled out

1. **Cross-thread libco cothread migration.** The reproduction uses
   strict goroutine-pinning: each worker, once it Pops a goroutine,
   runs it to completion (yields included) on the same OS thread. No
   `Re_Push` to the shared queue from the YIELDED branch. The same
   address `Self` failing Lookup_Exit was confirmed to be a freshly
   `Co_Create`'d cothread on a single worker's pthread — not migrated.

2. **libco's per-OS-thread state init order.** Each worker calls
   `Co_Active` (initialises `co_active_handle`) before its first
   `Co_Switch`. `co_swap` is a process-global; the test thread's
   `Co_Create` calls `co_init` before any worker runs.

3. **Hashed_Maps under protected.** Switched to per-call
   `Contains`/`Insert`/`Element` patterns inside `protected State`;
   no shared cursor across calls. Protected serialisation is an
   Ada-runtime guarantee.

4. **Single-worker correctness.** `Init (Workers => 1)` runs the
   complete 8-test scheduler suite green every run. The fence
   (pragma Atomic on `State`) is consistent with single-worker
   correctness; the multi-worker race is on top of, not because of,
   the fence.

5. **`Goroutine_Trampoline` falling through to the busy-loop guard.**
   Adding an explicit yield in `Goroutine_Trampoline` (so the libco
   tail-stub is never used) shifts the symptom from CE-on-Lookup_Exit
   to hang-on-Drain, but does not eliminate the underlying race —
   the hang means `G` was `null` from `Current_Goroutine_Attr.Value`
   on the goroutine's stack.

## Top suspect: `Ada.Task_Attributes` thread-safety

Per RM C.7.2 the package is **not** required to be task-safe across
concurrent `Set_Value` from different tasks. GNAT FSF's implementation
uses a global hash keyed on `Task_Id`; concurrent writes from N
worker tasks setting their own task-attribute can race on the table's
internal structure, leaving a stale or partially-written entry that
later reads as `null` or as some other task's pointer.

The "G is null on the goroutine's stack" failure mode is consistent
with this hypothesis: the worker `Set_Value (G)` succeeded on its
own thread, but a sibling worker's concurrent `Set_Value` corrupted
the global table such that subsequent `Value` returns the
`Initial_Value` (`null`) for that key.

The Lookup_Exit-CE failure mode is consistent with a second-order
effect: if worker A's `Switch_To (G.Ctx)` runs `Record_Exit_If_Absent`
on the protected `State`, but a concurrent operation on a *different*
protected (Worker_Recorder, the per-test observation surface) trips
on the same Task_Attributes corruption — the protected lock can be
acquired by a thread whose `Current_Task` is misidentified, leading
to misordered Insert/Delete and missing entries.

Neither hypothesis is conclusively proven. The race is non-deterministic
and the failure modes are downstream of memory corruption.

## Plan for the next attempt

1. **Replace `Ada.Task_Attributes` with explicit per-worker state.**
   Pass the worker's `Goroutine_Access` slot via an OS-thread-local
   variable using `pragma Thread_Local_Storage` (GNAT-specific) or
   via a worker-task discriminant + an in-task local that the
   trampoline can reach without crossing tasks. The current goroutine
   pointer should never go through a process-global hash.
2. **Test the hypothesis in isolation.** Write a standalone
   reproducer (no scheduler, no libco) that just hammers a shared
   `Task_Attribute` from N tasks, asserting per-task `Value` returns
   what each task `Set_Value`'d. If that flakes, the fix lands at
   the runtime layer; if it doesn't, the issue is interaction with
   libco context switching, not Task_Attributes alone.
3. **Add a per-worker stress test under TSan.** GNAT supports
   `-fsanitize=thread`; build the runtime with TSan enabled and
   re-run the multi-worker test. ThreadSanitizer reports on every
   Task_Attributes access if there's a data race on the underlying
   global.
4. **Consider routing through `pragma Volatile_Components`** on the
   per-worker slot if Task_Attributes turns out to be the only issue.
5. **Land the worker-pool change as a single atomic commit** that
   includes the new per-worker storage AND the multi-worker test —
   no half-shipped state where 3a-style code still uses the broken
   Task_Attributes path.

## What shipped

Just the prereq commit (`9082328`):

- `pragma Atomic` on `Goroutine_Record.State` (forward-compatible
  fence, single-worker behaviour unchanged).
- New comment block on the field documenting why State needs the
  fence and why `Worker_Ctx` and `Body_Proc` don't.
- Coverage exclusion line numbers in `tools/coverage_thresholds.toml`
  and `runtime/COVERAGE.md` shifted to track the new comment block.

The roadmap entry for sub-item 3b is updated with this incident as
a Prereq read; the Done bar gains "no `Ada.Task_Attributes` in the
goroutine→worker handoff path" so the next attempt doesn't re-walk
the same trap.
