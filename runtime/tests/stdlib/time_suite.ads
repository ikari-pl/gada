--  AUnit suite for `Gada.Std.Time` (Go `time` port, Phase 6).
--
--  Covers Duration arithmetic + String (pinned to Go's output),
--  Now/Since monotonic elapsed, Date + calendar accessors, UTC/Local
--  zone formatting, and After/NewTimer/Tick via goroutines.

with AUnit;
with AUnit.Test_Cases;

package Time_Suite is

   type Time_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Time_Test);
   overriding function  Name (T : Time_Test) return AUnit.Message_String;

   procedure Test_Duration_String (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Duration_Arith (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Now_Since (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Date_Accessors (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_UTC_Local_Format (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_After (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Timer_Stop (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Tick (T : in out AUnit.Test_Cases.Test_Case'Class);

end Time_Suite;
