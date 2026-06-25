--  Gada.Reflect.Types — the type-metadata schema (Phase 4 item 1).
--
--  A `Type_Descriptor` is GADA's runtime mirror of one Go type, in the
--  shape Go's `reflect.Type` exposes: a name, a Kind, an ordered list of
--  struct fields, an ordered list of method names, and — for the
--  composite kinds — element / key links to other types. The compiler
--  emits one descriptor per defined Go type (a later Phase 4 item) and
--  the TypeOf / ValueOf entry points hand them back to user code.
--
--  ## Identity vs. equality
--
--  Each descriptor carries a `Type_Id` — a small integer the compiler
--  assigns once per defined type, the unit of *type identity* (Go's
--  `t1 == t2` on reflect.Types). Fields, element, and key reference
--  other types *by Id* rather than embedding descriptors, so the schema
--  is a flat, cycle-safe table (a struct may contain a pointer to
--  itself).
--
--  The predefined `"="` on Type_Descriptor is the Ada-level *value*
--  equality: deep across name, kind, fields, methods, and the elem/key
--  links (Unbounded_String compares by content, the field/method
--  vectors element-wise). That is what the Phase 4 done-when asks for;
--  identity comparison is just `Id (A) = Id (B)`.
--
--  Dependency-light by design: only Ada.Strings.Unbounded and
--  Ada.Containers.Vectors, no GADA runtime layers.

with Ada.Strings.Unbounded;
private with Ada.Containers.Vectors;

package Gada.Reflect.Types is

   --  Make / Add_Field are called from client module-init elaboration
   --  (the compiler builds each descriptor there); force this body to
   --  elaborate right after its spec so those calls can never precede it.
   pragma Elaborate_Body;

   --  Mirrors Go's reflect.Kind for the type set GADA supports. The
   --  literals are suffixed `_Kind` to dodge Ada reserved words
   --  (`interface`) and predefined type names (`String`, `Float`).
   --  Invalid_Kind is the zero value — an unset or unknown type,
   --  matching Go's reflect.Invalid.
   type Type_Kind is
     (Invalid_Kind,
      Bool_Kind,
      Int_Kind,
      Float_Kind,
      String_Kind,
      Slice_Kind,
      Map_Kind,
      Chan_Kind,
      Struct_Kind,
      Interface_Kind,
      Pointer_Kind,
      Func_Kind);

   --  Per-program-unique identity assigned by the compiler. Zero is the
   --  "no type" sentinel (a scalar's elem/key, a non-composite's links).
   type Type_Id is new Natural;
   No_Type : constant Type_Id := 0;

   type Type_Descriptor is private;

   ---------------------------------------------------------------
   --  Construction
   ---------------------------------------------------------------

   --  Build a descriptor with no fields or methods yet. Elem is the
   --  element type of a Slice / Pointer / Chan or the *value* type of a
   --  Map; Key is the key type of a Map. Both default to No_Type for the
   --  scalar and struct kinds. Add_Field / Add_Method append to the
   --  (initially empty) field and method lists in source order.
   function Make
     (Id   : Type_Id;
      Name : String;
      Kind : Type_Kind;
      Elem : Type_Id := No_Type;
      Key  : Type_Id := No_Type) return Type_Descriptor;

   procedure Add_Field
     (T          : in out Type_Descriptor;
      Name       : String;
      Field_Type : Type_Id);

   procedure Add_Method (T : in out Type_Descriptor; Name : String);

   ---------------------------------------------------------------
   --  Inspection
   ---------------------------------------------------------------

   function Id   (T : Type_Descriptor) return Type_Id;
   function Name (T : Type_Descriptor) return String;
   function Kind (T : Type_Descriptor) return Type_Kind;
   function Elem (T : Type_Descriptor) return Type_Id;
   function Key  (T : Type_Descriptor) return Type_Id;

   function Num_Fields (T : Type_Descriptor) return Natural;

   --  Field_Name / Field_Type select the Index'th struct field in
   --  source order (1-based). Index outside 1 .. Num_Fields raises
   --  Constraint_Error — the same "out of range" signal Go's
   --  reflect.Type.Field gives via panic.
   function Field_Name
     (T : Type_Descriptor; Index : Positive) return String;
   function Field_Type
     (T : Type_Descriptor; Index : Positive) return Type_Id;

   function Num_Methods (T : Type_Descriptor) return Natural;

   --  Method_Name selects the Index'th method in source order (1-based);
   --  out-of-range raises Constraint_Error.
   function Method_Name
     (T : Type_Descriptor; Index : Positive) return String;

private

   use Ada.Strings.Unbounded;

   type Field_Descriptor is record
      Name       : Unbounded_String;
      Field_Type : Type_Id := No_Type;
   end record;

   type Method_Descriptor is record
      Name : Unbounded_String;
   end record;

   package Field_Vectors is new
     Ada.Containers.Vectors (Positive, Field_Descriptor);
   package Method_Vectors is new
     Ada.Containers.Vectors (Positive, Method_Descriptor);

   type Type_Descriptor is record
      Id      : Type_Id := No_Type;
      Name    : Unbounded_String;
      Kind    : Type_Kind := Invalid_Kind;
      Elem    : Type_Id := No_Type;
      Key     : Type_Id := No_Type;
      Fields  : Field_Vectors.Vector;
      Methods : Method_Vectors.Vector;
   end record;

end Gada.Reflect.Types;
