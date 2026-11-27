--  Gada.Std.Crypto.Sha256 — the Go `crypto/sha256` package, ported
--  (Phase 8 wave 4, item 2). FIPS 180-4 SHA-256: 64-byte blocks,
--  32-bit words, 64 rounds.
--
--  Go's sha256.New() returns a hash.Hash; v1 returns the concrete
--  Digest record (same shape as the Gada.Std.Hash.Fnv ports): New /
--  Write / Sum / Reset / Size / Block_Size are primitive operations.
--  Go's Sum256(data) [32]byte maps to a 32-byte Byte_Slice here.

with Gada.Std.Bytes;
with Interfaces;

package Gada.Std.Crypto.Sha256 is

   use Interfaces;

   type Digest is limited private;

   --  Go: sha256.New() hash.Hash.
   function New return Digest;

   --  Go: h.Write(p) (io.Writer) — returns (len p, nil error); v1 is a
   --  procedure, the error half is always nil.
   procedure Write (H : in out Digest; Data : Gada.Std.Bytes.Byte_Slice);

   --  Go: h.Sum(b) []byte — appends the 32-byte big-endian digest.
   function Sum (H : Digest; B : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;

   --  Go: h.Reset(), h.Size() int, h.BlockSize() int.
   procedure Reset (H : in out Digest);
   function Size (H : Digest) return Natural;
   function Block_Size (H : Digest) return Natural;

   --  Go: sha256.Sum256(data) [32]byte — one-shot, as a 32-byte slice.
   function Sum256 (Data : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;

private

   Block_Len : constant := 64;

   type State_Array is array (Natural range 0 .. 7) of Unsigned_32;

   Init : constant State_Array :=
     (16#6A09E667#, 16#BB67AE85#, 16#3C6EF372#, 16#A54FF53A#,
      16#510E527F#, 16#9B05688C#, 16#1F83D9AB#, 16#5BE0CD19#);

   type Digest is record
      H       : State_Array := Init;
      Buf     : array (Natural range 0 .. Block_Len - 1) of Character :=
                  (others => Character'Val (0));
      Buf_Len : Natural := 0;
      Len     : Unsigned_64 := 0;  --  total bytes written
   end record;

end Gada.Std.Crypto.Sha256;
