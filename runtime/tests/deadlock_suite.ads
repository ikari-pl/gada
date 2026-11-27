--  AUnit suite for main-task deadlock detection (PR #46 review #11).
--
--  Go aborts with "fatal error: all goroutines are asleep - deadlock!"
--  (exit 2) when main blocks and nothing can wake it. The runtime
--  reports the same from Scheduler.Main_Block / Selector.Select_One,
--  but only when detection is enabled and no goroutine or timer could
--  make progress. Tests install a Gada.Core.Process exit handler so the
--  report is observable without ending the runner, and check the
--  no-false-positive side: pending timers and live goroutines keep the
--  main task waiting.

with AUnit;
with AUnit.Test_Cases;

package Deadlock_Suite is

   type Deadlock_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Deadlock_Test);
   overriding function  Name (T : Deadlock_Test) return AUnit.Message_String;
   overriding procedure Tear_Down (T : in out Deadlock_Test);

   procedure Test_Unbounded_Receive (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Bounded_Send_Receive (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Select (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Stopped_Ticker (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_No_False_Positive (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Disabled_And_Returning_Handler (T : in out
      AUnit.Test_Cases.Test_Case'Class);

end Deadlock_Suite;
