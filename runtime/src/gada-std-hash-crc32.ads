--  Gada.Std.Hash.Crc32 — the Go `hash/crc32` package, ported (Phase 8).
--
--  Polynomials are in LSB-first (reflected) form, as in Go. The table
--  and update loop are the textbook reflected CRC:
--    Update(crc, tab, p): crc = not crc; per byte
--      crc := tab((crc xor b) and 16#FF#) xor (crc >> 8); return not crc.
--  Checksum(data, tab) = Update(0, tab, data).
--
--  Naming: the compiler maps Go names through goNameToAdaMember, so
--  ChecksumIEEE → Checksum_IEEE, MakeTable → Make_Table, and the
--  polynomial constants IEEE / Castagnoli / Koopman map unchanged
--  (all-caps initialisms stay whole).

with Gada.Std.Bytes;
with Interfaces;

package Gada.Std.Hash.Crc32 is

   use Interfaces;

   type Table is array (Natural range 0 .. 255) of Unsigned_32;

   --  Reflected polynomial constants (Go: crc32.IEEE etc.).
   IEEE       : constant Unsigned_32 := 16#EDB88320#;
   Castagnoli : constant Unsigned_32 := 16#82F63B78#;
   Koopman    : constant Unsigned_32 := 16#EB31D82E#;

   --  Go: func MakeTable(poly uint32) *Table — build the reflected
   --  table. Returned by value (1 KiB); Go's *Table pointer is an
   --  implementation detail.
   function Make_Table (Poly : Unsigned_32) return Table;

   --  Go: func Update(crc uint32, tab *Table, p []byte) uint32.
   function Update
     (Crc : Unsigned_32; Tab : Table; Data : Gada.Std.Bytes.Byte_Slice)
      return Unsigned_32;

   --  Go: func Checksum(data []byte, tab *Table) uint32.
   function Checksum
     (Data : Gada.Std.Bytes.Byte_Slice; Tab : Table) return Unsigned_32;

   --  Go: func ChecksumIEEE(data []byte) uint32 — the IEEE table is
   --  package-level (Go: var IEEETable), built once here.
   function Checksum_IEEE (Data : Gada.Std.Bytes.Byte_Slice)
      return Unsigned_32;

end Gada.Std.Hash.Crc32;
