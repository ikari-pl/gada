package body P is

   function Choose (X : Integer) return Integer is
   begin
      if X < 0 then
         return -1;
      elsif X = 0 then
         return 0;
      else
         return 1;
      end if;
   end Choose;

end P;
