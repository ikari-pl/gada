--  AUnit suite for `Gada.Std.OS` (Go `os` port, Phase 5 wave 1).
--
--  Covers os.ReadFile's contract: full contents returned as a byte
--  slice, empty file gives an empty slice with a nil error, and a
--  missing file gives an empty slice plus a non-nil error.

with AUnit;
with AUnit.Test_Cases;

package OS_Suite is

   type OS_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out OS_Test);
   overriding function  Name (T : OS_Test) return AUnit.Message_String;

   procedure Test_Read_File_Ok (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Read_File_Empty (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Read_File_Missing (T : in out
      AUnit.Test_Cases.Test_Case'Class);

end OS_Suite;
