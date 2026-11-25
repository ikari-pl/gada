with Gada.Core.IO; use Gada.Core.IO;
with Gada.Reflect.Types;
with Gada.Reflect.Registry;
with Gada.Reflect.Interfaces;
with Main_Types;
use Main_Types;

procedure Main is

   G : Gauge := Gauge'(Reading => 7);

begin
   Print (G.Reading);
   New_Line;
end Main;
