--  Reflect_Types_Suite body — see spec for the property list.

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Reflect.Types; use Gada.Reflect.Types;

package body Reflect_Types_Suite is

   ---------------------------------------------------------------
   --  Tests
   ---------------------------------------------------------------

   procedure Test_Scalar_Descriptor
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Int_T : constant Type_Descriptor := Make (Id => 1, Name => "int",
                                                Kind => Int_Kind);
   begin
      Assert (Id (Int_T) = 1, "Id should round-trip");
      Assert (Name (Int_T) = "int", "Name should round-trip");
      Assert (Kind (Int_T) = Int_Kind, "Kind should round-trip");
      Assert (Elem (Int_T) = No_Type, "scalar has no element type");
      Assert (Key (Int_T) = No_Type, "scalar has no key type");
      Assert (Num_Fields (Int_T) = 0, "scalar has no fields");
      Assert (Num_Methods (Int_T) = 0, "scalar has no methods");
   end Test_Scalar_Descriptor;

   procedure Test_Struct_Fields_And_Methods
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  type Point struct { X, Y int } with method Norm.
      Pt : Type_Descriptor := Make (Id => 7, Name => "Point",
                                    Kind => Struct_Kind);
   begin
      Add_Field (Pt, "X", Field_Type => 1);  --  int
      Add_Field (Pt, "Y", Field_Type => 1);
      Add_Method (Pt, "Norm");

      Assert (Num_Fields (Pt) = 2, "Point should have two fields");
      Assert (Field_Name (Pt, 1) = "X", "first field is X");
      Assert (Field_Name (Pt, 2) = "Y", "second field is Y");
      Assert (Field_Type (Pt, 1) = 1 and Field_Type (Pt, 2) = 1,
              "both fields are of type int (Id 1)");

      Assert (Num_Methods (Pt) = 1, "Point should have one method");
      Assert (Method_Name (Pt, 1) = "Norm", "method is Norm");
      Assert (Kind (Pt) = Struct_Kind, "Point is a struct");
   end Test_Struct_Fields_And_Methods;

   procedure Test_Composite_Elem_And_Key
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  []int : element type int (Id 1).
      Slice_T : constant Type_Descriptor :=
        Make (Id => 10, Name => "[]int", Kind => Slice_Kind, Elem => 1);
      --  map[string]int : key string (Id 2), value int (Id 1).
      Map_T : constant Type_Descriptor :=
        Make (Id => 11, Name => "map[string]int", Kind => Map_Kind,
              Elem => 1, Key => 2);
   begin
      Assert (Kind (Slice_T) = Slice_Kind, "slice kind");
      Assert (Elem (Slice_T) = 1, "slice element type is int");
      Assert (Key (Slice_T) = No_Type, "slice has no key type");

      Assert (Kind (Map_T) = Map_Kind, "map kind");
      Assert (Elem (Map_T) = 1, "map value type is int");
      Assert (Key (Map_T) = 2, "map key type is string");
   end Test_Composite_Elem_And_Key;

   procedure Test_Value_Equality
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      function Built_Point (Method : String) return Type_Descriptor;
      function Built_Point (Method : String) return Type_Descriptor is
         P : Type_Descriptor := Make (Id => 7, Name => "Point",
                                      Kind => Struct_Kind);
      begin
         Add_Field (P, "X", Field_Type => 1);
         Add_Field (P, "Y", Field_Type => 1);
         Add_Method (P, Method);
         return P;
      end Built_Point;

      A : constant Type_Descriptor := Built_Point ("Norm");
      B : constant Type_Descriptor := Built_Point ("Norm");
      C : constant Type_Descriptor := Built_Point ("Length");
      Scalar : constant Type_Descriptor :=
        Make (Id => 1, Name => "int", Kind => Int_Kind);
   begin
      --  Deep value equality: same name/kind/fields/methods => equal,
      --  even though A and B are independently built values.
      Assert (A = B, "structurally identical descriptors compare equal");
      Assert (A /= C, "a differing method list breaks equality");
      Assert (A /= Scalar, "different kind/name breaks equality");
   end Test_Value_Equality;

   procedure Test_Out_Of_Range_Accessors_Raise
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Pt : Type_Descriptor := Make (Id => 7, Name => "Point",
                                    Kind => Struct_Kind);

      procedure Expect_Constraint_Error
        (Probe : not null access procedure; Label : String);
      procedure Expect_Constraint_Error
        (Probe : not null access procedure; Label : String)
      is
         Raised : Boolean := False;
      begin
         --  Assert *after* the inner block, not inside the handler: a
         --  Probe that fails to raise would otherwise skip the handler
         --  and exit with no assertion — a silent false pass.
         begin
            Probe.all;
         exception
            when Constraint_Error =>
               Raised := True;
         end;
         Assert (Raised, Label);
      end Expect_Constraint_Error;

      procedure Bad_Field_Name;
      procedure Bad_Field_Name is
         Discard : constant String := Field_Name (Pt, 1);
         pragma Unreferenced (Discard);
      begin
         null;
      end Bad_Field_Name;

      procedure Bad_Field_Type;
      procedure Bad_Field_Type is
         Discard : constant Type_Id := Field_Type (Pt, 5);
         pragma Unreferenced (Discard);
      begin
         null;
      end Bad_Field_Type;

      procedure Bad_Method_Name;
      procedure Bad_Method_Name is
         Discard : constant String := Method_Name (Pt, 1);
         pragma Unreferenced (Discard);
      begin
         null;
      end Bad_Method_Name;
   begin
      --  Pt has zero fields and zero methods, so every indexed access
      --  is out of range and must raise Constraint_Error (Go's
      --  reflect.Type.Field panics on the same out-of-range index).
      Add_Field (Pt, "X", Field_Type => 1);  --  one field, index 5 still bad
      Expect_Constraint_Error
        (Bad_Field_Type'Access, "Field_Type past the end raises");
      --  Drop back to a fresh empty descriptor for the name probes.
      Pt := Make (Id => 7, Name => "Point", Kind => Struct_Kind);
      Expect_Constraint_Error
        (Bad_Field_Name'Access, "Field_Name on an empty struct raises");
      Expect_Constraint_Error
        (Bad_Method_Name'Access, "Method_Name on an empty struct raises");
   end Test_Out_Of_Range_Accessors_Raise;

   ---------------------------------------------------------------
   --  Registration
   ---------------------------------------------------------------

   overriding procedure Register_Tests (T : in out Reflect_Types_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Scalar_Descriptor'Access,
         "A scalar descriptor round-trips Id / Name / Kind and has no "
         & "fields, methods, elem, or key");
      Register_Routine
        (T, Test_Struct_Fields_And_Methods'Access,
         "Add_Field / Add_Method append in source order; the accessors "
         & "read them back by 1-based index");
      Register_Routine
        (T, Test_Composite_Elem_And_Key'Access,
         "Slice carries an element type; Map carries both element "
         & "(value) and key types");
      Register_Routine
        (T, Test_Value_Equality'Access,
         "Type_Descriptor '=' is deep value equality across name, kind, "
         & "fields, and methods");
      Register_Routine
        (T, Test_Out_Of_Range_Accessors_Raise'Access,
         "Indexed accessors raise Constraint_Error past the end (Go's "
         & "reflect panics on the same out-of-range index)");
   end Register_Tests;

   overriding function Name
     (T : Reflect_Types_Test) return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Gada.Reflect.Types suite");
   end Name;

end Reflect_Types_Suite;
