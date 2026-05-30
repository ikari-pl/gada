--  Body of Stress_Scheduler_Suite — see spec for design notes.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;
with Gada.Async.Scheduler;

package body Stress_Scheduler_Suite is

   overriding function Name
     (T : Stress_Scheduler_Test) return AUnit.Message_String is
     (AUnit.Format
        ("GADA scheduler stress suite (PKG=stress.scheduler)"));

   --  Counter incremented by every spawned body. The aspect Atomic
   --  guarantees that *individual* loads and stores cannot tear, but
   --  it does NOT promote the read-modify-write `Spawn_Counter :=
   --  Spawn_Counter + 1` into an atomic add — under multi-worker the
   --  RMW would race and the final count would be < N_Cycles. This
   --  test is *intentionally* single-worker (`Init (Workers => 1)`
   --  in the test body) precisely to keep the increment race-free
   --  without needing System.Atomic_Counters or Ada 2022's
   --  Ada.Atomic_Operations.Modular_Arithmetic. The Atomic aspect is
   --  retained so the *test-side* read after Shutdown sees the most
   --  recent worker store without a memory-model loophole, even
   --  though the workers' writes are already happens-before the
   --  Drain barrier inside Shutdown.
   --
   --  A future leak gate that stresses multi-worker spawn fan-out
   --  would need either a protected counter or an atomic-add
   --  primitive; revisit when Phase 4 adds that surface.
   --  (PR #7 R1 review feedback — "lock-free" wording dropped.)
   Spawn_Counter : Natural := 0
     with Atomic;

   procedure Increment_And_Return is
   begin
      Spawn_Counter := @ + 1;
   end Increment_And_Return;

   overriding procedure Register_Tests
     (T : in out Stress_Scheduler_Test)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_1000_Cycles_Spawn_Return_Reap_Leaks_None'Access,
         "1000 spawn-and-return cycles complete without "
         & "Storage_Error from co_create — every libco stack is "
         & "reaped in the worker's DONE arm rather than leaking "
         & "into vmem");
   end Register_Tests;

   procedure Test_1000_Cycles_Spawn_Return_Reap_Leaks_None
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use Gada.Async.Scheduler;
      Unused_G : Goroutine_Id;

      --  1000 cothread allocations × 256 KB per Spawn = ~256 MB of
      --  cumulative vmem if reaping is broken. Linux's default
      --  /proc/sys/vm/max_map_count is 65 530 vmem regions; macOS
      --  has a per-task vmem ceiling around 1 TB but each mmap
      --  region also costs a kernel handle. Either way, a leak
      --  of 1000 stacks is loud and immediate, surfacing as
      --  Storage_Error from co_create.
      N_Cycles : constant := 1_000;
   begin
      Spawn_Counter := 0;
      Shutdown;
      Init (Workers => 1);
      for I in 1 .. N_Cycles loop
         Unused_G := Spawn (Increment_And_Return'Access);
      end loop;
      Shutdown;

      Assert
        (Spawn_Counter = N_Cycles,
         "Expected" & N_Cycles'Image
         & " spawned bodies to run, got" & Spawn_Counter'Image);
   end Test_1000_Cycles_Spawn_Return_Reap_Leaks_None;

end Stress_Scheduler_Suite;
