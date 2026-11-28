--  Gada.Std.Crypto.Cipher — the Go `crypto/cipher` package, ported
--  (Phase 8 wave 4, item 4). Block modes over Gada.Std.Crypto.Aes:
--  CBC (SP 800-38A §6.2/6.3), CTR (§6.5), and GCM AEAD (SP 800-38D,
--  96-bit nonce, 128-bit tag).
--
--  Go shapes kept: NewCBCEncrypter/NewCBCDecrypter return a
--  BlockMode with CryptBlocks(dst, src); NewCTR returns a Stream
--  with XORKeyStream(dst, src); NewGCM returns an AEAD with
--  Seal/Open. v1 deviations: results are returned/assigned via an
--  out Byte_Slice instead of a caller-preallocated dst, and the
--  error halves (bad IV length, src not a multiple of the block
--  size, GCM tag mismatch on Open) raise CONSTRAINT_ERROR.

with Gada.Std.Bytes;
with Gada.Std.Crypto.Aes;

package Gada.Std.Crypto.Cipher is

   use Gada.Std.Bytes;

   ---------------------------------------------------------------
   --  CBC block mode
   ---------------------------------------------------------------

   type Block_Mode is limited private;

   function New_CBC_Encrypter (B : Gada.Std.Crypto.Aes.Block;
                               IV : Byte_Slice) return Block_Mode;
   function New_CBC_Decrypter (B : Gada.Std.Crypto.Aes.Block;
                               IV : Byte_Slice) return Block_Mode;

   --  Go: CryptBlocks(dst, src) — Src must be a non-zero multiple of
   --  16 bytes; Dst receives the result (same length as Src).
   procedure Crypt_Blocks (M : in out Block_Mode; Dst : out Byte_Slice;
                           Src : Byte_Slice);

   ---------------------------------------------------------------
   --  CTR stream
   ---------------------------------------------------------------

   type Stream is limited private;

   function New_CTR (B : Gada.Std.Crypto.Aes.Block; IV : Byte_Slice)
      return Stream;

   --  Go: XORKeyStream(dst, src) — Dst := Src xor keystream.
   procedure XOR_Key_Stream (S : in out Stream; Dst : out Byte_Slice;
                             Src : Byte_Slice);

   ---------------------------------------------------------------
   --  GCM AEAD (96-bit nonce, 128-bit tag)
   ---------------------------------------------------------------

   type GCM is limited private;

   function New_GCM (B : Gada.Std.Crypto.Aes.Block) return GCM;
   function Nonce_Size (G : GCM) return Natural;   --  12
   function Overhead (G : GCM) return Natural;     --  16

   --  Go: Seal(dst, nonce, plaintext, additionalData) — v1 returns
   --  ciphertext || tag. Nonce must be exactly 12 bytes.
   function Seal (G : GCM; Nonce, Plaintext, Additional : Byte_Slice)
      return Byte_Slice;

   --  Go: Open(dst, nonce, ciphertext, additionalData) — v1 takes
   --  ciphertext || tag and returns the plaintext; raises
   --  CONSTRAINT_ERROR on a tag mismatch (Go's error half).
   function Open (G : GCM; Nonce, Ciphertext, Additional : Byte_Slice)
      return Byte_Slice;

private

   type Block_Mode is record
      B     : Gada.Std.Crypto.Aes.Block;
      Enc   : Boolean;      --  True = CBC encrypter, False = decrypter
      Chain : Byte_Slice;   --  IV (first block) / last ciphertext block
   end record;

   type Stream is record
      B    : Gada.Std.Crypto.Aes.Block;
      Ctr  : Byte_Slice;    --  16-byte counter, inc32 on the last 4 bytes
      Key  : Byte_Slice;    --  current keystream block
      Used : Natural := 0;  --  keystream bytes already consumed
   end record;

   type GCM is record
      B : Gada.Std.Crypto.Aes.Block;
      H : Byte_Slice;       --  E_K(0^128), the GHASH key
   end record;

end Gada.Std.Crypto.Cipher;
