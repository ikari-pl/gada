--  AUnit suite for Gada.Reflect.Values (Phase 4 item 3): the
--  reflect.TypeOf / reflect.ValueOf entry points — Type_Of round-trip,
--  scalar Value_Of + accessors, the composite type-only Value_Of, and
--  the kind-mismatch Constraint_Error on each scalar accessor.

with AUnit;
with AUnit.Test_Cases;

package Reflect_Values_Suite is

   type Reflect_Values_Test is
     new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Reflect_Values_Test);
   overriding function  Name
     (T : Reflect_Values_Test) return AUnit.Message_String;

   procedure Test_Type_Of
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Value_Of_Scalars
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Value_Of_Composite
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Composite_Box_Of_Scalar_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Scalar_Accessor_Mismatch_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Reflect_Values_Suite;
