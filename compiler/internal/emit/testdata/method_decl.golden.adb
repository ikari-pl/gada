with Gada.Reflect.Types;
with Gada.Reflect.Registry;

package body P is

   type Counter is record
      N : Integer;
   end record;

   function Zero return Integer is
   begin
      return 0;
   end Zero;

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Counter
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Counter", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "N", Field_Type => 2);
      Gada.Reflect.Types.Add_Method (Meta, "Get");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
end P;
