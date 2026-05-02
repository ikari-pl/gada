--  AUnit suite for Gada.Core.Maps.
--
--  Tests target every branch in the Swiss-table runtime to hold
--  the runtime/ 100% coverage gate. The map under test is
--  instantiated once with (Integer, Integer, Fibonacci hash, "=",
--  Default = -1). Two helper instantiations (Adversarial_Hash,
--  Identity_Hash) drive collision-heavy probe sequences.

with AUnit;
with AUnit.Test_Cases;

package Maps_Suite is

   type Maps_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Maps_Test);
   overriding function  Name (T : Maps_Test) return AUnit.Message_String;

   procedure Test_Empty_Map_Defaults
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Insert_And_Get
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Insert_Updates_Existing
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Delete_Present
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Delete_Absent_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Grow_On_Load_Factor
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Iterate_All_Entries
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Iterate_Empty_Map
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Make_Map_With_Hint
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Tombstone_Reuse
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Adversarial_Probe_Chain
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Clear
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Get_Found_Variant
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Tombstone_Driven_Grow
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Iterate_With_Empty_Prefix
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Maps_Suite;
