with Gada.Core.IO; use Gada.Core.IO;
with Gada.Reflect.Types;
with Gada.Reflect.Registry;
with Gada.Reflect.Interfaces;

procedure Main is

   type Meter is interface;
   function Value (Self : Meter) return Integer is abstract;

   type Gauge is new Meter with record
      Reading : Integer;
   end record;
   overriding function Value (G : Gauge) return Integer;

   overriding function Value (G : Gauge) return Integer is
   begin
      return G.Reading;
   end Value;

   G : Gauge := Gauge'(Reading => 7);

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Meter
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Meter", Kind => Gada.Reflect.Types.Interface_Kind);
      Gada.Reflect.Types.Add_Method (Meta, "Value");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Gauge
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "Gauge", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "Reading", Field_Type => 3);
      Gada.Reflect.Types.Add_Method (Meta, "Value");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 3, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
   --  Gauge satisfies Meter
   Gada.Reflect.Interfaces.Register (Concrete => 2, Iface => 1);
   Print (G.Reading);
   New_Line;
end Main;
