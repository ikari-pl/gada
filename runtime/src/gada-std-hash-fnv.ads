--  Gada.Std.Hash.Fnv — the Go `hash/fnv` package, ported (Phase 8).
--
--  Go returns the hash.Hash32/Hash64 interfaces from New32/New64/...;
--  v1 returns the concrete state records instead (the hash.Hash
--  interface port is a later item). Write/Sum/Sum32/Sum64/Reset/Size
--  are primitive operations, so `h.Write (b)` on a local h keeps its
--  Go shape once the compiler maps the fnv types.
--
--  FNV-1:  h := h * prime; h := h xor b.
--  FNV-1a: h := h xor b;   h := h * prime.

with Gada.Std.Bytes;
with Interfaces;

package Gada.Std.Hash.Fnv is

   use Interfaces;

   type Hash32 is limited private;
   type Hash64 is limited private;

   --  Go: fnv.New32() / New32a() / New64() / New64a().
   function New32 return Hash32;    --  FNV-1
   function New32a return Hash32;   --  FNV-1a
   function New64 return Hash64;    --  FNV-1
   function New64a return Hash64;   --  FNV-1a

   --  Go: h.Write(p) (io.Writer) — returns (len p, nil error); v1 is a
   --  procedure, the error half is always nil.
   procedure Write (H : in out Hash32; Data : Gada.Std.Bytes.Byte_Slice);
   procedure Write (H : in out Hash64; Data : Gada.Std.Bytes.Byte_Slice);

   --  Go: h.Sum32() / h.Sum64() (hash.Hash32/64).
   function Sum32 (H : Hash32) return Unsigned_32;
   function Sum64 (H : Hash64) return Unsigned_64;

   --  Go: h.Sum(b) []byte — appends the big-endian sum bytes.
   function Sum (H : Hash32; B : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;
   function Sum (H : Hash64; B : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;

   --  Go: h.Reset() and h.Size() int.
   procedure Reset (H : in out Hash32);
   procedure Reset (H : in out Hash64);
   function Size (H : Hash32) return Natural;
   function Size (H : Hash64) return Natural;

private

   Offset32 : constant Unsigned_32 := 16#811C9DC5#;
   Prime32  : constant Unsigned_32 := 16#01000193#;
   Offset64 : constant Unsigned_64 := 16#CBF29CE484222325#;
   Prime64  : constant Unsigned_64 := 16#100000001B3#;

   type Hash32 is record
      State : Unsigned_32 := Offset32;
      A     : Boolean := False;  --  False = FNV-1, True = FNV-1a
   end record;

   type Hash64 is record
      State : Unsigned_64 := Offset64;
      A     : Boolean := False;
   end record;

end Gada.Std.Hash.Fnv;
