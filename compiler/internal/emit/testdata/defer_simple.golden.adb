with Gada.Core.Defer;

package body P is

   procedure F is
      procedure Defer_Closure_1 is
      begin
         Cleanup;
      end Defer_Closure_1;
      Defer_1 : Gada.Core.Defer.Defer_Block (Op => Defer_Closure_1'Access);
   begin
      null;
   end F;

end P;
