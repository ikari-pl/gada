package body P is

   function Add (A : Integer; B : Integer) return Integer is
   begin
      return A + B;
   end Add;

   function Pi return Long_Float is
   begin
      return 3.14;
   end Pi;

end P;
