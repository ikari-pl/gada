--  Gada.Async.Context — userspace context switching.
--
--  Public API for cooperative coroutine-style context switching: a
--  context owns its own stack, runs a user-supplied procedure when
--  switched to, and yields back via Switch_To. The implementation
--  delegates to the vendored libco library
--  (runtime/src/vendor/libco/) per docs/adr/0004-scheduler-libco-for-v1.md
--  and docs/adr/0007-libco-vendoring.md.
--
--  Usage shape (intentionally minimal — the scheduler in Phase 3
--  item 3 is what most callers will reach for):
--
--     procedure Pong;
--     procedure Ping is
--     begin
--        loop
--           --  ... do work ...
--           Switch_To (Ping_To_Pong);
--        end loop;
--     end Ping;
--
--     Ctx_Pong : Context;
--     Make (Ctx_Pong, Pong'Access);
--     Switch_To (Ctx_Pong);   --  Pong starts running here.
--
--  Single-thread caveat: libco's default build is per-OS-thread.
--  Contexts created on one Ada task cannot be switched to from
--  another. Cross-thread coordination is the Phase 3 scheduler's
--  job; Context itself stays thread-bound.

with System;

package Gada.Async.Context is

   --  Opaque handle to a userspace context. Made non-limited so
   --  callers can stash these in arrays/maps; copying the value
   --  shares the underlying libco cothread.
   type Context is private;

   Null_Context : constant Context;

   --  User-supplied entry procedure. Run when the owning context is
   --  first switched to. When the procedure returns, behaviour is
   --  undefined unless the caller arranged a Switch_To back first —
   --  Go's scheduler does this automatically; until the scheduler
   --  lands, callers should ensure the entry never falls off the end.
   type Entry_Procedure is access procedure;

   --  Allocate a fresh context with its own stack (default 64 KiB —
   --  enough for typical goroutine-shaped work; the scheduler will
   --  later make this configurable per-spawn). Entry_Point runs only
   --  when the context is first switched to; Make itself does not
   --  transfer control.
   procedure Make
     (C           : out Context;
      Entry_Point : Entry_Procedure;
      Stack_Size  : Positive := 64 * 1024)
     with Pre  => Entry_Point /= null,
          Post => C /= Null_Context;

   --  The currently executing context. The "main" context (the one
   --  the OS thread starts on) is materialised lazily by libco on
   --  first call; there is no need for an explicit Make for it.
   --  Useful as the Switch_To target when a coroutine wants to yield
   --  back to its caller.
   function Active return Context;

   --  Suspend the caller and resume Target. Returns when some other
   --  context switches back. Switching to the active context is a
   --  no-op (libco swaps to itself); switching to Null_Context is a
   --  precondition violation.
   procedure Switch_To (Target : Context)
     with Pre => Target /= Null_Context;

   --  Release the stack and bookkeeping. Sets C to Null_Context.
   --  Calling Free on Null_Context is a no-op (idempotent
   --  half-init / half-teardown). Calling Free on the active context
   --  is a precondition violation — libco would free its own stack
   --  out from under the running code.
   procedure Free (C : in out Context)
     with Pre => C = Null_Context or else C /= Active;

private

   --  At the implementation layer a Context is just libco's
   --  cothread_t (`void*`). We hide System.Address from clients so
   --  the public type can be widened later (priority, debug name,
   --  GC root list, ...) without breaking the public spec.
   type Context is new System.Address;

   Null_Context : constant Context := Context (System.Null_Address);

end Gada.Async.Context;
