--  Body of Stress_Scheduler_Suite — see spec for design notes.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;
with Gada.Async.Scheduler;

package body Stress_Scheduler_Suite is

   overriding function Name
     (T : Stress_Scheduler_Test) return AUnit.Message_String is
     (AUnit.Format
        ("GADA scheduler stress suite (PKG=stress.scheduler)"));

   --  Lock-free counter incremented by every spawned body. Atomic so
   --  reads from the test side after Shutdown see every increment.
   --  Pragma Atomic on Natural is portable enough for a 32-bit
   --  counter; on a 64-bit host the actual underlying type is
   --  Natural'Size = 32 by default, well within atomic-load reach.
   Spawn_Counter : Natural := 0
     with Atomic;

   procedure Increment_And_Return is
   begin
      Spawn_Counter := Spawn_Counter + 1;
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
