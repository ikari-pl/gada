with Gada.Core.Slices;

package body P is

   package Slices_Of_Integer is new Gada.Core.Slices (Element_Type => Integer);

   function Mid (S : Slices_Of_Integer.Slice) return Slices_Of_Integer.Slice is
   begin
      return Slices_Of_Integer.Slice_Of (S, 1 + 1, 3 + 1);
   end Mid;

   function Tail (S : Slices_Of_Integer.Slice) return Slices_Of_Integer.Slice is
   begin
      return Slices_Of_Integer.Slice_Of (S, 1 + 1, Slices_Of_Integer.Len (S) + 1);
   end Tail;

   function Head_n (S : Slices_Of_Integer.Slice; N : Integer) return Slices_Of_Integer.Slice is
   begin
      return Slices_Of_Integer.Slice_Of (S, 1, N + 1);
   end Head_n;

   function Full (S : Slices_Of_Integer.Slice) return Slices_Of_Integer.Slice is
   begin
      return Slices_Of_Integer.Slice_Of (S, 1, Slices_Of_Integer.Len (S) + 1);
   end Full;

end P;
