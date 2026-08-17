with Gada.Core.IO; use Gada.Core.IO;
with Gada.Reflect.Types;
with Gada.Reflect.Registry;

procedure Main is

   type Config is record
      Width : Integer;
      Height : Integer;
      Depth : Integer;
      Verbose : Boolean;
      Ratio : Long_Float;
   end record;

   Zero : Config := Config'(Width => 0, Height => 0, Depth => 0, Verbose => False, Ratio => 0.0);
   Partial : Config := Config'(Width => 80, Height => 0, Depth => 0, Verbose => False, Ratio => 0.0);

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Config
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Config", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "Width", Field_Type => 2);
      Gada.Reflect.Types.Add_Field (Meta, "Height", Field_Type => 2);
      Gada.Reflect.Types.Add_Field (Meta, "Depth", Field_Type => 2);
      Gada.Reflect.Types.Add_Field (Meta, "Verbose", Field_Type => 3);
      Gada.Reflect.Types.Add_Field (Meta, "Ratio", Field_Type => 4);
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
      --  bool
      Meta := Gada.Reflect.Types.Make (Id => 3, Name => "bool", Kind => Gada.Reflect.Types.Bool_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
      --  float64
      Meta := Gada.Reflect.Types.Make (Id => 4, Name => "float64", Kind => Gada.Reflect.Types.Float_Kind);
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
