--  Gada.Reflect.Types body — see spec for the schema design.
--
--  The descriptor is a plain value: Make stamps the scalar attributes
--  and leaves the field / method vectors empty, Add_Field / Add_Method
--  append in source order, and the inspection functions are thin reads.
--  No heap ownership beyond what Unbounded_String and the vectors manage
--  themselves, so descriptors copy and compare by value.

package body Gada.Reflect.Types is

   function Make
     (Id   : Type_Id;
      Name : String;
      Kind : Type_Kind;
      Elem : Type_Id := No_Type;
      Key  : Type_Id := No_Type) return Type_Descriptor
   is
   begin
      return
        (Id      => Id,
         Name    => To_Unbounded_String (Name),
         Kind    => Kind,
         Elem    => Elem,
         Key     => Key,
         Fields  => Field_Vectors.Empty_Vector,
         Methods => Method_Vectors.Empty_Vector);
   end Make;

   procedure Add_Field
     (T          : in out Type_Descriptor;
      Name       : String;
      Field_Type : Type_Id) is
   begin
      T.Fields.Append
        (Field_Descriptor'
           (Name => To_Unbounded_String (Name), Field_Type => Field_Type));
   end Add_Field;

   procedure Add_Method (T : in out Type_Descriptor; Name : String) is
   begin
      T.Methods.Append
        (Method_Descriptor'(Name => To_Unbounded_String (Name)));
   end Add_Method;

   function Id   (T : Type_Descriptor) return Type_Id is (T.Id);
   function Name (T : Type_Descriptor) return String is
     (To_String (T.Name));
   function Kind (T : Type_Descriptor) return Type_Kind is (T.Kind);
   function Elem (T : Type_Descriptor) return Type_Id is (T.Elem);
   function Key  (T : Type_Descriptor) return Type_Id is (T.Key);

   function Num_Fields (T : Type_Descriptor) return Natural is
     (Natural (T.Fields.Length));

   function Field_Name
     (T : Type_Descriptor; Index : Positive) return String is
     (To_String (T.Fields.Element (Index).Name));

   function Field_Type
     (T : Type_Descriptor; Index : Positive) return Type_Id is
     (T.Fields.Element (Index).Field_Type);

   function Num_Methods (T : Type_Descriptor) return Natural is
     (Natural (T.Methods.Length));

   function Method_Name
     (T : Type_Descriptor; Index : Positive) return String is
     (To_String (T.Methods.Element (Index).Name));

end Gada.Reflect.Types;
