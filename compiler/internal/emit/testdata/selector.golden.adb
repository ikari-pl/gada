with Gada.Core.IO; use Gada.Core.IO;

procedure Main is

   procedure Say is
   begin
      Print ("hi");
      New_Line;
   end Say;

   function Greet (Prefix : String) return String is
   begin
      return Prefix;
   end Greet;

begin
   null;
end Main;
