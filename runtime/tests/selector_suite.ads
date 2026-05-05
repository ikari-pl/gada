--  AUnit suite for Gada.Async.Selector.
--
--  Phase 3 item 6 surface. Each test pins one Go-spec semantic of
--  the select statement: pick a ready case, fairness across
--  multiple ready cases, default fires when nothing ready, timeout
--  fires after the deadline, blocks until ready, error on empty /
--  multiple-default cases.

with AUnit;
with AUnit.Test_Cases;

package Selector_Suite is

   type Selector_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Selector_Test);
   overriding function  Name (T : Selector_Test) return AUnit.Message_String;

   procedure Test_Default_Fires_When_Nothing_Ready
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Recv_Wins_When_Buffer_Has_Value
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Send_Wins_When_Buffer_Has_Slot
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Recv_From_Closed_Channel_Yields_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Timeout_Fires_When_Nothing_Else_Ready
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Random_Tiebreak_Across_Many_Trials
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Empty_Case_Array_Raises_Selector_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Two_Defaults_Raises_Selector_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Recv_With_Null_Output_Pointers_Discards
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Blocks_Until_Sibling_Sends
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_More_Than_Max_Cases_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Selector_Suite;
