with Gada.Reflect.Types;
with Gada.Reflect.Registry;
with Gada.Reflect.Interfaces;

package body P is
begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Stringer
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Stringer", Kind => Gada.Reflect.Types.Interface_Kind);
      Gada.Reflect.Types.Add_Method (Meta, "String");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Point
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "Point", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "X", Field_Type => 3);
      Gada.Reflect.Types.Add_Field (Meta, "Y", Field_Type => 3);
      Gada.Reflect.Types.Add_Method (Meta, "String");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 3, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
   --  Point satisfies Stringer
   Gada.Reflect.Interfaces.Register (Concrete => 2, Iface => 1);
end P;
