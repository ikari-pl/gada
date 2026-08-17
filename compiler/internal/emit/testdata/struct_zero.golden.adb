with Gada.Core.IO; use Gada.Core.IO;
with Gada.Reflect.Types;
with Gada.Reflect.Registry;

procedure Main is

   type Config is record
      Width : Integer;
      Height : Integer;
      Depth : Integer;
   end record;

   Zero : Config := Config'(Width => 0, Height => 0, Depth => 0);
   Partial : Config := Config'(Width => 80, Height => 0, Depth => 0);

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Config
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Config", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "Width", Field_Type => 2);
      Gada.Reflect.Types.Add_Field (Meta, "Height", Field_Type => 2);
      Gada.Reflect.Types.Add_Field (Meta, "Depth", Field_Type => 2);
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
   Print (Zero.Width);
   Print (" ");
   Print (Zero.Height);
   Print (" ");
   Print (Zero.Depth);
   New_Line;
   Print (Partial.Width);
   Print (" ");
   Print (Partial.Height);
   Print (" ");
   Print (Partial.Depth);
   New_Line;
end Main;
