--  AUnit suite for `Gada.Core.Process` (Go main-return exit).
--
--  A real exit would end the test runner, so every test installs an
--  exit handler that records the requested status and raises
--  Exit_Called; the default OS_Exit arm is the one documented
--  exclusion (runtime/COVERAGE.md).

with AUnit;
with AUnit.Test_Cases;

package Process_Suite is

   type Process_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Process_Test);
   overriding function  Name (T : Process_Test) return AUnit.Message_String;

   procedure Test_Exit_Main (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unhandled (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Finish_Code (T : in out
      AUnit.Test_Cases.Test_Case'Class);

end Process_Suite;
