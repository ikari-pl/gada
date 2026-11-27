--  Gada.Std.Crypto.Sha512 body — see spec. Textbook FIPS 180-4
--  SHA-512: big-endian 64-bit word load, 80-round sigma0/sigma1
--  schedule, Ch/Maj round function. All word arithmetic is mod
--  2**64, which Unsigned_64 gives for free.

with Gada.Std.Bytes; use Gada.Std.Bytes;

package body Gada.Std.Crypto.Sha512 is

   use Interfaces;

   K : constant array (Natural range 0 .. 79) of Unsigned_64 :=
     (16#428A2F98D728AE22#, 16#7137449123EF65CD#,
      16#B5C0FBCFEC4D3B2F#, 16#E9B5DBA58189DBBC#,
      16#3956C25BF348B538#, 16#59F111F1B605D019#,
      16#923F82A4AF194F9B#, 16#AB1C5ED5DA6D8118#,
      16#D807AA98A3030242#, 16#12835B0145706FBE#,
      16#243185BE4EE4B28C#, 16#550C7DC3D5FFB4E2#,
      16#72BE5D74F27B896F#, 16#80DEB1FE3B1696B1#,
      16#9BDC06A725C71235#, 16#C19BF174CF692694#,
      16#E49B69C19EF14AD2#, 16#EFBE4786384F25E3#,
      16#0FC19DC68B8CD5B5#, 16#240CA1CC77AC9C65#,
      16#2DE92C6F592B0275#, 16#4A7484AA6EA6E483#,
      16#5CB0A9DCBD41FBD4#, 16#76F988DA831153B5#,
      16#983E5152EE66DFAB#, 16#A831C66D2DB43210#,
      16#B00327C898FB213F#, 16#BF597FC7BEEF0EE4#,
      16#C6E00BF33DA88FC2#, 16#D5A79147930AA725#,
      16#06CA6351E003826F#, 16#142929670A0E6E70#,
      16#27B70A8546D22FFC#, 16#2E1B21385C26C926#,
      16#4D2C6DFC5AC42AED#, 16#53380D139D95B3DF#,
      16#650A73548BAF63DE#, 16#766A0ABB3C77B2A8#,
      16#81C2C92E47EDAEE6#, 16#92722C851482353B#,
      16#A2BFE8A14CF10364#, 16#A81A664BBC423001#,
      16#C24B8B70D0F89791#, 16#C76C51A30654BE30#,
      16#D192E819D6EF5218#, 16#D69906245565A910#,
      16#F40E35855771202A#, 16#106AA07032BBD1B8#,
      16#19A4C116B8D2D0C8#, 16#1E376C085141AB53#,
      16#2748774CDF8EEB99#, 16#34B0BCB5E19B48A8#,
      16#391C0CB3C5C95A63#, 16#4ED8AA4AE3418ACB#,
      16#5B9CCA4F7763E373#, 16#682E6FF3D6B2B8A3#,
      16#748F82EE5DEFB2FC#, 16#78A5636F43172F60#,
      16#84C87814A1F0AB72#, 16#8CC702081A6439EC#,
      16#90BEFFFA23631E28#, 16#A4506CEBDE82BDE9#,
      16#BEF9A3F7B2C67915#, 16#C67178F2E372532B#,
      16#CA273ECEEA26619C#, 16#D186B8C721C0C207#,
      16#EADA7DD6CDE0EB1E#, 16#F57D4F7FEE6ED178#,
      16#06F067AA72176FBA#, 16#0A637DC5A2C898A6#,
      16#113F9804BEF90DAE#, 16#1B710B35131C471B#,
      16#28DB77F523047D84#, 16#32CAAB7B40C72493#,
      16#3C9EBE0A15C9BEBC#, 16#431D67C49C100D4C#,
      16#4CC5D4BECB3E42B6#, 16#597F299CFC657E2A#,
      16#5FCB6FAB3AD6FAEC#, 16#6C44198C4A475817#);

   procedure Transform (Dg : in out Digest) is
      W  : array (Natural range 0 .. 79) of Unsigned_64;
      A, B, C, D, E, F, G, H : Unsigned_64;
      S0, S1, T1, T2 : Unsigned_64;
   begin
      for I in 0 .. 15 loop
         W (I) := Shift_Left (Unsigned_64 (Character'Pos (Dg.Buf (8 * I))), 56)
                  or Shift_Left
                    (Unsigned_64 (Character'Pos (Dg.Buf (8 * I + 1))), 48)
                  or Shift_Left
                    (Unsigned_64 (Character'Pos (Dg.Buf (8 * I + 2))), 40)
                  or Shift_Left
                    (Unsigned_64 (Character'Pos (Dg.Buf (8 * I + 3))), 32)
                  or Shift_Left
                    (Unsigned_64 (Character'Pos (Dg.Buf (8 * I + 4))), 24)
                  or Shift_Left
                    (Unsigned_64 (Character'Pos (Dg.Buf (8 * I + 5))), 16)
                  or Shift_Left
                    (Unsigned_64 (Character'Pos (Dg.Buf (8 * I + 6))), 8)
                  or Unsigned_64 (Character'Pos (Dg.Buf (8 * I + 7)));
      end loop;
      for I in 16 .. 79 loop
         S0 := Rotate_Right (W (I - 15), 1) xor Rotate_Right (W (I - 15), 8)
               xor Shift_Right (W (I - 15), 7);
         S1 := Rotate_Right (W (I - 2), 19) xor Rotate_Right (W (I - 2), 61)
               xor Shift_Right (W (I - 2), 6);
         W (I) := W (I - 16) + S0 + W (I - 7) + S1;
      end loop;
      A := Dg.H (0); B := Dg.H (1); C := Dg.H (2); D := Dg.H (3);
      E := Dg.H (4); F := Dg.H (5); G := Dg.H (6); H := Dg.H (7);
      for I in 0 .. 79 loop
         S1 := Rotate_Right (E, 14) xor Rotate_Right (E, 18)
               xor Rotate_Right (E, 41);
         T1 := H + S1 + ((E and F) xor ((not E) and G)) + K (I) + W (I);
         S0 := Rotate_Right (A, 28) xor Rotate_Right (A, 34)
               xor Rotate_Right (A, 39);
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
      --  FIPS padding: 0x80, zeros to 112 mod 128, then the 16-byte
      --  big-endian bit length (high half zero — see spec).
      Append_Byte (Dg, Character'Val (16#80#));
      while Dg.Buf_Len /= 112 loop
         Append_Byte (Dg, Character'Val (0));
      end loop;
      for J in 0 .. 7 loop
         Append_Byte (Dg, Character'Val (0));
      end loop;
      for J in 0 .. 7 loop
         Append_Byte
           (Dg, Character'Val (Shift_Right (Bits, 8 * (7 - J)) and 16#FF#));
      end loop;
      for I in 0 .. 7 loop
         for J in 0 .. 7 loop
            Byte_Vectors.Append
              (R, Character'Val
                 (Shift_Right (Dg.H (I), 8 * (7 - J)) and 16#FF#));
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
      return 64;
   end Size;

   function Block_Size (H : Digest) return Natural is
      pragma Unreferenced (H);
   begin
      return Block_Len;
   end Block_Size;

   function Sum512 (Data : Byte_Slice) return Byte_Slice is
      H : Digest := New;
   begin
      Write (H, Data);
      return Sum (H, Byte_Vectors.Empty_Vector);
   end Sum512;

end Gada.Std.Crypto.Sha512;
