--  AUnit test suite for `Gada.Core.IO`.
--
--  Each test redirects stdout to a temp file, runs a print sequence,
--  restores stdout, and asserts the captured bytes. Phase 01 covered
--  `Println` (single-line write + terminator); Phase 03 adds the
--  multi-arg `fmt.Println` building blocks — `Print (String)`,
--  `Print (Integer)` (with the leading-blank trim that matches Go's
--  bare-int rendering), and `New_Line`.

with AUnit;
with AUnit.Test_Cases;

package IO_Suite is

   type IO_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out IO_Test);
   overriding function  Name (T : IO_Test) return AUnit.Message_String;

   procedure Test_Println_Hello (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Print_String_No_Newline
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Print_Integer_Trims_Leading_Blank
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Print_Integer_Negative
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_New_Line_Emits_LF
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end IO_Suite;
