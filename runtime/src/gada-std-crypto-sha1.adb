--  Gada.Std.Crypto.Sha1 body — see spec. Textbook FIPS 180-4 SHA-1:
--  big-endian word load, 80-word schedule with a rotate-left-by-1
--  recurrence, and the four round functions with their K constants.

with Gada.Std.Bytes; use Gada.Std.Bytes;

package body Gada.Std.Crypto.Sha1 is

   use Interfaces;

   procedure Transform (Dg : in out Digest) is
      W : array (Natural range 0 .. 79) of Unsigned_32;
      A, B, C, D, E, F, K, T : Unsigned_32;
   begin
      for I in 0 .. 15 loop
         W (I) := Shift_Left (Unsigned_32 (Character'Pos (Dg.Buf (4 * I))), 24)
                  or Shift_Left
                    (Unsigned_32 (Character'Pos (Dg.Buf (4 * I + 1))), 16)
                  or Shift_Left
                    (Unsigned_32 (Character'Pos (Dg.Buf (4 * I + 2))), 8)
                  or Unsigned_32 (Character'Pos (Dg.Buf (4 * I + 3)));
      end loop;
      for I in 16 .. 79 loop
         W (I) := Rotate_Left
           (W (I - 3) xor W (I - 8) xor W (I - 14) xor W (I - 16), 1);
      end loop;
      A := Dg.H (0); B := Dg.H (1); C := Dg.H (2); D := Dg.H (3);
      E := Dg.H (4);
      for I in 0 .. 79 loop
         if I < 20 then
            F := (B and C) or ((not B) and D);
            K := 16#5A827999#;
         elsif I < 40 then
            F := B xor C xor D;
            K := 16#6ED9EBA1#;
         elsif I < 60 then
            F := (B and C) or (B and D) or (C and D);
            K := 16#8F1BBCDC#;
         else
            F := B xor C xor D;
            K := 16#CA62C1D6#;
         end if;
         T := Rotate_Left (A, 5) + F + E + K + W (I);
         E := D; D := C; C := Rotate_Left (B, 30); B := A; A := T;
      end loop;
      Dg.H (0) := Dg.H (0) + A; Dg.H (1) := Dg.H (1) + B;
      Dg.H (2) := Dg.H (2) + C; Dg.H (3) := Dg.H (3) + D;
      Dg.H (4) := Dg.H (4) + E;
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

   function New return Digest is
   begin
      return (H => Init, others => <>);
   end New;

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
      --  FIPS padding: 0x80, zeros to 56 mod 64, 8-byte big-endian
      --  bit length.
      Append_Byte (Dg, Character'Val (16#80#));
      while Dg.Buf_Len /= 56 loop
         Append_Byte (Dg, Character'Val (0));
      end loop;
      for J in 0 .. 7 loop
         Append_Byte
           (Dg, Character'Val (Shift_Right (Bits, 8 * (7 - J)) and 16#FF#));
      end loop;
      for I in 0 .. 4 loop
         for J in 0 .. 3 loop
            Byte_Vectors.Append
              (R, Character'Val
                 (Shift_Right (Dg.H (I), 8 * (3 - J)) and 16#FF#));
         end loop;
      end loop;
      return R;
   end Sum;

   procedure Reset (H : in out Digest) is
   begin
      H.H := Init;
      H.Buf_Len := 0;
      H.Len := 0;
   end Reset;

   function Size (H : Digest) return Natural is
      pragma Unreferenced (H);
   begin
      return 20;
   end Size;

   function Block_Size (H : Digest) return Natural is
      pragma Unreferenced (H);
   begin
      return Block_Len;
   end Block_Size;

   function Sum (Data : Byte_Slice) return Byte_Slice is
      H : Digest := New;
   begin
      Write (H, Data);
      return Sum (H, Byte_Vectors.Empty_Vector);
   end Sum;

end Gada.Std.Crypto.Sha1;
