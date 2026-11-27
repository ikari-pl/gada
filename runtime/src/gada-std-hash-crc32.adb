--  Gada.Std.Hash.Crc32 body — see spec.

with Gada.Std.Bytes; use Gada.Std.Bytes;

package body Gada.Std.Hash.Crc32 is

   function Make_Table (Poly : Unsigned_32) return Table is
      Tab : Table;
   begin
      for I in Tab'Range loop
         declare
            C : Unsigned_32 := Unsigned_32 (I);
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
     (Crc : Unsigned_32; Tab : Table; Data : Byte_Slice)
      return Unsigned_32
   is
      C : Unsigned_32 := not Crc;
   begin
      for I in 1 .. Natural (Byte_Vectors.Length (Data)) loop
         declare
            B : constant Unsigned_32 :=
              Unsigned_32 (Byte_Vectors.Element (Data, I));
         begin
            C := Tab (Natural ((C xor B) and 16#FF#)) xor Shift_Right (C, 8);
         end;
      end loop;
      return not C;
   end Update;

   function Checksum (Data : Byte_Slice; Tab : Table) return Unsigned_32 is
   begin
      return Update (0, Tab, Data);
   end Checksum;

   function Checksum_IEEE (Data : Byte_Slice) return Unsigned_32 is
      IEEE_Table : constant Table := Make_Table (IEEE);
   begin
      return Update (0, IEEE_Table, Data);
   end Checksum_IEEE;

end Gada.Std.Hash.Crc32;
