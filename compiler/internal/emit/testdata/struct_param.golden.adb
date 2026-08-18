with Gada.Reflect.Types;
with Gada.Reflect.Registry;

package body P is

   type Point is record
      X : Integer;
      Y : Integer;
   end record;

   function Area (P : Point) return Integer is
   begin
      return P.X;
   end Area;

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Point
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Point", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "X", Field_Type => 2);
      Gada.Reflect.Types.Add_Field (Meta, "Y", Field_Type => 2);
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
end P;
