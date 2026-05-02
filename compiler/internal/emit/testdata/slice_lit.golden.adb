with Gada.Core.Slices;

package body P is

   package Slices_Of_Integer is new Gada.Core.Slices (Element_Type => Integer);

   function Three return Slices_Of_Integer.Slice is
   begin
      return Slices_Of_Integer.From_Array ([1, 2, 3]);
   end Three;

end P;
