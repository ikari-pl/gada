--  Gada.Async.Scheduler — M:N goroutine scheduler over Ada tasks.
--
--  Public API for the runtime that lowers Go's `go func() { ... }()`,
--  channel send/receive, and `select` onto Ada tasks + libco userspace
--  contexts. Per ADR-0004 (M:N goroutine scheduler over Ada tasks +
--  libco for hosted), each goroutine owns a fixed-size libco context;
--  a small pool of `Worker` Ada tasks drains a shared run queue,
--  Switch_To-ing into each goroutine cooperatively.
--
--  Sub-items 3a + 3b + 3d ship the multi-worker shape:
--    * pool of Worker tasks sized by System.Multiprocessors.Number_Of_CPUs
--      (overridable via Init (Workers => N)),
--    * shared FIFO run queue for fresh spawns + per-worker Inbox queues
--      for yielded + Unparked goroutines (yielded goroutines pin to the
--      worker that first popped them; Park/Unpark route through the
--      same Inbox to preserve the pinning invariant — libco cothreads
--      cannot migrate between OS threads, see ADR-0007 §4),
--    * Spawn / Yield / Init / Shutdown / Park / Unpark.
--    * no work-stealing yet (item 3c),
--    * no syscall handoff (item 3e).
--  Subsequent sub-items extend the body without breaking this spec.
--
--  Usage shape (intentionally minimal — until the compiler's `go`
--  emission lands in item 7, callers wire Spawn directly):
--
--     procedure Hello is
--     begin
--        Ada.Text_IO.Put_Line ("hi from goroutine");
--     end Hello;
--
--     Gada.Async.Scheduler.Init;             --  defaults to Number_Of_CPUs
--     declare
--        G : constant Goroutine_Id :=
--          Gada.Async.Scheduler.Spawn (Hello'Access);
--     begin
--        null;
--     end;
--     Gada.Async.Scheduler.Shutdown;         --  blocks until Hello has run
--
--  Layering: this is the only `Gada.Async` package that is *allowed*
--  to depend on `Gada.Async.Context`. Channels, select, and timers
--  build on Park/Unpark exposed here, not on the raw context API.

package Gada.Async.Scheduler is

   --  Opaque handle to a scheduled goroutine. Returned by Spawn,
   --  consumed by the future Park/Unpark surface (item 3d). Today
   --  callers do not need to do anything with the handle — Shutdown
   --  reaps everything — but exposing it now keeps the spec stable.
   type Goroutine_Id is private;

   No_Goroutine : constant Goroutine_Id;

   --  User-supplied entry procedure for a goroutine. Returns naturally
   --  when the goroutine is "done"; the scheduler reaps it without the
   --  caller doing anything. Cooperative yield happens via Yield
   --  (below) at the body's discretion.
   type Goroutine_Body is access procedure;

   --  Bring up the worker pool. Workers = 0 means
   --  System.Multiprocessors.Number_Of_CPUs. Calling Init twice
   --  without an intervening Shutdown is a precondition violation.
   procedure Init (Workers : Natural := 0);

   --  Schedule Body to run as a new goroutine. Returns a handle
   --  immediately; Body may not have started executing by the time
   --  Spawn returns. Spawn is callable from any context — from inside
   --  a goroutine, from a non-goroutine task, from the main task.
   --  Calling Spawn before Init is a precondition violation.
   function Spawn (Body_Proc : Goroutine_Body) return Goroutine_Id
     with Pre => Body_Proc /= null;

   --  Cooperative yield. When called from inside a goroutine,
   --  suspends the goroutine and returns control to its worker; the
   --  worker may pick up another goroutine and round-robin back.
   --  Calling Yield from a non-goroutine context is a no-op (so
   --  generated code can call it unconditionally without first
   --  asking "am I in a goroutine?").
   procedure Yield;

   --  Suspend the calling goroutine indefinitely. Unlike Yield, the
   --  goroutine is NOT re-enqueued — it sits in suspended limbo until
   --  somebody calls Unpark on its handle. The worker is free to pick
   --  up other goroutines in the meantime. Calling Park from a non-
   --  goroutine context is a no-op (matches Yield).
   --
   --  This is the primitive Phase 3 channel-receive-on-empty-channel,
   --  select-with-no-ready-case, and timer-wait will be built on. Item
   --  3d ships Park/Unpark; the higher-level uses arrive in items 4-6.
   procedure Park;

   --  Make the goroutine identified by G eligible to run again. G is
   --  routed back to the Inbox of its bound worker (the worker that
   --  first ran it) — libco cothreads cannot migrate between OS
   --  threads (ADR-0007 §4), so re-enqueueing onto a different worker
   --  is UB. Calling Unpark on No_Goroutine is a documented no-op.
   --
   --  Precondition: G must have run at least once on some worker
   --  (i.e. its Bound_Worker is set). Calling Unpark on a goroutine
   --  that has never run raises Program_Error — there's no correct
   --  routing target to guess.
   --
   --  Unpark is callable from any context: from inside a (different)
   --  goroutine, from a non-worker task, from the main task. The
   --  protected Inbox handles cross-thread injection.
   procedure Unpark (G : Goroutine_Id);

   --  Block until every spawned goroutine has finished, then tear
   --  down the worker pool. After Shutdown returns, Init must be
   --  called again before any Spawn. Calling Shutdown without a
   --  prior Init is a no-op (idempotent half-init / half-teardown,
   --  matching the Free contract on Gada.Async.Context).
   procedure Shutdown;

private

   --  A Goroutine_Id is a thin wrapper around the heap-allocated
   --  Goroutine_Record (defined in the body). The wrapper exists so
   --  we can stash an Id in a hashed map keyed on something other
   --  than its address later (item 3d's Unpark needs to find a
   --  goroutine by handle without traversing the run queue).
   type Goroutine_Record;
   type Goroutine_Access is access all Goroutine_Record;

   type Goroutine_Id is record
      Ref : Goroutine_Access := null;
   end record;

   No_Goroutine : constant Goroutine_Id := (Ref => null);

end Gada.Async.Scheduler;
