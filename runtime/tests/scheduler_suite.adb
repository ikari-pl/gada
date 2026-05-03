--  Body of Scheduler_Suite — see spec for property list.
--
--  Globals (Counter, Done_Yields) are package-level rather than
--  test-procedure locals because the goroutine bodies passed to Spawn
--  are parameterless `access procedure` values: there is no closure
--  mechanism to thread per-test state through, so the bodies must
--  reach through file-scope state. Each test resets the globals it
--  reads before driving Spawn — order-of-registration is not
--  contractual under AUnit, defensive resets keep failures localised.
--
--  Single-worker safety note (sub-item 3a): the scheduler clamps to
--  one Worker task today, and goroutine yields are cooperative — every
--  increment of the shared counters is serialised through the same
--  worker. No data race, no atomic needed. Sub-item (b) bumps the
--  worker count and revisits this assumption.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Async.Scheduler; use Gada.Async.Scheduler;

package body Scheduler_Suite is

   Counter        : Natural := 0;
   Yield_Iterations : constant := 100;
   Yields_Run     : Natural := 0;
   Yield_Done     : Boolean := False;

   procedure Increment_Once;
   procedure Yield_Then_Mark;

   procedure Increment_Once is
   begin
      Counter := Counter + 1;
   end Increment_Once;

   procedure Yield_Then_Mark is
   begin
      for Iteration in 1 .. Yield_Iterations loop
         Yields_Run := Yields_Run + 1;
         Gada.Async.Scheduler.Yield;
      end loop;
      Yield_Done := True;
   end Yield_Then_Mark;

   overriding function Name
     (T : Scheduler_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Async.Scheduler suite (PKG=async.scheduler)"));

   overriding procedure Register_Tests (T : in out Scheduler_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Init_Shutdown_Empty'Access,
         "Init followed immediately by Shutdown drains a zero-"
         & "goroutine pool without raising");
      Register_Routine
        (T, Test_Shutdown_Without_Init_Is_Noop'Access,
         "Shutdown without a prior Init is the documented "
         & "idempotent no-op (matches Free on Context)");
      Register_Routine
        (T, Test_Single_Spawn_Runs_Body'Access,
         "Spawn (Body) actually runs Body — counter advances by "
         & "exactly one between Spawn and Shutdown return");
      Register_Routine
        (T, Test_Multiple_Spawns_All_Run'Access,
         "100 Spawns of Increment_Once leave Counter = 100 — "
         & "queue ordering doesn't drop or duplicate goroutines");
      Register_Routine
        (T, Test_Yield_Re_Schedules'Access,
         "A goroutine that calls Yield N times completes all N "
         & "iterations — the worker re-pushes YIELDED goroutines");
      Register_Routine
        (T, Test_Yield_From_Non_Goroutine_Is_Noop'Access,
         "Yield called from the main task (no current goroutine) "
         & "returns immediately and does not stall the test");
      Register_Routine
        (T, Test_Init_Twice_Raises'Access,
         "Init called twice without an intervening Shutdown raises "
         & "Program_Error — the precondition documented on Init");
      Register_Routine
        (T, Test_Spawn_Before_Init_Raises'Access,
         "Spawn called before Init raises Program_Error — the "
         & "precondition documented on Spawn");
   end Register_Tests;

   procedure Test_Init_Shutdown_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Defensive: a previous test that raised before its own Shutdown
      --  could leave the scheduler initialised. AUnit doesn't guarantee
      --  ordering, and Init-twice is a precondition violation; the
      --  shutdown-when-not-init contract is documented as no-op so
      --  this is always safe.
      Shutdown;
      Init;
      Shutdown;
      --  Reached here without raising = success. The goroutine pool
      --  drained correctly with zero work in flight.
      Assert (True, "Init+Shutdown completed without raising");
   end Test_Init_Shutdown_Empty;

   procedure Test_Shutdown_Without_Init_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Documented contract: Shutdown without prior Init is a no-op.
      --  A regression that raised here would break clean teardown
      --  paths in higher layers (the user's main() may call Shutdown
      --  on every exit branch even when Init was guarded by a
      --  conditional that didn't fire).
      Shutdown;
      Assert (True, "Shutdown without Init returned cleanly");
   end Test_Shutdown_Without_Init_Is_Noop;

   procedure Test_Single_Spawn_Runs_Body
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Goroutine_Id;
   begin
      Counter := 0;
      Shutdown;  --  defensive: prior-test leftover wouldn't survive Init
      Init;
      Unused_G := Spawn (Increment_Once'Access);
      Shutdown;
      Assert (Counter = 1,
              "Increment_Once body did not run; Counter ="
              & Counter'Image);
   end Test_Single_Spawn_Runs_Body;

   procedure Test_Multiple_Spawns_All_Run
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Goroutine_Id;
   begin
      Counter := 0;
      Shutdown;
      Init;
      for Iteration in 1 .. 100 loop
         Unused_G := Spawn (Increment_Once'Access);
      end loop;
      Shutdown;
      Assert (Counter = 100,
              "Expected Counter = 100, got" & Counter'Image);
   end Test_Multiple_Spawns_All_Run;

   procedure Test_Yield_Re_Schedules
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Goroutine_Id;
   begin
      Yields_Run := 0;
      Yield_Done := False;
      Shutdown;
      Init;
      Unused_G := Spawn (Yield_Then_Mark'Access);
      Shutdown;
      Assert (Yields_Run = Yield_Iterations,
              "Expected" & Yield_Iterations'Image
              & " yield iterations, got" & Yields_Run'Image);
      Assert (Yield_Done,
              "Yield_Then_Mark did not reach the post-loop marker");
   end Test_Yield_Re_Schedules;

   procedure Test_Yield_From_Non_Goroutine_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Init bumps the scheduler online but we never Spawn, so the
      --  main test task is not a goroutine context. Yield must early-
      --  exit. A regression that called Switch_To on a null
      --  Worker_Ctx would either raise or hang here.
      Shutdown;
      Init;
      Gada.Async.Scheduler.Yield;
      Shutdown;
      Assert (True, "Yield from main task returned cleanly");
   end Test_Yield_From_Non_Goroutine_Is_Noop;

   procedure Test_Init_Twice_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Raised : Boolean := False;
   begin
      Shutdown;
      Init;
      begin
         Init;
      exception
         when Program_Error =>
            Raised := True;
      end;
      Shutdown;
      Assert (Raised,
              "Init called twice without Shutdown should raise "
              & "Program_Error");
   end Test_Init_Twice_Raises;

   procedure Test_Spawn_Before_Init_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Raised   : Boolean := False;
      Unused_G : Goroutine_Id;
   begin
      Shutdown;  --  ensure not initialised
      begin
         Unused_G := Spawn (Increment_Once'Access);
      exception
         when Program_Error =>
            Raised := True;
      end;
      Assert (Raised,
              "Spawn before Init should raise Program_Error");
   end Test_Spawn_Before_Init_Raises;

end Scheduler_Suite;
