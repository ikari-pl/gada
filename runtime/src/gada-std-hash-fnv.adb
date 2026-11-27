--  Gada.Std.Hash.Fnv body — see spec.

with Gada.Std.Bytes; use Gada.Std.Bytes;

package body Gada.Std.Hash.Fnv is

   function New32 return Hash32 is
      (State => Offset32, A => False);

   function New32a return Hash32 is
      (State => Offset32, A => True);

   function New64 return Hash64 is
      (State => Offset64, A => False);

   function New64a return Hash64 is
      (State => Offset64, A => True);

   procedure Write (H : in out Hash32; Data : Byte_Slice) is
   begin
      for I in 1 .. Natural (Byte_Vectors.Length (Data)) loop
         declare
            B : constant Unsigned_32 :=
              Unsigned_32 (Character'Pos (Byte_Vectors.Element (Data, I)));
         begin
            if H.A then
               H.State := (H.State xor B) * Prime32;
            else
               H.State := (H.State * Prime32) xor B;
            end if;
         end;
      end loop;
   end Write;

   procedure Write (H : in out Hash64; Data : Byte_Slice) is
   begin
      for I in 1 .. Natural (Byte_Vectors.Length (Data)) loop
         declare
            B : constant Unsigned_64 :=
              Unsigned_64 (Character'Pos (Byte_Vectors.Element (Data, I)));
         begin
            if H.A then
               H.State := (H.State xor B) * Prime64;
            else
               H.State := (H.State * Prime64) xor B;
            end if;
         end;
      end loop;
   end Write;

   function Sum32 (H : Hash32) return Unsigned_32 is (H.State);

   function Sum64 (H : Hash64) return Unsigned_64 is (H.State);

   function Sum (H : Hash32; B : Byte_Slice) return Byte_Slice is
      use Interfaces;
      R   : Byte_Slice := B;
      Tmp : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      --  Go's Sum appends big-endian: most significant byte first.
      for K in 0 .. 3 loop
         Byte_Vectors.Append
           (Tmp, Character'Val (Shift_Right (H.State, 8 * (3 - K))
                                  and 16#FF#));
      end loop;
      for I in 1 .. Natural (Byte_Vectors.Length (Tmp)) loop
         Byte_Vectors.Append (R, Byte_Vectors.Element (Tmp, I));
      end loop;
      return R;
   end Sum;

   function Sum (H : Hash64; B : Byte_Slice) return Byte_Slice is
      use Interfaces;
      R : Byte_Slice := B;
      Tmp : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      for K in 0 .. 7 loop
         Byte_Vectors.Append
           (Tmp, Character'Val (Shift_Right (H.State, 8 * (7 - K))
                                  and 16#FF#));
      end loop;
      for I in 1 .. Natural (Byte_Vectors.Length (Tmp)) loop
         Byte_Vectors.Append (R, Byte_Vectors.Element (Tmp, I));
      end loop;
      return R;
   end Sum;

   procedure Reset (H : in out Hash32) is
   begin
      H.State := Offset32;
   end Reset;

   procedure Reset (H : in out Hash64) is
   begin
      H.State := Offset64;
   end Reset;

   function Size (H : Hash32) return Natural is
      pragma Unreferenced (H);
   begin
      return 4;
   end Size;

   function Size (H : Hash64) return Natural is
      pragma Unreferenced (H);
   begin
      return 8;
   end Size;

end Gada.Std.Hash.Fnv;
