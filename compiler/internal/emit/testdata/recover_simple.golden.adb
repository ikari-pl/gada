with Gada.Core.Panic;

package body P is

   package Panic_Of_Integer is new Gada.Core.Panic
     (Payload_Type => Integer,
      Default      => 0);

   function F return Integer is
   begin
      begin
         return Panic_Of_Integer.Recover;
      exception
         when Panic_Of_Integer.Panicking =>
            if Panic_Of_Integer.Is_Panicking then
               raise;
            end if;
            return 0;
      end;
   end F;

end P;
