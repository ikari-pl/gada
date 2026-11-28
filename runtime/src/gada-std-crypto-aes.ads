--  Gada.Std.Crypto.Aes — the Go `crypto/aes` package, ported
--  (Phase 8 wave 4, item 4). FIPS-197 AES-128/192/256: 16-byte
--  blocks, 10/12/14 rounds, byte-oriented SubBytes/ShiftRows/
--  MixColumns with the standard S-box tables.
--
--  Go: aes.NewCipher(key) (cipher.Block, error). v1 returns the
--  concrete Block record and raises CONSTRAINT_ERROR on a bad key
--  size (16/24/32 bytes) — Go's error half. The Block components
--  are visible so Gada.Std.Crypto.Cipher can embed the expanded
--  schedule in its mode records; treat them as internal and use
--  New_Cipher / Encrypt / Decrypt.
--
--  Go: Block.Encrypt(dst, src) / Decrypt(dst, src) with one 16-byte
--  block — v1 returns the 16-byte result as a Byte_Slice; Src must
--  be exactly one block (CONSTRAINT_ERROR otherwise).

with Gada.Std.Bytes;
with Interfaces;

package Gada.Std.Crypto.Aes is

   use Interfaces;

   type Key_Schedule is array (Natural range 0 .. 59) of Unsigned_32;

   type Block is record
      Nr : Natural := 10;   --  rounds: 10/12/14 for 128/192/256-bit keys
      W  : Key_Schedule;    --  words 0 .. 4 * (Nr + 1) - 1 are used
   end record;

   --  Go: aes.NewCipher(key).
   function New_Cipher (Key : Gada.Std.Bytes.Byte_Slice) return Block;

   --  Go: Block.BlockSize() int — always 16.
   function Block_Size (B : Block) return Natural;

   --  Go: Block.Encrypt / Block.Decrypt on a single 16-byte block.
   function Encrypt (B : Block; Src : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;
   function Decrypt (B : Block; Src : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;

end Gada.Std.Crypto.Aes;
