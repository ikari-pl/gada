with Gada.Core.Slices;

package body P is

   package Slices_Of_Integer is new Gada.Core.Slices (Element_Type => Integer);

   function Push (S : Slices_Of_Integer.Slice; X : Integer) return Slices_Of_Integer.Slice is
   begin
      return Slices_Of_Integer.Append (S, X);
   end Push;

end P;
