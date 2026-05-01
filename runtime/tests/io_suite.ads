--  AUnit test suite for `Gada.Core.IO`.
--
--  Phase 01 ships exactly one test: redirect stdout to a temp file,
--  call `Gada.Core.IO.Println ("hello, GADA")`, restore stdout, and
--  assert the captured bytes equal `"hello, GADA" & ASCII.LF`. This
--  exercises both the Println contract (single-line write with a
--  terminator) and the AUnit harness wiring end-to-end.

with AUnit;
with AUnit.Test_Cases;

package IO_Suite is

   type IO_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out IO_Test);
   overriding function  Name (T : IO_Test) return AUnit.Message_String;

   procedure Test_Println_Hello (T : in out AUnit.Test_Cases.Test_Case'Class);

end IO_Suite;
