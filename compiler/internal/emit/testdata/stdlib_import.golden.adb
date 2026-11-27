with Ada.Strings.Unbounded;
with Gada.Std.Strings;

package body P is

   procedure F (S : String) is
   begin
      Gada.Std.Strings.To_Upper (S);
   end F;

end P;
