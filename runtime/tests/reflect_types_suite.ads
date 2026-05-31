--  AUnit suite for Gada.Reflect.Types — the Phase 4 type-metadata
--  schema. Covers descriptor construction (scalar, struct, composite),
--  the field / method builders and accessors, the elem / key links, the
--  value-equality contract, and the out-of-range accessor signal.

with AUnit;
with AUnit.Test_Cases;

package Reflect_Types_Suite is

   type Reflect_Types_Test is
     new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Reflect_Types_Test);
   overriding function  Name
     (T : Reflect_Types_Test) return AUnit.Message_String;

   procedure Test_Scalar_Descriptor
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Struct_Fields_And_Methods
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Composite_Elem_And_Key
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Value_Equality
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Out_Of_Range_Accessors_Raise
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Reflect_Types_Suite;
