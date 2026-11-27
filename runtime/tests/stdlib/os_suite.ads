--  AUnit suite for `Gada.Std.OS` (Go `os` port, Phase 5 wave 1 +
--  Phase 6 wave 2).
--
--  Wave 1 covers os.ReadFile's contract: full contents returned as a
--  byte slice, empty file gives an empty slice with a nil error, and
--  a missing file gives an empty slice plus a non-nil error.
--
--  Wave 2 covers Args, Get_Env/Lookup_Env/Set_Env (incl. Go's
--  invalid-key rejection), Open on a missing file, Create + Write +
--  Close round-tripped through ReadFile, Stat on file/dir/missing,
--  and Mkdir incl. the already-exists error.

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
   procedure Test_Args (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Env (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Open_Ok (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Open_Missing (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Create_Write_Stat (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Stat_Dir_And_Missing (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Mkdir (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Read_File_Dir (T : in out
      AUnit.Test_Cases.Test_Case'Class);

end OS_Suite;
