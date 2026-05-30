--  Gada.Core.Panic body — see spec for design.
--
--  ## Per-goroutine pending-panic state (Phase 3 promotion)
--
--  The pending-panic stack used to be a single package-body global
--  (one fixed array + one Natural). That was correct for the v1
--  single-threaded runtime, but Phase 3's scheduler is M:N: several
--  goroutines share one worker (one OS thread), and a single global —
--  or even a `pragma Thread_Local_Storage` slot — would let one
--  goroutine observe or overwrite another's panic state. TLS
--  partitions by *OS thread*; panic state must partition by
--  *goroutine*. (See roadmap/03-concurrency.md, "Promote Gada.Core.
--  Panic Pending stack to per-goroutine storage".)
--
--  The state now lives in a heap-allocated Panic_State_Type per
--  goroutine, reached through the scheduler's opaque per-goroutine
--  slot (`Gada.Async.Scheduler.Get_Local_Storage` /
--  `Set_Local_Storage`). The slot is a bare `System.Address` so the
--  scheduler — which sits at a layer this generic must not force its
--  Payload_Type onto — never names Panic_State_Type. We register a
--  finalizer with Set_Local_Storage; the scheduler runs it when the
--  goroutine is reaped, reclaiming the block. First Do_Panic on a
--  goroutine allocates the block; a goroutine that never panics never
--  allocates (Recover / Is_Panicking only *read* the slot).
--
--  ## Main-task fallback
--
--  The non-goroutine context (the main Ada task before any Spawn, the
--  test harness's own task) has no Goroutine_Record. There,
--  Get/Set_Local_Storage route to a single `Main_Local_Storage`
--  global inside the scheduler — genuinely single-threaded, so a
--  plain global is correct. That fallback is what keeps panic /
--  recover working (and the v1 single-threaded panic_suite passing)
--  with no goroutine in sight. Main-context state is never reaped, so
--  its one block leaks at program exit; the OS reclaims it.
--
--  Zero-alloc on the *steady-state* panic/recover path still holds
--  (the array is fixed, Do_Panic does no allocation once the block
--  exists); the only allocation is the one-time per-goroutine block.
--  Cap of 16 nested panics is unchanged and documented in ADR-0006.

with System;
with System.Address_To_Access_Conversions;
with Ada.Unchecked_Deallocation;
with Gada.Async.Scheduler;

use type System.Address;

package body Gada.Core.Panic is

   --  Cap chosen to comfortably exceed any sane nested-panic
   --  depth a transpiled Go program could produce. Doubling is a
   --  one-line change if a future workload demands it; tracked in
   --  docs/imperfections.md.
   Max_Pending_Panics : constant := 16;

   --  Per-goroutine (or per-main-task) panic state. Heap-allocated on
   --  first Do_Panic, hung off the scheduler's opaque slot, reclaimed
   --  by Finalize_State when the owning goroutine is reaped.
   type Pending_Array is
     array (1 .. Max_Pending_Panics) of Payload_Type;

   type Panic_State_Type is record
      Pending       : Pending_Array := [others => Default];
      Pending_Count : Natural := 0;
   end record;

   package State_Conv is
     new System.Address_To_Access_Conversions (Panic_State_Type);
   subtype State_Access is State_Conv.Object_Pointer;
   use type State_Conv.Object_Pointer;

   procedure Free_State is
     new Ada.Unchecked_Deallocation
       (Object => Panic_State_Type, Name => State_Conv.Object_Pointer);

   --  Reclaimer handed to the scheduler. Runs once, on reap, against
   --  the goroutine's slot address. Called as an ordinary Ada access-
   --  to-procedure (no C convention needed).
   procedure Finalize_State (Addr : System.Address);
   procedure Finalize_State (Addr : System.Address) is
      S : State_Access := State_Conv.To_Pointer (Addr);
   begin
      Free_State (S);
   end Finalize_State;

   --  Read the current context's state without allocating. Returns
   --  null when no panic has ever happened here — Recover and
   --  Is_Panicking use this so a non-panicking context stays
   --  allocation-free.
   function Peek_State return State_Access is
     (State_Conv.To_Pointer (Gada.Async.Scheduler.Get_Local_Storage));

   --  Read-or-create the current context's state. Allocates and
   --  registers the block on first use. Only Do_Panic needs this.
   function Get_State return State_Access;
   function Get_State return State_Access is
      Addr : constant System.Address :=
        Gada.Async.Scheduler.Get_Local_Storage;
   begin
      if Addr /= System.Null_Address then
         return State_Conv.To_Pointer (Addr);
      end if;
      return S : constant State_Access := new Panic_State_Type do
         Gada.Async.Scheduler.Set_Local_Storage
           (Addr      => State_Conv.To_Address (S),
            Finalizer => Finalize_State'Unrestricted_Access);
         --  'Unrestricted_Access (GNAT) bypasses RM 3.10.2(32): the
         --  named Storage_Finalizer access type lives at library level
         --  in the scheduler, while Finalize_State lives in this
         --  generic body. The instantiation is itself library-level
         --  (one per program), so the stored access never dangles —
         --  same idiom the scheduler's Spawn path uses for closures.
      end return;
   end Get_State;

   procedure Do_Panic (Value : Payload_Type) is
      S : constant State_Access := Get_State;
   begin
      --  Bounded — overflow is a programmer error, not a runtime
      --  contract; raise Constraint_Error to surface it loudly.
      if S.Pending_Count >= Max_Pending_Panics then
         raise Constraint_Error
           with "Gada.Core.Panic: pending-panic stack overflow"
                & " (depth >" & Max_Pending_Panics'Image & ")";
      end if;
      S.Pending_Count := @ + 1;
      S.Pending (S.Pending_Count) := Value;
      raise Panicking;
   end Do_Panic;

   function Recover return Payload_Type is
      S : constant State_Access := Peek_State;
   begin
      if S = null or else S.Pending_Count = 0 then
         return Default;
      end if;
      return V : constant Payload_Type := S.Pending (S.Pending_Count) do
         S.Pending (S.Pending_Count) := Default;  -- drop reference
         S.Pending_Count := @ - 1;
      end return;
   end Recover;

   function Is_Panicking return Boolean is
      S : constant State_Access := Peek_State;
   begin
      return S /= null and then S.Pending_Count > 0;
   end Is_Panicking;

end Gada.Core.Panic;
