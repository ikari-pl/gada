--  Gada.Std.Crypto.Sha1 — the Go `crypto/sha1` package, ported
--  (Phase 8 wave 4, item 2). FIPS 180-4 SHA-1: 64-byte blocks,
--  32-bit words, 80 rounds. SHA-1 is broken as a collision
--  resistance primitive (SHAttered 2017); the port exists for
--  compatibility with protocols that still require it (TLS legacy,
--  git-style object names), not for new designs.
--
--  Go's sha1.New() returns a hash.Hash; v1 returns the concrete
--  Digest record: New / Write / Sum / Reset / Size / Block_Size.
--  Go's sha1.Sum(data) [20]byte maps to a 20-byte Byte_Slice here.

with Gada.Std.Bytes;
with Interfaces;

package Gada.Std.Crypto.Sha1 is

   use Interfaces;

   type Digest is limited private;

   --  Go: sha1.New() -> New_K (new is reserved) hash.Hash.
   function New_K return Digest;

   --  Go: h.Write(p) (io.Writer) — returns (len p, nil error); v1 is a
   --  procedure, the error half is always nil.
   procedure Write (H : in out Digest; Data : Gada.Std.Bytes.Byte_Slice);

   --  Go: h.Sum(b) []byte — appends the 20-byte big-endian digest.
   function Sum (H : Digest; B : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;

   --  Go: h.Reset(), h.Size() int, h.BlockSize() int.
   procedure Reset (H : in out Digest);
   function Size (H : Digest) return Natural;
   function Block_Size (H : Digest) return Natural;

   --  Go: sha1.Sum(data) [20]byte — one-shot, as a 20-byte slice.
   function Sum (Data : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;

private

   Block_Len : constant := 64;

   type State_Array is array (Natural range 0 .. 4) of Unsigned_32;

   Init : constant State_Array :=
     (16#67452301#, 16#EFCDAB89#, 16#98BADCFE#, 16#10325476#,
      16#C3D2E1F0#);

   type Digest is record
      H       : State_Array := Init;
      Buf     : array (Natural range 0 .. Block_Len - 1) of Character :=
                  (others => Character'Val (0));
      Buf_Len : Natural := 0;
      Len     : Unsigned_64 := 0;  --  total bytes written
   end record;

end Gada.Std.Crypto.Sha1;
