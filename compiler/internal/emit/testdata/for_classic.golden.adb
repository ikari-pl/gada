package body P is

   procedure Count (N : Integer) is
   begin
      for I in 0 .. N - 1 loop
         null;
      end loop;
   end Count;

end P;
