--  AUnit suite for `Gada.Std.Strings` (Go `strings` port, Phase 5).
--
--  One to three cases per function, focused on Go-semantics edge
--  behavior: 0-based/-1 index contract, non-overlapping Count, Split_N
--  caps, empty-separator splits, trim cutsets, case folding, Replacer
--  priority order.

with AUnit;
with AUnit.Test_Cases;

package Strings_Suite is

   type Strings_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Strings_Test);
   overriding function  Name (T : Strings_Test) return AUnit.Message_String;

   procedure Test_Contains (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Count_Non_Overlapping (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Equal_Fold (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Prefix_Suffix (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Index_Family (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Last_Index_Family (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Split (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Split_N (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Split_After_And_Empty_Sep (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Join (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Fields (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Trim_Family (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Trim_Space_Prefix_Suffix (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Case_And_Map (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Repeat (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Replace (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Replacer (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Edges (T : in out AUnit.Test_Cases.Test_Case'Class);

end Strings_Suite;
