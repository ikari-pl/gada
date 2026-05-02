with Gada.Core.Slices;

package body P is

   package Slices_Of_Integer is new Gada.Core.Slices (Element_Type => Integer);

   function Size (S : Slices_Of_Integer.Slice) return Integer is
   begin
      return Slices_Of_Integer.Len (S);
   end Size;

   function Room (S : Slices_Of_Integer.Slice) return Integer is
   begin
      return Slices_Of_Integer.Cap (S);
   end Room;

end P;
