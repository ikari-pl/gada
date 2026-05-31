--  AUnit suite for the Gada.Reflect type registry (Phase 4 item 2b):
--  Register_Type / Lookup round-trip, the unregistered-Id zero value,
--  and last-wins on a duplicate Id.

with AUnit;
with AUnit.Test_Cases;

package Reflect_Suite is

   type Reflect_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Reflect_Test);
   overriding function  Name (T : Reflect_Test) return AUnit.Message_String;

   procedure Test_Register_Then_Lookup
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Lookup_Unknown_Is_Invalid
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Duplicate_Register_Last_Wins
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Register_No_Type_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Reflect_Suite;
