--  Gada.Core.Defer — Go-style `defer` via Ada controlled types.
--
--  Go's `defer` semantics:
--    - A `defer` statement registers a call that runs when the
--      enclosing function returns, including under panic.
--    - Multiple defers fire in LIFO order.
--    - Captured arguments are evaluated at defer time (not at run
--      time).
--
--  Ada's `Limited_Controlled` types give us LIFO finalisation for
--  free: objects declared in a block are finalised in reverse order
--  of declaration when the block exits, *including* on exception
--  propagation. We exploit this directly: the compiler-emit layer
--  (Phase 2 item 8) translates each `defer F(args)` into:
--
--     declare
--        Captured_Args : constant ... := <evaluated args>;
--        procedure Wrap is
--        begin
--           F (Captured_Args);
--        end Wrap;
--        D : Gada.Core.Defer.Defer_Block (Wrap'Access);
--     begin ... end;
--
--  Per docs/adr/0006-runtime-performance-bar.md:
--
--    - Zero-alloc. The Defer_Block lives on the caller's stack;
--      the discriminant is just an access value. No heap touch
--      from declaring or finalising one.
--    - Runs under exception unwind (Ada's exception machinery
--      walks finalisation chains identically to normal exit).
--    - O(1) per defer site (one Finalize call) — no chain walk,
--      no allocator, no scheduler.
--
--  Contract with Gada.Core.Panic (next phase item): a deferred
--  call that itself raises is allowed, and the in-flight panic
--  takes precedence. Recover semantics (Phase 2 item 4) read the
--  pending exception payload from inside a deferred call.

with Ada.Finalization;

package Gada.Core.Defer is

   --  Action — a parameterless procedure access. The compiler-emit
   --  layer wraps Go's `defer F(args)` into a closure procedure with
   --  this signature; runtime code calling Defer_Block directly can
   --  pass any matching access (library-level or nested via GNAT's
   --  downward-closure support).
   type Action is access procedure;

   --  Defer_Block — discriminated Limited_Controlled holding the
   --  deferred call. Declaring a Defer_Block in a block schedules
   --  the call for execution at block exit (LIFO with siblings).
   --
   --  Limited semantics — the type cannot be assigned or passed by
   --  value — guarantee the deferred call fires exactly once, at
   --  exactly one place: the declaration's enclosing block.
   --
   --  The discriminant is `not null Action` so a `null` access can
   --  never reach Finalize; an attempt to declare with `null` fails
   --  Ada's discriminant constraint at the point of declaration,
   --  not later at finalisation time.
   type Defer_Block (Op : not null Action) is
     limited new Ada.Finalization.Limited_Controlled with null record;

   overriding procedure Finalize (D : in out Defer_Block);

end Gada.Core.Defer;
