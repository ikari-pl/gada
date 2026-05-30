with Gada.Core.IO; use Gada.Core.IO;

procedure Main is

   function Demo (N : Integer) return Integer is
      X : Integer := 0;
   begin
      for I in 0 .. N - 1 loop
         X := X + (I * 2);
      end loop;
      if X > 100 then
         Print ("big");
         New_Line;
         return -X;
      elsif X < -10 then
         Print ("small");
         New_Line;
         return X;
      end if;
      Print ("ok");
      New_Line;
      return X;
   end Demo;

begin
   null;
end Main;
