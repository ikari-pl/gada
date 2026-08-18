with Gada.Reflect.Types;
with Gada.Reflect.Registry;

package body P is

   type Stringer is interface;
   function String (Self : Stringer) return String is abstract;
   type Shape is interface;
   function Area (Self : Shape) return Integer is abstract;
   procedure Scale (Self : Shape; Factor : Integer) is abstract;
   function SetName (Self : Shape; Name : String) return Boolean is abstract;
   type Any is interface;

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Stringer
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Stringer", Kind => Gada.Reflect.Types.Interface_Kind);
      Gada.Reflect.Types.Add_Method (Meta, "String");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Shape
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "Shape", Kind => Gada.Reflect.Types.Interface_Kind);
      Gada.Reflect.Types.Add_Method (Meta, "Area");
      Gada.Reflect.Types.Add_Method (Meta, "Scale");
      Gada.Reflect.Types.Add_Method (Meta, "SetName");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Any
      Meta := Gada.Reflect.Types.Make (Id => 3, Name => "Any", Kind => Gada.Reflect.Types.Interface_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
end P;
