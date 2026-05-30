with Gada.Core.IO; use Gada.Core.IO;
with Gada.Core.Defer;

procedure Main is

   procedure Defer_Closure_1 is
   begin
      Print ("end");
      New_Line;
   end Defer_Closure_1;
   Defer_1 : Gada.Core.Defer.Defer_Block (Op => Defer_Closure_1'Unrestricted_Access);

begin
   Print ("hello");
   New_Line;
end Main;
