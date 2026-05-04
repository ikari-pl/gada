--  AUnit suite for Gada.Async.Channels.Bounded.
--
--  Phase 3 item 4 surface. Each test pins one Go-spec semantic so a
--  regression points at the missing invariant rather than a generic
--  "channels broken." Where a test name uses a specific cap or count,
--  the choice is the smallest value that makes the property
--  observable — e.g. cap=1 + 2 senders is the minimum to surface the
--  blocking-when-full case.

with AUnit;
with AUnit.Test_Cases;

package Channels_Suite is

   type Channels_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Channels_Test);
   overriding function  Name (T : Channels_Test) return AUnit.Message_String;

   procedure Test_Make_Capacity_And_Length
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Send_Receive_Buffered
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Receive_From_Empty_Closed_Returns_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Send_On_Closed_Channel_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Close_Twice_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Receive_After_Drain_Returns_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Send_Blocks_When_Full_Then_Receive_Unblocks
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Receive_Blocks_When_Empty_Then_Send_Unblocks
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Close_Wakes_Parked_Receivers_With_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_FIFO_Across_Multiple_Senders
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Length_And_Is_Closed_Reflect_State
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_No_Channel_Operations_Raise_Constraint_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Current_Returns_No_Goroutine_From_Main_Task
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Close_While_Sender_Parked_Raises_Channel_Closed
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Channels_Suite;
