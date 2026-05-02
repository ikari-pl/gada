with Gada.Core.Panic;

procedure Main is

   package Panic_Of_Integer is new Gada.Core.Panic
     (Payload_Type => Integer,
      Default      => 0);

begin
   Panic_Of_Integer.Do_Panic (42);
exception
   when Panic_Of_Integer.Panicking =>
      if Panic_Of_Integer.Is_Panicking then
         raise;
      end if;
end Main;
