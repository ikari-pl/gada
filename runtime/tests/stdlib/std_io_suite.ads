--  AUnit suite for `Gada.Std.IO` (Go `io` port, Phase 5).
--
--  Uses small in-memory Reader/Writer doubles deriving from the
--  abstract tagged IO.Reader / IO.Writer to verify dispatch, the EOF
--  sentinel, and Copy/Read_All semantics including hard read/write
--  errors.

with AUnit;
with AUnit.Test_Cases;

package Std_IO_Suite is

   type Std_IO_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Std_IO_Test);
   overriding function  Name (T : Std_IO_Test) return AUnit.Message_String;

   procedure Test_EOF_Sentinel (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Copy (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Copy_Empty (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Copy_Read_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Copy_Write_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Read_All (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Read_All_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class);

end Std_IO_Suite;
