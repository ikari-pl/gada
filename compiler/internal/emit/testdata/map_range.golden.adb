with Gada.Core.Maps;
with Gada.Core.Hash;

package body P is

   package Maps_Of_Integer_To_Integer is new Gada.Core.Maps
     (Key_Type      => Integer,
      Value_Type    => Integer,
      Hash          => Gada.Core.Hash.Hash_Integer,
      Default_Value => 0);

   function F (M : Maps_Of_Integer_To_Integer.Map) return Integer is
      Total : Integer := 0;
   begin
      declare
         Cursor_1 : Maps_Of_Integer_To_Integer.Cursor := Maps_Of_Integer_To_Integer.First (M);
      begin
         while Maps_Of_Integer_To_Integer.Has_Element (M, Cursor_1) loop
            declare
               K : constant Integer := Maps_Of_Integer_To_Integer.Key (M, Cursor_1);
               V : constant Integer := Maps_Of_Integer_To_Integer.Value (M, Cursor_1);
            begin
               Total := (Total + K) + V;
            end;
            Cursor_1 := Maps_Of_Integer_To_Integer.Next (M, Cursor_1);
         end loop;
      end;
      return Total;
   end F;

end P;
