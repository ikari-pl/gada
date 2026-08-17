with Gada.Core.IO; use Gada.Core.IO;
with Gada.Reflect.Types;
with Gada.Reflect.Registry;

procedure Main is

   type Point is record
      X : Integer;
      Y : Integer;
   end record;
   type Tick is record
      N : Integer;
   end record;

   P : Point := Point'(X => 1, Y => 2);
   Q : Point := Point'(3, 4);
   T : Tick := Tick'(N => 7);

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Point
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Point", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "X", Field_Type => 3);
      Gada.Reflect.Types.Add_Field (Meta, "Y", Field_Type => 3);
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Tick
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "Tick", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "N", Field_Type => 3);
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 3, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
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
   Print (T.N);
   New_Line;
end Main;
