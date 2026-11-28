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
      Register_Routine (T, Test_GOMAXPROCS'Access, "GOMAXPROCS");
      Register_Routine (T, Test_Gosched_And_GC'Access, "Gosched + GC");
   end Register_Tests;

   procedure Test_Num_Goroutine (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      N0 : Natural;
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 2);
      N0 := Num_Goroutine;   --  baseline AFTER the reset, not before
      Assert (N0 >= 1, "at least the main goroutine is counted");
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

   procedure Test_GOMAXPROCS (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 2);
      Assert (GOMAXPROCS (0) = 2, "query returns 2 workers");
      --  Resize from the main task (non-goroutine context): returns
      --  the old count and applies the new one.
      Assert (GOMAXPROCS (3) = 2, "set returns previous count");
      Assert (GOMAXPROCS (0) = 3, "resize applied, now 3");
      --  Regression (#10): with a goroutine parked on a channel only
      --  main will feed, a resize must not join it (that deadlocked).
      --  It is recorded instead and returns the old count at once.
      Release_Chan := Unit_Channels.Make;
      Ready_Count  := 0;
      Unused_G := Scheduler.Spawn (Blocker_Body'Access);
      for I in 1 .. 5_000 loop
         exit when Ready_Count = 1;
         delay 0.001;
      end loop;
      Assert (GOMAXPROCS (4) = 3, "live resize returns old count");
      Assert (Scheduler.Live_Workers = 3, "live pool not resized");
      Unit_Channels.Send (Release_Chan, True);
      Scheduler.Shutdown;
      --  Recorded request applies at the next default Init.
      Assert (GOMAXPROCS (0) = 4, "not running: reports the recorded 4");
      Scheduler.Init;
      Assert (Scheduler.Live_Workers = 4, "next Init used recorded 4");
      Scheduler.Shutdown;
      --  Before Init: recorded too (no stray pool is started).
      Assert (GOMAXPROCS (2) = 4, "pre-Init set returns old setting");
      Assert (not Scheduler.Is_Running, "pre-Init set starts nothing");
      Assert (Scheduler.Default_Workers = 2, "pre-Init set recorded");
      Scheduler.Set_Default_Workers (0);
   end Test_GOMAXPROCS;

   procedure Test_Gosched_And_GC (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Gosched;  --  no-op outside a goroutine; must not raise
      GC;        --  full collection; must not raise
      Assert (Num_Goroutine >= 1, "runtime still sane after Gosched+GC");
   end Test_Gosched_And_GC;

end Runtime_Suite;
