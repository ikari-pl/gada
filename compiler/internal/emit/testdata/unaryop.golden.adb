package body P is

   function Flip (X : Integer; Ok : Boolean) return Integer is
   begin
      null;
      if not Ok then
         return -X;
      end if;
      return X;
   end Flip;

   function Always return Boolean is
   begin
      return True;
   end Always;

end P;
