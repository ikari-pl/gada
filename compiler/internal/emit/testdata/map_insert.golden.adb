with Gada.Core.Maps;
with Gada.Core.Hash;

package body P is

   package Maps_Of_Integer_To_Integer is new Gada.Core.Maps
     (Key_Type      => Integer,
      Value_Type    => Integer,
      Hash          => Gada.Core.Hash.Hash_Integer,
      Default_Value => 0);

   procedure F (M : Maps_Of_Integer_To_Integer.Map) is
   begin
      Maps_Of_Integer_To_Integer.Insert (M, 1, 2);
   end F;

end P;
