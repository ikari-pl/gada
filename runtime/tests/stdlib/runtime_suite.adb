--  Body of Runtime_Suite — see spec for test rationale.
--
--  Num_Goroutine's parked-blocker test spawns two goroutines that
--  park on a channel; the main task polls with a real delay (Yield is
--  a no-op outside a goroutine) and then releases them so Shutdown's
--  drain can finish.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Async.Channels.Unbounded;
with Gada.Async.Scheduler;
with Gada.Std.Runtime; use Gada.Std.Runtime;

package body Runtime_Suite is

   package Scheduler renames Gada.Async.Scheduler;

   package Unit_Channels is new Gada.Async.Channels.Unbounded (Boolean);

   --  Cross-task counter: volatile so the poll loop re-reads memory.
   Ready_Count : Natural := 0;
   pragma Volatile (Ready_Count);

   Release_Chan : Unit_Channels.Channel;

   procedure Blocker_Body is
      V  : Boolean;
      OK : Boolean;
   begin
      Ready_Count := Ready_Count + 1;
      Unit_Channels.Receive (Release_Chan, V, OK);
   end Blocker_Body;

   overriding function Name
     (T : Runtime_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Runtime suite"));

   overriding procedure Register_Tests (T : in out Runtime_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Num_Goroutine'Access, "NumGoroutine");
      Register_Routine (T, Test_Go_Max_Procs'Access, "GOMAXPROCS");
      Register_Routine (T, Test_Go_Sched_And_GC'Access, "Gosched + GC");
   end Register_Tests;

   procedure Test_Num_Goroutine (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      N0 : constant Natural := Num_Goroutine;
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Assert (N0 >= 1, "at least the main goroutine is counted");
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 2);
      Release_Chan := Unit_Channels.Make;
      Ready_Count  := 0;
      Unused_G := Scheduler.Spawn (Blocker_Body'Access);
      Unused_G := Scheduler.Spawn (Blocker_Body'Access);
      --  Spawn bumps the live count synchronously; the poll just makes
      --  sure both blockers actually started.
      for I in 1 .. 5_000 loop
         exit when Ready_Count = 2;
         delay 0.001;
      end loop;
      Assert (Ready_Count = 2, "both blockers started, got"
              & Natural'Image (Ready_Count));
      Assert (Num_Goroutine = N0 + 2, "NumGoroutine counts the 2 parked"
              & " goroutines, got" & Natural'Image (Num_Goroutine));
      Unit_Channels.Send (Release_Chan, True);
      Unit_Channels.Send (Release_Chan, True);
      Scheduler.Shutdown;
      Assert (Num_Goroutine = N0, "back to baseline after drain, got"
              & Natural'Image (Num_Goroutine));
   end Test_Num_Goroutine;

   procedure Test_Go_Max_Procs (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 2);
      Assert (Go_Max_Procs (0) = 2, "query returns 2 workers");
      --  Resize from the main task (non-goroutine context): returns
      --  the old count and applies the new one.
      Assert (Go_Max_Procs (3) = 2, "set returns previous count");
      Assert (Go_Max_Procs (0) = 3, "resize applied, now 3");
      Scheduler.Shutdown;
   end Test_Go_Max_Procs;

   procedure Test_Go_Sched_And_GC (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Go_Sched;  --  no-op outside a goroutine; must not raise
      GC;        --  full collection; must not raise
      Assert (Num_Goroutine >= 1, "runtime still sane after Gosched+GC");
   end Test_Go_Sched_And_GC;

end Runtime_Suite;
