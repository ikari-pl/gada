--  AUnit suite for Gada.Async.Scheduler.
--
--  Sub-items 3a + 3b of Phase 3 ship the multi-worker scheduler:
--  Spawn / Yield / Init / Shutdown driving a pool of Worker Ada tasks
--  over a shared FIFO + per-worker yielded queues. This suite is the
--  smoke + invariant pass that gates 3a/3b and the scaffolding sub-
--  items (c)-(f) extend in place. Each test names the property it is
--  pinning so a regression points at the missing invariant, not at
--  "the scheduler is broken."

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
   procedure Test_Pool_Distributes_Across_Workers
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Init_Default_Number_Of_CPUs
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Park_Unpark_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Park_From_Non_Goroutine_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unpark_Of_No_Goroutine_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unpark_Of_Never_Run_Goroutine_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Enter_Exit_Syscall_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Syscall_Doesnt_Stall_Siblings
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Goroutine_Body_That_Raises_Is_Reaped_Cleanly
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Panic_Isolation_Across_Goroutines
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Panic_Main_Fallback
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Scheduler_Suite;
