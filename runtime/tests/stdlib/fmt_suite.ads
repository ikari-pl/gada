--  AUnit suite for `Gada.Std.Fmt` (Go `fmt` port, Phase 5).
--
--  Covers the documented verb/flag set (docs/fmt_verb_support.md):
--  integer bases with sign/zero/hash flags, width and precision,
--  strings with %q, floats via strconv, bools, pointers, errors,
--  %% and bad verbs; Errorf's %w wrapping; Sscanf round-trips and
--  error paths.

with AUnit;
with AUnit.Test_Cases;

package Fmt_Suite is

   type Fmt_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Fmt_Test);
   overriding function  Name (T : Fmt_Test) return AUnit.Message_String;

   procedure Test_Sprintf_Int (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Sprintf_Str_Bool (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Sprintf_Float (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Sprintf_Misc (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Errorf (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Sscanf (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Print_Family (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Edges (T : in out AUnit.Test_Cases.Test_Case'Class);

end Fmt_Suite;
