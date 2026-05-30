with Gada.Core.IO; use Gada.Core.IO;
with Gada.Core.Defer;
with Gada.Core.Panic;

procedure Main is

   package Panic_Of_Integer is new Gada.Core.Panic
     (Payload_Type => Integer,
      Default      => 0);

   procedure Rescue is
   begin
      if Panic_Of_Integer.Recover /= 0 then
         Print ("rescued");
         New_Line;
      end if;
   exception
      when Panic_Of_Integer.Panicking =>
         if Panic_Of_Integer.Is_Panicking then
            raise;
         end if;
   end Rescue;

begin
   declare
      procedure Defer_Closure_1 is
      begin
         Rescue;
      end Defer_Closure_1;
      Defer_1 : Gada.Core.Defer.Defer_Block (Op => Defer_Closure_1'Unrestricted_Access);
   begin
      Panic_Of_Integer.Do_Panic (42);
   end;
exception
   when Panic_Of_Integer.Panicking =>
      if Panic_Of_Integer.Is_Panicking then
         raise;
      end if;
end Main;
