--  Gada.Std.Encoding.Binary — the Go `encoding/binary` package,
--  ported (Phase 8 wave 4, item 5). Fixed-width integers in big- or
--  little-endian byte order, plus uvarint/varint (Go's Uvarint /
--  Varint with zigzag for signed values).
--
--  Go: binary.BigEndian.PutUint16(buf, v) / Uint16(buf) etc. v1:
--  Encode_* return a fresh slice, Append_* write into a buffer, and
--  Uint*_BE/LE read (raising CONSTRAINT_ERROR on a short buffer).
--  Uvarint/Varint return N = 0 on an empty buffer and raise
--  CONSTRAINT_ERROR on overflow or a truncated varint (Go's n <= 0
--  error half).

with Gada.Std.Bytes;
with Interfaces;

package Gada.Std.Encoding.Binary is

   use Interfaces;

   --  Fixed-width, big-endian.
   function Encode_Uint16_BE (V : Unsigned_16) return Gada.Std.Bytes.Byte_Slice;
   function Encode_Uint32_BE (V : Unsigned_32) return Gada.Std.Bytes.Byte_Slice;
   function Encode_Uint64_BE (V : Unsigned_64) return Gada.Std.Bytes.Byte_Slice;
   --  Fixed-width, little-endian.
   function Encode_Uint16_LE (V : Unsigned_16) return Gada.Std.Bytes.Byte_Slice;
   function Encode_Uint32_LE (V : Unsigned_32) return Gada.Std.Bytes.Byte_Slice;
   function Encode_Uint64_LE (V : Unsigned_64) return Gada.Std.Bytes.Byte_Slice;

   procedure Append_Uint16_BE (Buf : in out Gada.Std.Bytes.Byte_Slice;
                               V : Unsigned_16);
   procedure Append_Uint32_BE (Buf : in out Gada.Std.Bytes.Byte_Slice;
                               V : Unsigned_32);
   procedure Append_Uint64_BE (Buf : in out Gada.Std.Bytes.Byte_Slice;
                               V : Unsigned_64);
   procedure Append_Uint16_LE (Buf : in out Gada.Std.Bytes.Byte_Slice;
                               V : Unsigned_16);
   procedure Append_Uint32_LE (Buf : in out Gada.Std.Bytes.Byte_Slice;
                               V : Unsigned_32);
   procedure Append_Uint64_LE (Buf : in out Gada.Std.Bytes.Byte_Slice;
                               V : Unsigned_64);

   function Uint16_BE (B : Gada.Std.Bytes.Byte_Slice) return Unsigned_16;
   function Uint32_BE (B : Gada.Std.Bytes.Byte_Slice) return Unsigned_32;
   function Uint64_BE (B : Gada.Std.Bytes.Byte_Slice) return Unsigned_64;
   function Uint16_LE (B : Gada.Std.Bytes.Byte_Slice) return Unsigned_16;
   function Uint32_LE (B : Gada.Std.Bytes.Byte_Slice) return Unsigned_32;
   function Uint64_LE (B : Gada.Std.Bytes.Byte_Slice) return Unsigned_64;

   --  Go: binary.PutUvarint / binary.Uvarint.
   procedure Append_Uvarint (Buf : in out Gada.Std.Bytes.Byte_Slice;
                             V : Unsigned_64);
   procedure Uvarint (B : Gada.Std.Bytes.Byte_Slice; V : out Unsigned_64;
                      N : out Natural);

   --  Go: binary.PutVarint / binary.Varint (zigzag).
   procedure Append_Varint (Buf : in out Gada.Std.Bytes.Byte_Slice;
                            V : Integer_64);
   procedure Varint (B : Gada.Std.Bytes.Byte_Slice; V : out Integer_64;
                     N : out Natural);

end Gada.Std.Encoding.Binary;
