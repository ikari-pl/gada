--  AUnit suite for Gada.Async.Scheduler.
--
--  Sub-item (a) of Phase 3 item 3 ships the minimum viable scheduler:
--  one Worker, shared FIFO queue, Spawn / Yield / Init / Shutdown.
--  This suite is the smoke + invariant pass that gates (a) and the
--  scaffolding sub-items (b)-(f) extend in place. Each test names the
--  property it is pinning so a regression points at the missing
--  invariant, not at "the scheduler is broken."

with AUnit;
with AUnit.Test_Cases;

package Scheduler_Suite is

   type Scheduler_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Scheduler_Test);
   overriding function  Name (T : Scheduler_Test) return AUnit.Message_String;

   procedure Test_Init_Shutdown_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Shutdown_Without_Init_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Single_Spawn_Runs_Body
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Multiple_Spawns_All_Run
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Yield_Re_Schedules
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Yield_From_Non_Goroutine_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Init_Twice_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Spawn_Before_Init_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Scheduler_Suite;
