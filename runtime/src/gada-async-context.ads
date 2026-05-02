--  Gada.Async.Context — userspace context switching.
--
--  Public API for cooperative coroutine-style context switching: a
--  context owns its own stack, runs a user-supplied procedure when
--  switched to, and yields back via Switch_To. The implementation
--  delegates to the vendored libco library
--  (runtime/src/vendor/libco/) per docs/adr/0004-scheduler-libco-for-v1.md
--  and docs/adr/0007-libco-vendoring.md.
--
--  The full surface (Make / Active / Switch_To / Free) lands in
--  sub-item (e); this skeleton exists so the private child
--  Gada.Async.Context.Libco — the thin C bindings — can be a
--  proper child unit while sub-item (d) stages the libco imports
--  ahead of the user-facing API.

with System;

package Gada.Async.Context is

   --  Opaque handle to a userspace context. Made non-limited so
   --  callers can stash these in arrays/maps; copying the value
   --  shares the underlying libco cothread (which is internally
   --  reference-shared at the C level via co_active / co_switch).

   type Context is private;

   Null_Context : constant Context;

private

   --  At the implementation layer a Context is just libco's
   --  cothread_t (`void*`). We hide System.Address from clients so
   --  the public type can be widened later (priority, debug name,
   --  GC root list, ...) without breaking the public spec.

   type Context is new System.Address;

   Null_Context : constant Context := Context (System.Null_Address);

end Gada.Async.Context;
