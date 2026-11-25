--  AUnit suite for `Gada.Std.Errors` (Go `errors` port, Phase 5).
--
--  Covers the Go semantics contract: New/Error round-trip, the
--  With_Cause/Unwrap chain, Is (sentinel identity, nil cases, deep
--  chains), and As (head match, chain match, tag mismatch, null err).

with AUnit;
with AUnit.Test_Cases;

package Errors_Suite is

   type Errors_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Errors_Test);
   overriding function  Name (T : Errors_Test) return AUnit.Message_String;

   procedure Test_New_Error_Message (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unwrap_No_Cause (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unwrap_Chain (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Is_Sentinel (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Is_Deep_Chain (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Is_Nil_Cases (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Is_Distinct_Values (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_As_Head_Match (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_As_Chain_Match (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_As_Tag_Mismatch (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_As_Null_Err (T : in out AUnit.Test_Cases.Test_Case'Class);

end Errors_Suite;
