--  AUnit suite for `Gada.Std.Hash.*` (Go `hash/crc32`, `hash/crc64`,
--  `hash/fnv`, `hash/adler32` ports, Phase 8 wave 4 item 1).
--
--  Every expected value is pinned from Go 1.27 (`go run`), including
--  the classic check values: CRC-32/IEEE "123456789" = 16#CBF43926#,
--  CRC-64/ECMA = 16#995DC9BBDF1939FA#, ISO = 16#B90956C775A41001#.

with AUnit;
with AUnit.Test_Cases;

package Std_Hash_Suite is

   type Std_Hash_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Std_Hash_Test);
   overriding function  Name (T : Std_Hash_Test) return AUnit.Message_String;

   procedure Test_Crc32_Vectors (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Crc32_Update_Split (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Crc64_Vectors (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Adler32_Vectors (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Fnv32 (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Fnv64 (T : in out AUnit.Test_Cases.Test_Case'Class);

end Std_Hash_Suite;
