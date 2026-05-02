with Gada.Core.Maps;
with Gada.Core.Hash;

package body P is

   package Maps_Of_Integer_To_Integer is new Gada.Core.Maps
     (Key_Type      => Integer,
      Value_Type    => Integer,
      Hash          => Gada.Core.Hash.Hash_Integer,
      Default_Value => 0);

   function F return Integer is
      M : Maps_Of_Integer_To_Integer.Map := Maps_Of_Integer_To_Integer.From_Pairs ([(K => 1, V => 2), (K => 3, V => 4)]);
      E : Maps_Of_Integer_To_Integer.Map := Maps_Of_Integer_To_Integer.Make_Map;
   begin
      return Maps_Of_Integer_To_Integer.Length (M) + Maps_Of_Integer_To_Integer.Length (E);
   end F;

end P;
