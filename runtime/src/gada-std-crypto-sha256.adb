--  Gada.Std.Crypto.Sha256 body — see spec. Textbook FIPS 180-4:
--  big-endian word load, the sigma0/sigma1 message schedule, and the
--  Ch/Maj round function. All word arithmetic is mod 2**32, which
--  Unsigned_32 gives for free.

with Gada.Std.Bytes; use Gada.Std.Bytes;

package body Gada.Std.Crypto.Sha256 is

   use Interfaces;

   K : constant array (Natural range 0 .. 63) of Unsigned_32 :=
     (16#428A2F98#, 16#71374491#, 16#B5C0FBCF#, 16#E9B5DBA5#,
      16#3956C25B#, 16#59F111F1#, 16#923F82A4#, 16#AB1C5ED5#,
      16#D807AA98#, 16#12835B01#, 16#243185BE#, 16#550C7DC3#,
      16#72BE5D74#, 16#80DEB1FE#, 16#9BDC06A7#, 16#C19BF174#,
      16#E49B69C1#, 16#EFBE4786#, 16#0FC19DC6#, 16#240CA1CC#,
      16#2DE92C6F#, 16#4A7484AA#, 16#5CB0A9DC#, 16#76F988DA#,
      16#983E5152#, 16#A831C66D#, 16#B00327C8#, 16#BF597FC7#,
      16#C6E00BF3#, 16#D5A79147#, 16#06CA6351#, 16#14292967#,
      16#27B70A85#, 16#2E1B2138#, 16#4D2C6DFC#, 16#53380D13#,
      16#650A7354#, 16#766A0ABB#, 16#81C2C92E#, 16#92722C85#,
      16#A2BFE8A1#, 16#A81A664B#, 16#C24B8B70#, 16#C76C51A3#,
      16#D192E819#, 16#D6990624#, 16#F40E3585#, 16#106AA070#,
      16#19A4C116#, 16#1E376C08#, 16#2748774C#, 16#34B0BCB5#,
      16#391C0CB3#, 16#4ED8AA4A#, 16#5B9CCA4F#, 16#682E6FF3#,
      16#748F82EE#, 16#78A5636F#, 16#84C87814#, 16#8CC70208#,
      16#90BEFFFA#, 16#A4506CEB#, 16#BEF9A3F7#, 16#C67178F2#);

   procedure Transform (Dg : in out Digest) is
      W  : array (Natural range 0 .. 63) of Unsigned_32;
      A, B, C, D, E, F, G, H : Unsigned_32;
      S0, S1, T1, T2 : Unsigned_32;
   begin
      for I in 0 .. 15 loop
         W (I) := Shift_Left (Unsigned_32 (Character'Pos (Dg.Buf (4 * I))), 24)
                  or Shift_Left
                    (Unsigned_32 (Character'Pos (Dg.Buf (4 * I + 1))), 16)
                  or Shift_Left
                    (Unsigned_32 (Character'Pos (Dg.Buf (4 * I + 2))), 8)
                  or Unsigned_32 (Character'Pos (Dg.Buf (4 * I + 3)));
      end loop;
      for I in 16 .. 63 loop
         S0 := Rotate_Right (W (I - 15), 7) xor Rotate_Right (W (I - 15), 18)
               xor Shift_Right (W (I - 15), 3);
         S1 := Rotate_Right (W (I - 2), 17) xor Rotate_Right (W (I - 2), 19)
               xor Shift_Right (W (I - 2), 10);
         W (I) := W (I - 16) + S0 + W (I - 7) + S1;
      end loop;
      A := Dg.H (0); B := Dg.H (1); C := Dg.H (2); D := Dg.H (3);
      E := Dg.H (4); F := Dg.H (5); G := Dg.H (6); H := Dg.H (7);
      for I in 0 .. 63 loop
         S1 := Rotate_Right (E, 6) xor Rotate_Right (E, 11)
               xor Rotate_Right (E, 25);
         T1 := H + S1 + ((E and F) xor ((not E) and G)) + K (I) + W (I);
         S0 := Rotate_Right (A, 2) xor Rotate_Right (A, 13)
               xor Rotate_Right (A, 22);
         T2 := S0 + ((A and B) xor (A and C) xor (B and C));
         H := G; G := F; F := E; E := D + T1;
         D := C; C := B; B := A; A := T1 + T2;
      end loop;
      Dg.H (0) := Dg.H (0) + A; Dg.H (1) := Dg.H (1) + B;
      Dg.H (2) := Dg.H (2) + C; Dg.H (3) := Dg.H (3) + D;
      Dg.H (4) := Dg.H (4) + E; Dg.H (5) := Dg.H (5) + F;
      Dg.H (6) := Dg.H (6) + G; Dg.H (7) := Dg.H (7) + H;
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
      for I in 0 .. 7 loop
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
      return 32;
   end Size;

   function Block_Size (H : Digest) return Natural is
      pragma Unreferenced (H);
   begin
      return Block_Len;
   end Block_Size;

   function Sum256 (Data : Byte_Slice) return Byte_Slice is
      H : Digest := New;
   begin
      Write (H, Data);
      return Sum (H, Byte_Vectors.Empty_Vector);
   end Sum256;

end Gada.Std.Crypto.Sha256;
