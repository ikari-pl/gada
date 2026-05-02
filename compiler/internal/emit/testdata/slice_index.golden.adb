with Gada.Core.Slices;

package body P is

   package Slices_Of_Integer is new Gada.Core.Slices (Element_Type => Integer);

   function First (S : Slices_Of_Integer.Slice) return Integer is
   begin
      return Slices_Of_Integer.Element (S, 0 + 1);
   end First;

   function At_K (S : Slices_Of_Integer.Slice; I : Integer) return Integer is
   begin
      return Slices_Of_Integer.Element (S, I + 1);
   end At_K;

end P;
