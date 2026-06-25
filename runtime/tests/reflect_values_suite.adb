--  Reflect_Values_Suite body — see spec.
--
--  The registry is process-wide, so each test registers its operand
--  types under high, otherwise-unused Type_Ids (9101+), independent of
--  registration order and of the sibling reflect suites.

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Reflect.Registry;
with Gada.Reflect.Types;  use Gada.Reflect.Types;
with Gada.Reflect.Values; use Gada.Reflect.Values;

package body Reflect_Values_Suite is

   ----------------------------------------------------------------
   --  Type_Of (Id): reflect.TypeOf
   ----------------------------------------------------------------

   procedure Test_Type_Of
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Pt : Type_Descriptor :=
        Make (Id => 9101, Name => "Point", Kind => Struct_Kind);
   begin
      Add_Field (Pt, "X", Field_Type => 1);
      Gada.Reflect.Registry.Register_Type (Pt);

      --  Type_Of hands back the registered descriptor, and the type-side
      --  field walk reaches through it (Field, Method per the done-when).
      declare
         Got : constant Type_Descriptor := Gada.Reflect.Values.Type_Of (9101);
      begin
         Assert (Got = Pt, "Type_Of (Id) returns the registered descriptor");
         Assert (Kind (Got) = Struct_Kind, "round-tripped kind");
         Assert (Num_Fields (Got) = 1 and then Field_Name (Got, 1) = "X",
                 "type-side field walk through Type_Of");
      end;

      --  Unregistered Id: Go's zero reflect.Type.
      Assert (Kind (Gada.Reflect.Values.Type_Of (765432)) = Invalid_Kind,
              "Type_Of of an unregistered Id is Invalid_Kind");
   end Test_Type_Of;

   ----------------------------------------------------------------
   --  Value_Of scalars + Kind / Type_Of (V) / To_* success
   ----------------------------------------------------------------

   procedure Test_Value_Of_Scalars
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Celsius : constant Type_Descriptor :=
        Make (Id => 9102, Name => "Celsius", Kind => Float_Kind);

      I_Val : constant Value := Value_Of (9102, Long_Long_Integer'(42));
      F_Val : constant Value := Value_Of (9102, Long_Float'(3.5));
      B_Val : constant Value := Value_Of (9102, True);
      S_Val : constant Value := Value_Of (9102, "hi");
   begin
      Gada.Reflect.Registry.Register_Type (Celsius);

      --  The Ada datum type fixes the reflect Kind.
      Assert (Kind (I_Val) = Int_Kind,    "integer datum -> Int_Kind");
      Assert (Kind (F_Val) = Float_Kind,  "float datum -> Float_Kind");
      Assert (Kind (B_Val) = Bool_Kind,   "boolean datum -> Bool_Kind");
      Assert (Kind (S_Val) = String_Kind, "string datum -> String_Kind");

      --  reflect.Value.Int / Float / Bool / String round-trip the datum.
      Assert (To_Int (I_Val) = 42,        "To_Int round-trips the datum");
      Assert (To_Float (F_Val) = 3.5,     "To_Float round-trips the datum");
      Assert (To_Bool (B_Val),            "To_Bool round-trips the datum");
      Assert (To_String (S_Val) = "hi",   "To_String round-trips the datum");

      --  reflect.Value.Type: the boxed value's descriptor, by Id.
      Assert (Name (Gada.Reflect.Values.Type_Of (F_Val)) = "Celsius",
              "Type_Of (Value) returns the operand's descriptor");
   end Test_Value_Of_Scalars;

   ----------------------------------------------------------------
   --  Value_Of (Id): composite, type-only — Kind from the registry
   ----------------------------------------------------------------

   procedure Test_Value_Of_Composite
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Buf : constant Type_Descriptor :=
        Make (Id => 9103, Name => "Buf", Kind => Slice_Kind, Elem => 1);
      V : Value;
   begin
      Gada.Reflect.Registry.Register_Type (Buf);
      V := Value_Of (9103);

      Assert (Kind (V) = Slice_Kind,
              "composite Value_Of takes its Kind from the registry");
      Assert (Id (Gada.Reflect.Values.Type_Of (V)) = 9103,
              "Type_Of (Value) identifies the composite operand");
   end Test_Value_Of_Composite;

   ----------------------------------------------------------------
   --  Value_Of (Id) of a scalar Id is a compiler-side misuse and raises
   ----------------------------------------------------------------

   procedure Test_Composite_Box_Of_Scalar_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Scalar : constant Type_Descriptor :=
        Make (Id => 9104, Name => "Count", Kind => Int_Kind);
      Raised : Boolean := False;
   begin
      Gada.Reflect.Registry.Register_Type (Scalar);

      --  The type-only box is for composites; a scalar Id would build a
      --  zero-datum scalar Value, so it must fail fast. Consume the
      --  result (Unused_ prefix) and assert *after* the block.
      declare
         Unused_Box : Value;
      begin
         Unused_Box := Value_Of (9104);
      exception
         when Constraint_Error => Raised := True;
      end;
      Assert (Raised,
              "Value_Of (Id) of a scalar-kind Id raises Constraint_Error "
              & "(scalars must use a datum-carrying overload)");
   end Test_Composite_Box_Of_Scalar_Raises;

   ----------------------------------------------------------------
   --  Kind-mismatch accessors raise Constraint_Error (Go panics)
   ----------------------------------------------------------------

   procedure Test_Scalar_Accessor_Mismatch_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      I_Val : constant Value := Value_Of (No_Type, Long_Long_Integer'(7));
      F_Val : constant Value := Value_Of (No_Type, Long_Float'(1.0));

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

      --  Each probe asks an accessor for the wrong kind. The wrong-kind
      --  call raises during the constant's elaboration; with no handler
      --  here it propagates to Expect_Constraint_Error's Probe.all.
      procedure Int_On_Float;
      procedure Int_On_Float is
         Discard : constant Long_Long_Integer := To_Int (F_Val);
         pragma Unreferenced (Discard);
      begin
         null;
      end Int_On_Float;

      procedure Float_On_Int;
      procedure Float_On_Int is
         Discard : constant Long_Float := To_Float (I_Val);
         pragma Unreferenced (Discard);
      begin
         null;
      end Float_On_Int;

      procedure Bool_On_Int;
      procedure Bool_On_Int is
         Discard : constant Boolean := To_Bool (I_Val);
         pragma Unreferenced (Discard);
      begin
         null;
      end Bool_On_Int;

      procedure String_On_Int;
      procedure String_On_Int is
         Discard : constant String := To_String (I_Val);
         pragma Unreferenced (Discard);
      begin
         null;
      end String_On_Int;
   begin
      Expect_Constraint_Error
        (Int_On_Float'Access, "To_Int of a Float value raises");
      Expect_Constraint_Error
        (Float_On_Int'Access, "To_Float of an Int value raises");
      Expect_Constraint_Error
        (Bool_On_Int'Access, "To_Bool of an Int value raises");
      Expect_Constraint_Error
        (String_On_Int'Access, "To_String of an Int value raises");
   end Test_Scalar_Accessor_Mismatch_Raises;

   ----------------------------------------------------------------
   --  Registration
   ----------------------------------------------------------------

   overriding procedure Register_Tests (T : in out Reflect_Values_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Type_Of'Access,
         "Type_Of (Id) round-trips the registered descriptor; an "
         & "unregistered Id is Invalid_Kind");
      Register_Routine
        (T, Test_Value_Of_Scalars'Access,
         "Value_Of boxes a scalar: the datum fixes the Kind, To_Int / "
         & "To_Float / To_Bool / To_String round-trip it, and Type_Of "
         & "(Value) returns the operand's descriptor");
      Register_Routine
        (T, Test_Value_Of_Composite'Access,
         "Value_Of (Id) boxes a composite type-only; its Kind comes from "
         & "the registered descriptor");
      Register_Routine
        (T, Test_Composite_Box_Of_Scalar_Raises'Access,
         "Value_Of (Id) of a scalar-kind Id raises Constraint_Error rather "
         & "than fabricating a zero-datum scalar Value");
      Register_Routine
        (T, Test_Scalar_Accessor_Mismatch_Raises'Access,
         "Each scalar accessor raises Constraint_Error when V.Kind is not "
         & "its kind (Go panics on the same mismatch)");
   end Register_Tests;

   overriding function Name
     (T : Reflect_Values_Test) return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Gada.Reflect.Values suite");
   end Name;

end Reflect_Values_Suite;
