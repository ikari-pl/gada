--  Gada.Std.Crypto.Cipher body — see spec. CBC chains the previous
--  ciphertext block (IV for the first); CTR encrypts an inc32
--  counter; GCM is CTR starting at inc32(J0) plus a GHASH over
--  AAD || ciphertext with the length block, tag = E_K(J0) xor GHASH.

with Interfaces;
with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Crypto.Aes;
with Gada.Std.Crypto.Hmac;  --  for constant-time tag compare

package body Gada.Std.Crypto.Cipher is

   use Interfaces;

   type Byte16 is array (Natural range 0 .. 15) of Unsigned_8;

   function To_Byte16 (Src : Byte_Slice) return Byte16 is
      B : Byte16;
   begin
      for I in 0 .. 15 loop
         B (I) := Unsigned_8 (Character'Pos (Byte_Vectors.Element (Src, I + 1)));
      end loop;
      return B;
   end To_Byte16;

   function To_Bytes (B : Byte16) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      for I in 0 .. 15 loop
         Byte_Vectors.Append (R, Character'Val (B (I)));
      end loop;
      return R;
   end To_Bytes;

   function Sub_Slice (B : Byte_Slice; First, Last : Natural)
      return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      for I in First .. Last loop
         Byte_Vectors.Append (R, Byte_Vectors.Element (B, I));
      end loop;
      return R;
   end Sub_Slice;

   function Xor_Blocks (A, B : Byte_Slice) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      for I in 1 .. Natural (Byte_Vectors.Length (A)) loop
         Byte_Vectors.Append
           (R, Character'Val
              (Unsigned_32 (Character'Pos (Byte_Vectors.Element (A, I)))
               xor Unsigned_32 (Character'Pos (Byte_Vectors.Element (B, I)))));
      end loop;
      return R;
   end Xor_Blocks;

   procedure Check_IV (IV : Byte_Slice) is
   begin
      if Natural (Byte_Vectors.Length (IV)) /= 16 then
         raise Constraint_Error
           with "cipher: IV must be exactly 16 bytes, got"
                & Natural'Image (Natural (Byte_Vectors.Length (IV)));
      end if;
   end Check_IV;

   ---------------------------------------------------------------
   --  CBC
   ---------------------------------------------------------------

   function New_CBC_Encrypter (B : Gada.Std.Crypto.Aes.Block;
                               IV : Byte_Slice) return Block_Mode is
   begin
      Check_IV (IV);
      return (B => B, Enc => True, Chain => IV);
   end New_CBC_Encrypter;

   function New_CBC_Decrypter (B : Gada.Std.Crypto.Aes.Block;
                               IV : Byte_Slice) return Block_Mode is
   begin
      Check_IV (IV);
      return (B => B, Enc => False, Chain => IV);
   end New_CBC_Decrypter;

   procedure Crypt_Blocks (M : in out Block_Mode; Dst : out Byte_Slice;
                           Src : Byte_Slice) is
      N : constant Natural := Natural (Byte_Vectors.Length (Src));
   begin
      if N = 0 or else N mod 16 /= 0 then
         raise Constraint_Error
           with "cipher: CryptBlocks src must be a non-zero multiple of 16";
      end if;
      Dst := Byte_Vectors.Empty_Vector;
      for Off in 0 .. N / 16 - 1 loop
         declare
            Raw : constant Byte_Slice :=
              Sub_Slice (Src, 16 * Off + 1, 16 * Off + 16);
            --  Encrypt chains the XORed block; decrypt consumes the
            --  raw ciphertext block and XORs after the block decrypt.
            Blk : constant Byte_Slice :=
              (if M.Enc then Xor_Blocks (M.Chain, Raw) else Raw);
            C   : Byte_Slice;
         begin
            if M.Enc then
               C := Gada.Std.Crypto.Aes.Encrypt (M.B, Blk);
               M.Chain := C;
            else
               declare
                  P : constant Byte_Slice :=
                    Gada.Std.Crypto.Aes.Decrypt (M.B, Blk);
               begin
                  C := Xor_Blocks (P, M.Chain);
                  M.Chain := Raw;
               end;
            end if;
            for I in 1 .. Natural (Byte_Vectors.Length (C)) loop
               Byte_Vectors.Append (Dst, Byte_Vectors.Element (C, I));
            end loop;
         end;
      end loop;
   end Crypt_Blocks;

   ---------------------------------------------------------------
   --  CTR
   ---------------------------------------------------------------

   procedure Inc32 (Ctr : in out Byte_Slice) is
      --  Increment the last 4 bytes big-endian mod 2**32 (SP 800-38A).
      V : Unsigned_32 := 0;
   begin
      for I in 13 .. 16 loop
         V := Shift_Left (V, 8)
           or Unsigned_32 (Character'Pos (Byte_Vectors.Element (Ctr, I)));
      end loop;
      V := V + 1;
      for I in 13 .. 16 loop
         Byte_Vectors.Replace_Element
           (Ctr, I,
            Character'Val (Shift_Right (V, 8 * (16 - I)) and 16#FF#));
      end loop;
   end Inc32;

   function New_CTR (B : Gada.Std.Crypto.Aes.Block; IV : Byte_Slice)
      return Stream is
   begin
      Check_IV (IV);
      return (B => B, Ctr => IV, Key => Byte_Vectors.Empty_Vector,
              Used => 16);
   end New_CTR;

   procedure XOR_Key_Stream (S : in out Stream; Dst : out Byte_Slice;
                             Src : Byte_Slice) is
      N : constant Natural := Natural (Byte_Vectors.Length (Src));
   begin
      Dst := Byte_Vectors.Empty_Vector;
      for Off in 0 .. N - 1 loop
         if S.Used = 16 then
            S.Key := Gada.Std.Crypto.Aes.Encrypt (S.B, S.Ctr);
            Inc32 (S.Ctr);
            S.Used := 0;
         end if;
         Byte_Vectors.Append
           (Dst, Character'Val
              (Unsigned_32 (Character'Pos
                 (Byte_Vectors.Element (Src, Off + 1)))
               xor Unsigned_32 (Character'Pos
                 (Byte_Vectors.Element (S.Key, S.Used + 1)))));
         S.Used := S.Used + 1;
      end loop;
   end XOR_Key_Stream;

   ---------------------------------------------------------------
   --  GCM
   ---------------------------------------------------------------

   --  Multiply in GF(2^128) with the GCM reduction polynomial
   --  (R = 0xE1 at byte 0). Y's bits are consumed MSB-first.
   procedure GF128_Mul (X, Y : Byte16; R : out Byte16) is
      Z : Byte16 := (others => 0);
      V : Byte16 := X;
   begin
      for I in 0 .. 15 loop
         for B in 0 .. 7 loop
            if (Shift_Right (Y (I), 7 - B) and 1) /= 0 then
               for K in 0 .. 15 loop
                  Z (K) := Z (K) xor V (K);
               end loop;
            end if;
            declare
               LSB : constant Unsigned_8 := V (15) and 1;
            begin
               for K in reverse 1 .. 15 loop
                  V (K) := Shift_Right (V (K), 1)
                    or (Shift_Left (V (K - 1), 7) and 16#80#);
               end loop;
               V (0) := Shift_Right (V (0), 1);
               if LSB /= 0 then
                  V (0) := V (0) xor 16#E1#;
               end if;
            end;
         end loop;
      end loop;
      R := Z;
   end GF128_Mul;

   procedure GHASH_Block (Y : in out Byte16; H : Byte16; Blk : Byte16) is
      T : Byte16;
   begin
      for K in 0 .. 15 loop
         T (K) := Y (K) xor Blk (K);
      end loop;
      GF128_Mul (T, H, Y);
   end GHASH_Block;

   --  GHASH over AAD then C, each zero-padded to a 16-byte multiple,
   --  then the 64-bit big-endian bit-length block.
   function GHASH (H : Byte_Slice; AAD, C : Byte_Slice) return Byte_Slice is
      H16 : constant Byte16 := To_Byte16 (H);
      Y   : Byte16 := (others => 0);

      procedure Feed (Data : Byte_Slice) is
         N : constant Natural := Natural (Byte_Vectors.Length (Data));
      begin
         for Off in 0 .. (N + 15) / 16 - 1 loop
            declare
               Blk : Byte16 := (others => 0);
               Last : constant Natural :=
                 Natural'Min (16, N - 16 * Off);
            begin
               for I in 0 .. Last - 1 loop
                  Blk (I) :=
                    Unsigned_8 (Character'Pos
                      (Byte_Vectors.Element (Data, 16 * Off + I + 1)));
               end loop;
               GHASH_Block (Y, H16, Blk);
            end;
         end loop;
      end Feed;
   begin
      Feed (AAD);
      Feed (C);
      declare
         LA : constant Unsigned_64 :=
           Unsigned_64 (Natural (Byte_Vectors.Length (AAD))) * 8;
         LC : constant Unsigned_64 :=
           Unsigned_64 (Natural (Byte_Vectors.Length (C))) * 8;
         Len_Blk : Byte16 := (others => 0);
      begin
         for J in 0 .. 7 loop
            Len_Blk (J) := Unsigned_8 (Shift_Right (LA, 8 * (7 - J)) and 16#FF#);
            Len_Blk (8 + J) := Unsigned_8 (Shift_Right (LC, 8 * (7 - J)) and 16#FF#);
         end loop;
         GHASH_Block (Y, H16, Len_Blk);
      end;
      return To_Bytes (Y);
   end GHASH;

   function New_GCM (B : Gada.Std.Crypto.Aes.Block) return GCM is
      Zero : constant Byte_Slice := New_Bytes (16);
   begin
      return (B => B, H => Gada.Std.Crypto.Aes.Encrypt (B, Zero));
   end New_GCM;

   procedure New_GCM (B   : Gada.Std.Crypto.Aes.Block;
                      G   : out GCM;
                      Err : out Gada.Std.Errors.Error_Access) is
   begin
      G := New_GCM (B);
      Err := null;
   exception
      when others =>
         G := (B => (Nr => 10, W => (others => 0)),
               H => Byte_Vectors.Empty_Vector);
         Err := Gada.Std.Errors.New_K ("crypto/cipher: NewGCM failed");
   end New_GCM;

   function Nonce_Size (G : GCM) return Natural is
      pragma Unreferenced (G);
   begin
      return 12;
   end Nonce_Size;

   function Overhead (G : GCM) return Natural is
      pragma Unreferenced (G);
   begin
      return 16;
   end Overhead;

   --  J0 for a 96-bit nonce: nonce || 0x00000001 (SP 800-38D §5.2.1).
   function J0_Of (Nonce : Byte_Slice) return Byte_Slice is
      J0 : Byte_Slice := Nonce;
   begin
      Byte_Vectors.Append (J0, Character'Val (0));
      Byte_Vectors.Append (J0, Character'Val (0));
      Byte_Vectors.Append (J0, Character'Val (0));
      Byte_Vectors.Append (J0, Character'Val (1));
      return J0;
   end J0_Of;

   function Seal (G : GCM; Nonce, Plaintext, Additional : Byte_Slice)
      return Byte_Slice is
   begin
      if Natural (Byte_Vectors.Length (Nonce)) /= 12 then
         raise Constraint_Error with "cipher: GCM nonce must be 12 bytes";
      end if;
      declare
         J0  : constant Byte_Slice := J0_Of (Nonce);
         Ctr : Byte_Slice := J0;
      begin
         Inc32 (Ctr);
         declare
            C   : Byte_Slice;
            S   : Gada.Std.Crypto.Cipher.Stream :=
              (B => G.B, Ctr => Ctr, Key => Byte_Vectors.Empty_Vector,
               Used => 16);
         begin
            XOR_Key_Stream (S, C, Plaintext);
            declare
               S_Hash : constant Byte_Slice := GHASH (G.H, Additional, C);
               Tag    : Byte_Slice :=
                 Xor_Blocks (Gada.Std.Crypto.Aes.Encrypt (G.B, J0), S_Hash);
               R      : Byte_Slice := C;
            begin
               for I in 1 .. Natural (Byte_Vectors.Length (Tag)) loop
                  Byte_Vectors.Append (R, Byte_Vectors.Element (Tag, I));
               end loop;
               return R;
            end;
         end;
      end;
   end Seal;

   function Open (G : GCM; Nonce, Ciphertext, Additional : Byte_Slice)
      return Byte_Slice is
      N : constant Natural := Natural (Byte_Vectors.Length (Ciphertext));
   begin
      if Natural (Byte_Vectors.Length (Nonce)) /= 12 then
         raise Constraint_Error with "cipher: GCM nonce must be 12 bytes";
      end if;
      if N < 16 then
         raise Constraint_Error with "cipher: GCM ciphertext shorter than tag";
      end if;
      declare
         C   : constant Byte_Slice :=
           Sub_Slice (Ciphertext, 1, N - 16);
         Tag : constant Byte_Slice :=
           Sub_Slice (Ciphertext, N - 15, N);
         J0  : constant Byte_Slice := J0_Of (Nonce);
         Ctr : Byte_Slice := J0;
         Expect : Byte_Slice;
      begin
         Inc32 (Ctr);
         declare
            S_Hash : constant Byte_Slice := GHASH (G.H, Additional, C);
         begin
            Expect := Xor_Blocks (Gada.Std.Crypto.Aes.Encrypt (G.B, J0), S_Hash);
         end;
         if not Gada.Std.Crypto.Hmac.Equal (Tag, Expect) then
            raise Constraint_Error with "cipher: GCM tag mismatch";
         end if;
         declare
            S : Gada.Std.Crypto.Cipher.Stream :=
              (B => G.B, Ctr => Ctr, Key => Byte_Vectors.Empty_Vector,
               Used => 16);
            P : Byte_Slice;
         begin
            XOR_Key_Stream (S, P, C);
            return P;
         end;
      end;
   end Open;

   procedure Open (G          : GCM;
                   Nonce      : Byte_Slice;
                   Ciphertext : Byte_Slice;
                   Additional : Byte_Slice;
                   Plain      : out Byte_Slice;
                   Err        : out Gada.Std.Errors.Error_Access) is
   begin
      Plain := Open (G, Nonce, Ciphertext, Additional);
      Err := null;
   exception
      when Constraint_Error =>
         Err := Gada.Std.Errors.New_K
           ("crypto/cipher: message authentication failed");
   end Open;

end Gada.Std.Crypto.Cipher;
