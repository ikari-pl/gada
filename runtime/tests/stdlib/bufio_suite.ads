--  AUnit suite for `Gada.Std.Bufio` (Go `bufio` port, Phase 5).
--
--  In-memory IO.Reader/Writer doubles drive the buffered Reader
--  (chunk reads, ReadLine incl. CR stripping / long-line prefixes /
--  EOF, ReadString with delim and at-EOF), the buffered Writer
--  (auto-flush, Flush, error propagation), and the line Scanner.

with AUnit;
with AUnit.Test_Cases;

package Bufio_Suite is

   type Bufio_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Bufio_Test);
   overriding function  Name (T : Bufio_Test) return AUnit.Message_String;

   procedure Test_Reader_Read (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Read_Line (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Read_Line_Long (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Read_String (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Read_Hard_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Scanner (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Scanner_Long_And_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Writer (T : in out AUnit.Test_Cases.Test_Case'Class);

end Bufio_Suite;
