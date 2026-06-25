--  Gada.Reflect.Values — the reflect.TypeOf / reflect.ValueOf entry
--  points (Phase 4 item 3).
--
--  Go's `reflect` package has two doors into the metadata the compiler
--  registered (item 2): `reflect.TypeOf(x)` hands back the *type*, and
--  `reflect.ValueOf(x)` boxes the *value*. This package is GADA's port
--  of both, sitting on `Gada.Reflect.Types` (the schema) and
--  `Gada.Reflect.Registry` (the store).
--
--  It is a sibling child of those two, *not* the `Gada.Reflect` parent:
--  an Ada parent spec may not `with` its own child, and these entry
--  points name both Types and Registry — the same constraint that put
--  the registry in `Gada.Reflect.Registry`.
--
--  ## Type_Of
--
--  `Type_Of (Id)` is `reflect.TypeOf(x)`: the descriptor registered
--  under the operand's compiler-assigned Type_Id, via the registry. An
--  unregistered Id yields an Invalid_Kind descriptor — Go's zero
--  `reflect.Type`. The compiler supplies the static Type_Id of the
--  operand at the call site.
--
--  ## Value and Value_Of
--
--  `Value` is a flat, SPARK-friendly record — the operand's Type_Id plus,
--  for the scalar kinds, the datum (Int / Float / Bool / String). It is
--  deliberately *not* a boxed `Any`: no universal value box exists in the
--  runtime, and one would drag in the tagged / unsafe machinery the
--  verifiable subset rejects. A flat record (no discriminant, no pointer)
--  is the most verification-friendly shape that still answers
--  `Kind` / `To_Int` / `To_Float` / `To_Bool` / `To_String`.
--
--  `Value_Of` is overloaded per scalar so the compiler selects by the
--  static operand type; the no-datum `Value_Of (Id)` covers the composite
--  kinds (its Kind comes from the registered descriptor). The scalar
--  accessors raise `Constraint_Error` on a kind mismatch, mirroring Go's
--  panic on `Value.Int()` of a non-int.
--
--  Value-side composite *data* walking (a struct field's value, slice
--  indexing) is post-1.0 per AGENTS.md non-goals; the *type*-side walk
--  (`Num_Fields` / `Field_Name` / `Field_Type` / `Num_Methods` /
--  `Method_Name`) already ships on `Type_Descriptor`, reached here through
--  `Type_Of`.

with Ada.Strings.Unbounded;
with Gada.Reflect.Types;

package Gada.Reflect.Values is

   --  Local visibility of the schema names (Type_Id, Type_Kind,
   --  Type_Descriptor) so the profiles below read cleanly. A use clause
   --  does not leak to clients, so a caller that `with`s both this
   --  package and Gada.Reflect.Types sees each schema name exactly once
   --  (no re-export, no "multiple use clauses cause hiding").
   use Gada.Reflect.Types;

   ---------------------------------------------------------------
   --  reflect.TypeOf
   ---------------------------------------------------------------

   --  The descriptor registered under Id, or an Invalid_Kind descriptor
   --  (Go's zero reflect.Type) when Id is unregistered.
   function Type_Of (Id : Type_Id) return Type_Descriptor;

   ---------------------------------------------------------------
   --  reflect.ValueOf
   ---------------------------------------------------------------

   type Value is private;

   --  Box a scalar operand: the Type_Id its compiler assigned plus the
   --  datum. The Ada datum type fixes the reflect Kind (an integer is
   --  Int_Kind, a float Float_Kind, …), exactly as Go's reflect.Kind is
   --  the underlying kind regardless of the named type.
   function Value_Of (Id : Type_Id; Datum : Long_Long_Integer) return Value;
   function Value_Of (Id : Type_Id; Datum : Long_Float)        return Value;
   function Value_Of (Id : Type_Id; Datum : Boolean)           return Value;
   function Value_Of (Id : Type_Id; Datum : String)            return Value;

   --  Box a composite operand (slice / map / struct / …): type-only, the
   --  Kind taken from the registered descriptor. A scalar Id here would
   --  be a compiler-side misuse; the scalar overloads carry the datum.
   function Value_Of (Id : Type_Id) return Value;

   --  reflect.Value.Kind — the boxed value's kind.
   function Kind (V : Value) return Type_Kind;

   --  reflect.Value.Type — the boxed value's descriptor (via the
   --  registry), so the caller can walk fields / methods type-side.
   function Type_Of (V : Value) return Type_Descriptor;

   --  reflect.Value.Int / Float / Bool / String. Each raises
   --  Constraint_Error when V.Kind is not the matching scalar kind —
   --  Go panics on the same mismatch.
   function To_Int    (V : Value) return Long_Long_Integer;
   function To_Float  (V : Value) return Long_Float;
   function To_Bool   (V : Value) return Boolean;
   function To_String (V : Value) return String;

private

   use Ada.Strings.Unbounded;

   --  Flat by design (see the package comment): every Value carries all
   --  scalar slots, only one of which is meaningful per V_Kind. No
   --  discriminant, no access type — the shape the verifiable subset
   --  likes and the cheapest thing to keep at 100% coverage.
   type Value is record
      T        : Type_Id   := Gada.Reflect.Types.No_Type;
      V_Kind   : Type_Kind := Gada.Reflect.Types.Invalid_Kind;
      Int_Val  : Long_Long_Integer := 0;
      Flt_Val  : Long_Float        := 0.0;
      Bool_Val : Boolean           := False;
      Str_Val  : Unbounded_String  := Null_Unbounded_String;
   end record;

end Gada.Reflect.Values;
