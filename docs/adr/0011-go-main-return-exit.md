---
type: adr
title: "ADR-0011: The process ends when main returns (goroutines are not joined)"
status: accepted
created: 2026-11-27
deciders: [ikari]
tags: [runtime, scheduler, exit, semantics]
related:
  - "[[0004-scheduler-libco-for-v1]]"
  - "[[roadmap/06-stdlib-wave2]]"
---

# ADR-0011: The process ends when main returns (goroutines are not joined)

## Context

Go ends the process the moment `main` returns: goroutines that are
still running, parked on a channel or asleep, and pending timers, are
abandoned. Ada does the opposite — the environment task waits for every
library-level task before the program ends, and an unhandled exception
in the main subprogram waits the same way before the last-chance
handler even prints.

Until Phase 6 the generated main joined: `Scheduler.Shutdown` after the
body waited for every in-flight goroutine. Phase 6's timers made the
mismatch visible (PR #46 review findings #1 and #4): a goroutine parked
on a `time.After` that `Stop_All` had silenced was never woken, so
Shutdown hung forever; a program using `time.Tick` with no `go`
statement skipped `Stop_All` altogether and never exited; and a panic
with a live ticker hung instead of crashing.

## Decision

1. **A generated `package main` whose program owns runtime tasks** (the
   goroutine worker pool, or the `time` service task) ends through
   `Gada.Core.Process.Exit_Main` after main's body and defers: it
   flushes standard output/error and calls `GNAT.OS_Lib.OS_Exit (0)`.
   Nothing is joined; `Scheduler.Shutdown` is no longer emitted.
2. **Main's defers run before the exit.** When Exit_Main is emitted,
   main's `Defer_Block`s are declared in the inner block (as for the
   panic wrapper), because OS_Exit skips Main's own finalization.
3. **An exception escaping main** (an unrecovered panic, or any Ada
   runtime check — Go's runtime errors) goes to
   `Gada.Core.Process.Unhandled`, which prints GNAT's own report line
   (`raised NAME : message`) to standard error and exits with Go's
   panic status **2**. This handler is emitted for every main that
   owns runtime tasks or uses panic/recover; a panic recovered by
   main's defers still returns normally.
   **An early `return` in main** must reach Exit_Main too: when main
   contains one, its body is wrapped in a `Go_Main_Body : loop` and
   the return lowers to `exit Go_Main_Body;`, which leaves the defer
   block normally (defers run) and falls through to Exit_Main. A plain
   Ada `return;` would skip Exit_Main and hang on the worker tasks.
4. **Task-free programs are unchanged**: with nothing to abandon, the
   plain return already matches Go.
5. `Gada.Std.Time.Stop_All` and `Scheduler.Shutdown` stay available for
   hand-written Ada and the test harness; they are no longer
   load-bearing for generated programs.

## Consequences

- **What now becomes easier.** Exit never depends on what goroutines
  or timers are doing, so the whole class of exit hangs (parked
  goroutines, live tickers, long `time.After`, panics with live tasks)
  is gone. Exit statuses match Go (0, and 2 for a crash).
- **What now becomes harder.** Output written by a goroutine with Ada
  I/O other than Ada.Text_IO's standard files is not flushed at exit;
  goroutine finalization (controlled objects on goroutine stacks) never
  runs — exactly as in Go, but different from previous GADA builds.
  The unhandled-exception report no longer includes GNAT's optional
  traceback.
- **What is now off-limits.** Generated mains do not join goroutines at
  exit. A change that reintroduces join-at-exit (e.g. to "let
  goroutines finish") is rejected unless it supersedes this ADR; a Go
  program that needs to wait must use a WaitGroup or channel, as in Go.

## Alternatives considered

- **Keep joining, but close every timer channel in Stop_All** so parked
  receivers wake. Rejected: it runs timeout branches Go never runs, and
  still hangs on any goroutine parked on a user channel.
- **Abort the worker tasks, then return normally.** Rejected: abort is
  Ravenscar-forbidden, abort of a task inside libco cothread switching
  is unsafe, and it still waits for abort completion points.
- **Emit Exit_Main in every main.** Rejected as churn without benefit:
  a task-free program already ends when main returns.
