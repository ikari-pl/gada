--  AUnit suite for Gada.Async.Channels.Unbounded.
--
--  Phase 3 item 5 surface. Same test-shape pattern as the bounded
--  suite (channels_suite.{ads,adb}); each test pins one Go-spec
--  semantic so a regression points at the missing invariant. Where
--  bounded gates "buffer-full blocking" (cap=1 + 2 senders), this
--  suite gates the inverse — Send NEVER blocks, regardless of how
--  many values are pending — plus the receiver-blocks-when-empty
--  symmetric case.

with AUnit;
with AUnit.Test_Cases;

package Channels_Unbounded_Suite is

   type Channels_Unbounded_Test is
     new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests
     (T : in out Channels_Unbounded_Test);
   overriding function  Name
     (T : Channels_Unbounded_Test) return AUnit.Message_String;

   procedure Test_Make_Length_Starts_At_Zero
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Send_Many_Without_Receiver_Never_Blocks
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Send_Receive_FIFO_Order
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Receive_From_Empty_Closed_Returns_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Send_On_Closed_Channel_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Close_Twice_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Receive_After_Drain_Returns_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Receive_Blocks_When_Empty_Then_Send_Unblocks
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Close_Wakes_Parked_Receivers_With_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Length_And_Is_Closed_Reflect_State
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_No_Channel_Operations_Raise_Constraint_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Send_During_Receiver_Park_Hands_Off_Directly
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Receive_Park_From_Non_Goroutine_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Channels_Unbounded_Suite;
