--  Gada.Std.Crypto.Sha512 — the Go `crypto/sha512` package, ported
--  (Phase 8 wave 4, item 2). FIPS 180-4 SHA-512: 128-byte blocks,
--  64-bit words, 80 rounds.
--
--  Go's sha512.New() returns a hash.Hash; v1 returns the concrete
--  Digest record (same shape as the Gada.Std.Hash.Fnv ports): New_K /
--  Write / Sum / Reset / Size / Block_Size are primitive operations.
--  Go's Sum512(data) [64]byte maps to a 64-byte Byte_Slice here.
--
--  v1 tracks the message length in a single Unsigned_64, so the
--  128-bit length field of the FIPS padding carries a zero high half
--  (messages beyond 2**61 bytes are out of scope).

with Gada.Std.Bytes;
with Interfaces;

package Gada.Std.Crypto.Sha512 is

   use Interfaces;

   type Digest is limited private;

   --  Go: sha512.New() -> New_K (new is reserved) hash.Hash.
   function New_K return Digest;

   --  Go: h.Write(p) (io.Writer) — returns (len p, nil error); v1 is a
   --  procedure, the error half is always nil.
   procedure Write (H : in out Digest; Data : Gada.Std.Bytes.Byte_Slice);

   --  Go: h.Sum(b) []byte — appends the 64-byte big-endian digest.
   function Sum (H : Digest; B : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;

   --  Go: h.Reset(), h.Size() int, h.BlockSize() int.
   procedure Reset (H : in out Digest);
   function Size (H : Digest) return Natural;
   function Block_Size (H : Digest) return Natural;

   --  Go: sha512.Sum512(data) [64]byte — one-shot, as a 64-byte slice.
   function Sum512 (Data : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;

private

   Block_Len : constant := 128;

   type State_Array is array (Natural range 0 .. 7) of Unsigned_64;

   Init : constant State_Array :=
     (16#6A09E667F3BCC908#, 16#BB67AE8584CAA73B#,
      16#3C6EF372FE94F82B#, 16#A54FF53A5F1D36F1#,
      16#510E527FADE682D1#, 16#9B05688C2B3E6C1F#,
      16#1F83D9ABFB41BD6B#, 16#5BE0CD19137E2179#);

   type Digest is record
      H       : State_Array := Init;
      Buf     : array (Natural range 0 .. Block_Len - 1) of Character :=
                  (others => Character'Val (0));
      Buf_Len : Natural := 0;
      Len     : Unsigned_64 := 0;  --  total bytes written
   end record;

end Gada.Std.Crypto.Sha512;
