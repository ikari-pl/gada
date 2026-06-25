--  AUnit suite for Gada.Reflect.Interfaces (Phase 4 item 4c-i): the
--  satisfaction registry — Register / Satisfies round-trip, the
--  unregistered-and-asymmetric negatives, idempotent re-registration,
--  and the No_Type-sentinel rejection on either operand.

with AUnit;
with AUnit.Test_Cases;

package Reflect_Interfaces_Suite is

   type Reflect_Interfaces_Test is
     new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests
     (T : in out Reflect_Interfaces_Test);
   overriding function  Name
     (T : Reflect_Interfaces_Test) return AUnit.Message_String;

   procedure Test_Register_Then_Satisfies
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unregistered_And_Asymmetric
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Duplicate_Register_Idempotent
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Register_No_Type_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Reflect_Interfaces_Suite;
