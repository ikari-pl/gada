with Gada.Reflect.Types;
with Gada.Reflect.Registry;

procedure Main is

   type Point is record
      X : Integer;
      Y : Integer;
   end record;
   type Empty is null record;

   procedure Describe is
   begin
      null;
   end Describe;

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Point
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Point", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "X", Field_Type => 3);
      Gada.Reflect.Types.Add_Field (Meta, "Y", Field_Type => 3);
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Empty
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "Empty", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 3, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
   Describe;
end Main;
