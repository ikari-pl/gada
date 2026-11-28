--  AUnit suite for `Gada.Std.Encoding.*` (the Go `encoding/base64`,
--  `encoding/hex`, `encoding/binary` ports, Phase 8 wave 4 item 5).
--
--  All expected values pinned from Go 1.27 via `go run`: base64
--  std/URL/raw/raw-URL over inputs of length 0..8 plus bytes that
--  exercise the URL alphabet (0xfb 0xff ...), hex round-trips, fixed
--  width uint16/32/64 in both endians, and uvarint/varint (zigzag)
--  boundary values. Error paths (illegal base64 char, raw padding,
--  odd/invalid hex, uvarint overflow/truncation, short read buffer)
--  raise CONSTRAINT_ERROR.

with AUnit;
with AUnit.Test_Cases;

package Std_Encoding_Suite is

   type Std_Encoding_Test is new AUnit.Test_Cases.Test_Case
     with null record;

   overriding procedure Register_Tests (T : in out Std_Encoding_Test);
   overriding function  Name (T : Std_Encoding_Test)
      return AUnit.Message_String;

   procedure Test_Base64 (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Hex (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Binary (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Errors (T : in out AUnit.Test_Cases.Test_Case'Class);

end Std_Encoding_Suite;
