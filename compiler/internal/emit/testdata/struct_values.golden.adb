with Gada.Core.IO; use Gada.Core.IO;
with Gada.Reflect.Types;
with Gada.Reflect.Registry;

procedure Main is

   type Point is record
      X : Integer;
      Y : Integer;
   end record;

   P : Point := Point'(X => 1, Y => 2);
   Q : Point := Point'(3, 4);

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
   Print (P.X);
   Print (" ");
   Print (P.Y);
   New_Line;
   Print (Q.X);
   Print (" ");
   Print (Q.Y);
   New_Line;
end Main;
