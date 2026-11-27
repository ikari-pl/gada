--  Gada.Std.Hash.Crc64 body — see spec.

with Gada.Std.Bytes; use Gada.Std.Bytes;

package body Gada.Std.Hash.Crc64 is

   function Make_Table (Poly : Unsigned_64) return Table is
      Tab : Table;
   begin
      for I in Tab'Range loop
         declare
            C : Unsigned_64 := Unsigned_64 (I);
         begin
            for K in 1 .. 8 loop
               if (C and 1) /= 0 then
                  C := Shift_Right (C, 1) xor Poly;
               else
                  C := Shift_Right (C, 1);
               end if;
            end loop;
            Tab (I) := C;
         end;
      end loop;
      return Tab;
   end Make_Table;

   function Update
     (Crc : Unsigned_64; Tab : Table; Data : Byte_Slice)
      return Unsigned_64
   is
      C : Unsigned_64 := not Crc;
   begin
      for I in 1 .. Natural (Byte_Vectors.Length (Data)) loop
         declare
            B : constant Unsigned_64 :=
              Unsigned_64 (Byte_Vectors.Element (Data, I));
         begin
            C := Tab (Natural ((C xor B) and 16#FF#)) xor Shift_Right (C, 8);
         end;
      end loop;
      return not C;
   end Update;

   function Checksum (Data : Byte_Slice; Tab : Table) return Unsigned_64 is
   begin
      return Update (0, Tab, Data);
   end Checksum;

end Gada.Std.Hash.Crc64;
