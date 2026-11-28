--  AUnit suite for `Gada.Std.Encoding.Csv` / `.Xml` (the Go
--  `encoding/csv` and `encoding/xml` ports, Phase 8 wave 4 item 6).
--
--  All expected values pinned from Go 1.27 via `go run` (JSON vectors):
--  CSV parse/write round-trips incl. quoted fields, embedded commas,
--  quotes, newlines and CRLF; field-count-mismatch error. XML
--  Escape_Text vectors, tree unmarshal, Go-style canonical marshal,
--  malformed-document errors.

with AUnit;
with AUnit.Test_Cases;

package Std_Encoding_Text_Suite is

   type Std_Encoding_Text_Test is new AUnit.Test_Cases.Test_Case
     with null record;

   overriding procedure Register_Tests (T : in out Std_Encoding_Text_Test);
   overriding function  Name (T : Std_Encoding_Text_Test)
      return AUnit.Message_String;

   procedure Test_Csv_Read (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Csv_Write (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Csv_Errors (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Xml_Escape (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Xml_Unmarshal (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Xml_Marshal (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Xml_Errors (T : in out AUnit.Test_Cases.Test_Case'Class);

end Std_Encoding_Text_Suite;
