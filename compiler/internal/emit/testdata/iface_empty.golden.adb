with Gada.Reflect.Types;
with Gada.Reflect.Registry;
with Gada.Reflect.Interfaces;

package body P is

   type Any is interface;

   type Blank is record
      N : Integer;
   end record;

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Any
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Any", Kind => Gada.Reflect.Types.Interface_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Blank
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "Blank", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "N", Field_Type => 3);
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 3, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
   --  Blank satisfies Any
   Gada.Reflect.Interfaces.Register (Concrete => 2, Iface => 1);
end P;
