--  Gada.Async.Context.Libco — thin C bindings to vendored libco.
--
--  Private child of Gada.Async.Context: external `with`-ing is rejected
--  at compile time, mirroring the Gada.Core.Memory.Libgc pattern from
--  Phase 2. Higher layers reach for libco only via Gada.Async.Context
--  (and, later, Gada.Async.Scheduler), keeping the layering contract
--  from docs/adr/0002-runtime-layered.md intact.
--
--  Bindings are pragma Imports — no body. The C symbols resolve at link
--  time from runtime/src/vendor/libco/{amd64,aarch64}.c (the per-arch
--  source the gpr selects via the ARCH scenario variable per
--  docs/adr/0007-libco-vendoring.md §5).
--
--  Single-thread caveat: libco's default build (which we use) is
--  single-thread-context. Cothreads created on one OS thread cannot be
--  switched to from another. The scheduler (Phase 3 item 3) layers
--  multi-thread coordination on top of this — Context itself stays
--  thread-bound.

with Interfaces.C;
with System;

private package Gada.Async.Context.Libco is

   --  libco's `cothread_t` is `typedef void* cothread_t;` — exposing
   --  it here as System.Address keeps the C-side signatures honest.
   --  The public Context type is a private derivation of
   --  System.Address (see Gada.Async.Context's private part), so
   --  conversions inside the Gada.Async.Context body don't need an
   --  unchecked cast.

   subtype Cothread is System.Address;

   Null_Cothread : constant Cothread := System.Null_Address;

   --  Function-pointer type matching libco's `void (*)(void)` entry
   --  point. The `with Convention => C` is load-bearing: an Ada
   --  `access procedure` without it would have a different ABI on
   --  some targets (extra hidden context parameter for nested
   --  procedures), and libco would call it with stale registers.
   type C_Entry is access procedure with Convention => C;

   --  The active cothread for the calling OS thread. The "main"
   --  cothread (the one the OS thread starts on) is materialised
   --  lazily by libco on first call; there is no need for an
   --  explicit Make for it.
   function Co_Active return Cothread;
   pragma Import (C, Co_Active, "co_active");

   --  Allocate a fresh cothread with its own stack. The entry point
   --  runs *only* when the cothread is first switched to — co_create
   --  itself does not transfer control. Stack_Size is in bytes; libco
   --  rounds up to a page boundary internally.
   function Co_Create
     (Stack_Size  : Interfaces.C.unsigned;
      Entry_Point : C_Entry) return Cothread;
   pragma Import (C, Co_Create, "co_create");

   --  Suspend the caller and resume Target. Returns when some other
   --  cothread switches back to the caller. If Target's entry
   --  procedure has already returned, behaviour is undefined — the
   --  Phase 3 scheduler is responsible for never reaching that state.
   procedure Co_Switch (Target : Cothread);
   pragma Import (C, Co_Switch, "co_switch");

   --  Free the stack and bookkeeping owned by the cothread. Must
   --  *not* be called on the active cothread (libco would free its
   --  own stack out from under the running code). The public
   --  Gada.Async.Context.Free surface enforces this precondition.
   procedure Co_Delete (Co : Cothread);
   pragma Import (C, Co_Delete, "co_delete");

end Gada.Async.Context.Libco;
