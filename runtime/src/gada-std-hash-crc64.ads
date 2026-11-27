--  Gada.Std.Hash.Crc64 — the Go `hash/crc64` package, ported (Phase 8).
--
--  Same reflected-table scheme as Crc32, 64-bit wide. Polynomial
--  constants are the reflected forms Go uses: ECMA =
--  16#C96C5795D7870F42#, ISO = 16#D800000000000000#.

with Gada.Std.Bytes;
with Interfaces;

package Gada.Std.Hash.Crc64 is

   use Interfaces;

   type Table is array (Natural range 0 .. 255) of Unsigned_64;

   ECMA : constant Unsigned_64 := 16#C96C5795D7870F42#;
   ISO  : constant Unsigned_64 := 16#D800000000000000#;

   --  Go: func MakeTable(poly uint64) *Table.
   function Make_Table (Poly : Unsigned_64) return Table;

   --  Go: func Update(crc uint64, tab *Table, p []byte) uint64.
   function Update
     (Crc : Unsigned_64; Tab : Table; Data : Gada.Std.Bytes.Byte_Slice)
      return Unsigned_64;

   --  Go: func Checksum(data []byte, tab *Table) uint64.
   function Checksum
     (Data : Gada.Std.Bytes.Byte_Slice; Tab : Table) return Unsigned_64;

end Gada.Std.Hash.Crc64;
