--  Gada.Std.Crypto.Md5 body — see spec. RFC 1321 MD5: little-endian
--  word load, the four round functions with the per-round sine-table
--  constants K and shift amounts S, little-endian digest output.

with Gada.Std.Bytes; use Gada.Std.Bytes;

package body Gada.Std.Crypto.Md5 is

   use Interfaces;

   --  K(I) = floor(2**32 * abs(sin(I + 1))), the RFC 1321 table.
   K : constant array (Natural range 0 .. 63) of Unsigned_32 :=
     (16#D76AA478#, 16#E8C7B756#, 16#242070DB#, 16#C1BDCEEE#,
      16#F57C0FAF#, 16#4787C62A#, 16#A8304613#, 16#FD469501#,
      16#698098D8#, 16#8B44F7AF#, 16#FFFF5BB1#, 16#895CD7BE#,
      16#6B901122#, 16#FD987193#, 16#A679438E#, 16#49B40821#,
      16#F61E2562#, 16#C040B340#, 16#265E5A51#, 16#E9B6C7AA#,
      16#D62F105D#, 16#02441453#, 16#D8A1E681#, 16#E7D3FBC8#,
      16#21E1CDE6#, 16#C33707D6#, 16#F4D50D87#, 16#455A14ED#,
      16#A9E3E905#, 16#FCEFA3F8#, 16#676F02D9#, 16#8D2A4C8A#,
      16#FFFA3942#, 16#8771F681#, 16#6D9D6122#, 16#FDE5380C#,
      16#A4BEEA44#, 16#4BDECFA9#, 16#F6BB4B60#, 16#BEBFBC70#,
      16#289B7EC6#, 16#EAA127FA#, 16#D4EF3085#, 16#04881D05#,
      16#D9D4D039#, 16#E6DB99E5#, 16#1FA27CF8#, 16#C4AC5665#,
      16#F4292244#, 16#432AFF97#, 16#AB9423A7#, 16#FC93A039#,
      16#655B59C3#, 16#8F0CCC92#, 16#FFEFF47D#, 16#85845DD1#,
      16#6FA87E4F#, 16#FE2CE6E0#, 16#A3014314#, 16#4E0811A1#,
      16#F7537E82#, 16#BD3AF235#, 16#2AD7D2BB#, 16#EB86D391#);

   --  Per-round left-rotation amounts.
   S : constant array (Natural range 0 .. 63) of Natural :=
     (7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
      5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
      4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
      6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21);

   procedure Transform (Dg : in out Digest) is
      M : array (Natural range 0 .. 15) of Unsigned_32;
      A, B, C, D, F, T : Unsigned_32;
      G : Natural;
   begin
      --  RFC 1321 loads each 32-bit word little-endian.
      for I in 0 .. 15 loop
         M (I) := Unsigned_32 (Character'Pos (Dg.Buf (4 * I)))
                  or Shift_Left
                    (Unsigned_32 (Character'Pos (Dg.Buf (4 * I + 1))), 8)
                  or Shift_Left
                    (Unsigned_32 (Character'Pos (Dg.Buf (4 * I + 2))), 16)
                  or Shift_Left
                    (Unsigned_32 (Character'Pos (Dg.Buf (4 * I + 3))), 24);
      end loop;
      A := Dg.S (0); B := Dg.S (1); C := Dg.S (2); D := Dg.S (3);
      for I in 0 .. 63 loop
         if I < 16 then
            F := (B and C) or ((not B) and D);
            G := I;
         elsif I < 32 then
            F := (D and B) or ((not D) and C);
            G := (5 * I + 1) mod 16;
         elsif I < 48 then
            F := B xor C xor D;
            G := (3 * I + 5) mod 16;
         else
            F := C xor (B or (not D));
            G := (7 * I) mod 16;
         end if;
         T := Rotate_Left (A + F + K (I) + M (G), S (I));
         A := D; D := C; C := B; B := B + T;
      end loop;
      Dg.S (0) := Dg.S (0) + A; Dg.S (1) := Dg.S (1) + B;
      Dg.S (2) := Dg.S (2) + C; Dg.S (3) := Dg.S (3) + D;
   end Transform;

   --  Buffer one byte, running the compression when the block fills.
   --  Unlike Write this does not touch Len, so Sum can append padding.
   procedure Append_Byte (Dg : in out Digest; C : Character) is
   begin
      Dg.Buf (Dg.Buf_Len) := C;
      Dg.Buf_Len := Dg.Buf_Len + 1;
      if Dg.Buf_Len = Block_Len then
         Transform (Dg);
         Dg.Buf_Len := 0;
      end if;
   end Append_Byte;

   function New_K return Digest is
   begin
      return (S => Init, others => <>);
   end New_K;

   procedure Write (H : in out Digest; Data : Byte_Slice) is
      N : constant Natural := Natural (Byte_Vectors.Length (Data));
   begin
      H.Len := H.Len + Unsigned_64 (N);
      for I in 1 .. N loop
         Append_Byte (H, Byte_Vectors.Element (Data, I));
      end loop;
   end Write;

   function Sum (H : Digest; B : Byte_Slice) return Byte_Slice is
      Dg   : Digest := H;
      R    : Byte_Slice := B;
      Bits : constant Unsigned_64 := H.Len * 8;
   begin
      --  RFC 1321 padding: 0x80, zeros to 56 mod 64, then the 8-byte
      --  LITTLE-endian bit length.
      Append_Byte (Dg, Character'Val (16#80#));
      while Dg.Buf_Len /= 56 loop
         Append_Byte (Dg, Character'Val (0));
      end loop;
      for J in 0 .. 7 loop
         Append_Byte
           (Dg, Character'Val (Shift_Right (Bits, 8 * J) and 16#FF#));
      end loop;
      --  RFC 1321 emits each state word little-endian.
      for I in 0 .. 3 loop
         for J in 0 .. 3 loop
            Byte_Vectors.Append
              (R, Character'Val
                 (Shift_Right (Dg.S (I), 8 * J) and 16#FF#));
         end loop;
      end loop;
      return R;
   end Sum;

   procedure Reset (H : in out Digest) is
   begin
      H.S := Init;
      H.Buf_Len := 0;
      H.Len := 0;
   end Reset;

   function Size (H : Digest) return Natural is
      pragma Unreferenced (H);
   begin
      return 16;
   end Size;

   function Block_Size (H : Digest) return Natural is
      pragma Unreferenced (H);
   begin
      return Block_Len;
   end Block_Size;

   function Sum (Data : Byte_Slice) return Byte_Slice is
      H : Digest  := New_K;
   begin
      Write (H, Data);
      return Sum (H, Byte_Vectors.Empty_Vector);
   end Sum;

end Gada.Std.Crypto.Md5;
