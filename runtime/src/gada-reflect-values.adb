--  Body of Gada.Reflect.Values — see the spec for the contract.
--
--  Type_Of and the composite Value_Of read the registry; the scalar
--  Value_Of overloads are pure constructors. The scalar accessors are
--  expression functions whose mismatch branch is a raise-expression
--  (Ada 2012+), so the "wrong kind" path is one self-documenting line
--  rather than an if/raise statement.

with Gada.Reflect.Registry;

package body Gada.Reflect.Values is

   ----------------------------------------------------------------
   --  reflect.TypeOf
   ----------------------------------------------------------------

   function Type_Of (Id : Type_Id) return Type_Descriptor is
     (Gada.Reflect.Registry.Lookup (Id));

   ----------------------------------------------------------------
   --  reflect.ValueOf — constructors
   ----------------------------------------------------------------

   function Value_Of (Id : Type_Id; Datum : Long_Long_Integer) return Value is
     (T => Id, V_Kind => Int_Kind, Int_Val => Datum, others => <>);

   function Value_Of (Id : Type_Id; Datum : Long_Float) return Value is
     (T => Id, V_Kind => Float_Kind, Flt_Val => Datum, others => <>);

   function Value_Of (Id : Type_Id; Datum : Boolean) return Value is
     (T => Id, V_Kind => Bool_Kind, Bool_Val => Datum, others => <>);

   function Value_Of (Id : Type_Id; Datum : String) return Value is
     (T      => Id,
      V_Kind => String_Kind,
      Str_Val => To_Unbounded_String (Datum),
      others  => <>);

   --  Composite: the Kind is whatever the registry holds for Id (Slice /
   --  Map / Struct / …), or Invalid_Kind for an unregistered Id.
   function Value_Of (Id : Type_Id) return Value is
     (T      => Id,
      V_Kind => Gada.Reflect.Types.Kind (Gada.Reflect.Registry.Lookup (Id)),
      others => <>);

   ----------------------------------------------------------------
   --  reflect.Value — accessors
   ----------------------------------------------------------------

   function Kind (V : Value) return Type_Kind is (V.V_Kind);

   function Type_Of (V : Value) return Type_Descriptor is
     (Gada.Reflect.Registry.Lookup (V.T));

   function To_Int (V : Value) return Long_Long_Integer is
     (if V.V_Kind = Int_Kind then V.Int_Val
      else raise Constraint_Error
             with "reflect.Value.Int of " & V.V_Kind'Image);

   function To_Float (V : Value) return Long_Float is
     (if V.V_Kind = Float_Kind then V.Flt_Val
      else raise Constraint_Error
             with "reflect.Value.Float of " & V.V_Kind'Image);

   function To_Bool (V : Value) return Boolean is
     (if V.V_Kind = Bool_Kind then V.Bool_Val
      else raise Constraint_Error
             with "reflect.Value.Bool of " & V.V_Kind'Image);

   function To_String (V : Value) return String is
     (if V.V_Kind = String_Kind
      then Ada.Strings.Unbounded.To_String (V.Str_Val)
      else raise Constraint_Error
             with "reflect.Value.String of " & V.V_Kind'Image);

end Gada.Reflect.Values;
