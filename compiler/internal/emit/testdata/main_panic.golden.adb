with Gada.Core.Panic;
with Gada.Core.Process;

procedure Main is

   package Panic_Of_Integer is new Gada.Core.Panic
     (Payload_Type => Integer,
      Default      => 0);

begin
   Panic_Of_Integer.Do_Panic (42);
exception
   when E : Panic_Of_Integer.Panicking =>
      if Panic_Of_Integer.Is_Panicking then
         Gada.Core.Process.Unhandled (E);
      end if;
   when E : others =>
      Gada.Core.Process.Unhandled (E);
end Main;
