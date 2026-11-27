--  Gada.Std.Crypto.Md5 — the Go `crypto/md5` package, ported
--  (Phase 8 wave 4, item 2). RFC 1321 MD5: 64-byte blocks, 32-bit
--  little-endian words, 64 rounds. MD5 is broken as a collision
--  resistance primitive; the port exists for compatibility with
--  legacy protocols and checksums, not for new designs.
--
--  Go's md5.New() returns a hash.Hash; v1 returns the concrete
--  Digest record: New / Write / Sum / Reset / Size / Block_Size.
--  Go's md5.Sum(data) [16]byte maps to a 16-byte Byte_Slice here.

with Gada.Std.Bytes;
with Interfaces;

package Gada.Std.Crypto.Md5 is

   use Interfaces;

   type Digest is limited private;

   --  Go: md5.New() hash.Hash.
   function New return Digest;

   --  Go: h.Write(p) (io.Writer) — returns (len p, nil error); v1 is a
   --  procedure, the error half is always nil.
   procedure Write (H : in out Digest; Data : Gada.Std.Bytes.Byte_Slice);

   --  Go: h.Sum(b) []byte — appends the 16-byte little-endian digest.
   function Sum (H : Digest; B : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;

   --  Go: h.Reset(), h.Size() int, h.BlockSize() int.
   procedure Reset (H : in out Digest);
   function Size (H : Digest) return Natural;
   function Block_Size (H : Digest) return Natural;

   --  Go: md5.Sum(data) [16]byte — one-shot, as a 16-byte slice.
   function Sum (Data : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;

private

   Block_Len : constant := 64;

   type State_Array is array (Natural range 0 .. 3) of Unsigned_32;

   Init : constant State_Array :=
     (16#67452301#, 16#EFCDAB89#, 16#98BADCFE#, 16#10325476#);

   type Digest is record
      S       : State_Array := Init;
      Buf     : array (Natural range 0 .. Block_Len - 1) of Character :=
                  (others => Character'Val (0));
      Buf_Len : Natural := 0;
      Len     : Unsigned_64 := 0;  --  total bytes written
   end record;

end Gada.Std.Crypto.Md5;
