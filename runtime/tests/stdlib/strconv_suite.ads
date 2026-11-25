--  AUnit suite for `Gada.Std.Strconv` (Go `strconv` port, Phase 5).
--
--  Focused on Go-semantics edge behavior: Atoi sign/overflow clamping
--  with Err_Range, Format_Float's shortest round-trip ('g' prec < 0)
--  and NaN/±Inf spellings, Parse_Float specials and range errors,
--  Quote/Unquote escape handling, and Num_Error Is/As semantics.

with AUnit;
with AUnit.Test_Cases;

package Strconv_Suite is

   type Strconv_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Strconv_Test);
   overriding function  Name (T : Strconv_Test) return AUnit.Message_String;

   procedure Test_Itoa (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Atoi_Ok (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Atoi_Syntax (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Atoi_Range (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Format_Float_G (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Format_Float_F_E (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Parse_Float_Ok (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Parse_Float_Errors (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Quote (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unquote (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unquote_Errors (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Num_Error_Is_As (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Edges (T : in out AUnit.Test_Cases.Test_Case'Class);

end Strconv_Suite;
