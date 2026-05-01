package body P is

   function Compute (A : Integer; B : Integer) return Integer is
   begin
      return (A + B) - ((A * B) / 2);
   end Compute;

end P;
