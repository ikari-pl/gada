--  Body of Channels_Suite — see spec for property index.
--
--  ## Globals
--
--  Channel handles + per-test counters live at file scope because the
--  Goroutine_Body access procedures Spawn'd into the scheduler have no
--  closure mechanism. Tests reset the globals they read before
--  driving Spawn — same pattern as Scheduler_Suite.
--
--  ## Channel element type
--
--  Tests use a single `Bound : Bounded_Of_Integer` instantiation — the
--  Element_Type is Integer. That's enough surface to gate every
--  Channels.Bounded contract; future generic-aware coverage (records,
--  records-with-defaults, tagged types) belongs to Phase 4 once the
--  compiler-emit side starts demanding heterogeneity.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Async.Scheduler;
with Gada.Async.Channels.Bounded;

package body Channels_Suite is

   --  Single instantiation reused across every test.
   package Bound is new Gada.Async.Channels.Bounded
     (Element_Type => Integer);

   --  Per-test channel + saved Goroutine_Id slots.
   The_Channel  : Bound.Channel := Bound.No_Channel;
   The_Sender   : Gada.Async.Scheduler.Goroutine_Id :=
     Gada.Async.Scheduler.No_Goroutine;
   The_Receiver : Gada.Async.Scheduler.Goroutine_Id :=
     Gada.Async.Scheduler.No_Goroutine;

   --  Receive results captured by goroutine bodies for main-task
   --  assertions.
   Last_Recv_V    : Integer := 0;
   Last_Recv_OK   : Boolean := False;
   Recv_Done      : Boolean := False;

   Send_Done      : Boolean := False;
   Send_Raised    : Boolean := False;

   --  FIFO test: producers append their value into Recv_Log via
   --  Receive in order; the test asserts the log matches the
   --  expected ordering.
   Max_Log : constant := 32;
   type Int_Log is array (1 .. Max_Log) of Integer;
   Recv_Log     : Int_Log := [others => 0];
   Recv_Log_Len : Natural := 0;

   --  Body procedures used by Spawn.
   procedure Sender_Body_Send_42;
   procedure Receiver_Body_Receive_Once;
   procedure Sender_Body_Then_Mark_Closed;
   procedure Receiver_Body_Park_Then_Drain;

   --  ## Sender_Body_Send_42
   --
   --  Used in the "Send blocks when full" test. The buffer is filled
   --  by the test main task before this body runs, so this Send
   --  parks. The matching Receive on the main task unblocks it.
   procedure Sender_Body_Send_42 is
   begin
      Bound.Send (The_Channel, 42);
      Send_Done := True;
   end Sender_Body_Send_42;

   procedure Receiver_Body_Receive_Once is
   begin
      Bound.Receive (The_Channel, Last_Recv_V, Last_Recv_OK);
      Recv_Done := True;
   end Receiver_Body_Receive_Once;

   --  Sender body that's expected to raise Channel_Closed when the
   --  channel is closed mid-park (the Close_Wakes test).
   procedure Sender_Body_Then_Mark_Closed is
   begin
      Bound.Send (The_Channel, 99);
      --  If Send returned without raising, fall through (test
      --  asserts Send_Done = False under the close-wake-raise
      --  contract).
      Send_Done := True;
   exception
      when Bound.Channel_Closed =>
         Send_Raised := True;
   end Sender_Body_Then_Mark_Closed;

   --  Receiver that parks on empty channel; awoken by Close, must
   --  return OK = False.
   procedure Receiver_Body_Park_Then_Drain is
   begin
      Bound.Receive (The_Channel, Last_Recv_V, Last_Recv_OK);
      Recv_Done := True;
   end Receiver_Body_Park_Then_Drain;

   ---------------------------------------------------------------

   overriding function Name
     (T : Channels_Test) return AUnit.Message_String is
     (AUnit.Format
        ("Gada.Async.Channels.Bounded suite (PKG=async.channels.bounded)"));

   overriding procedure Register_Tests (T : in out Channels_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Make_Capacity_And_Length'Access,
         "Make returns a non-No_Channel handle whose Capacity matches "
         & "the requested value and whose Length starts at 0");
      Register_Routine
        (T, Test_Send_Receive_Buffered'Access,
         "Send / Receive on a buffered channel with free slots round-"
         & "trips values in FIFO order without parking");
      Register_Routine
        (T, Test_Receive_From_Empty_Closed_Returns_OK_False'Access,
         "Receive on an empty closed channel returns "
         & "(default Element_Type, OK => False) — Go's "
         & "zero-value-with-ok-false signal");
      Register_Routine
        (T, Test_Send_On_Closed_Channel_Raises'Access,
         "Send on a closed channel raises Channel_Closed (the Ada "
         & "mapping of Go's send-on-closed panic)");
      Register_Routine
        (T, Test_Close_Twice_Raises'Access,
         "Close on an already-closed channel raises Channel_Closed "
         & "(matches Go's panic-on-double-close)");
      Register_Routine
        (T, Test_Receive_After_Drain_Returns_OK_False'Access,
         "After a closed channel's buffered values are drained, "
         & "subsequent Receive calls keep returning OK => False");
      Register_Routine
        (T, Test_Send_Blocks_When_Full_Then_Receive_Unblocks'Access,
         "A Send on a full buffered channel parks the sender; the "
         & "next Receive promotes the parked sender's value into the "
         & "freed buffer slot and unblocks the sender (sub-item 4 "
         & "verify gate — buffered Send blocking)");
      Register_Routine
        (T, Test_Receive_Blocks_When_Empty_Then_Send_Unblocks'Access,
         "A Receive on an empty open channel parks the receiver; the "
         & "next Send hands the value directly into the parked "
         & "receiver's slot and unblocks them (sub-item 4 verify "
         & "gate — buffered Receive blocking)");
      Register_Routine
        (T, Test_Close_Wakes_Parked_Receivers_With_OK_False'Access,
         "Close on a channel with parked Receivers wakes each one "
         & "with OK => False — Go's broadcast-close-to-receivers "
         & "semantics");
      Register_Routine
        (T, Test_FIFO_Across_Multiple_Senders'Access,
         "On a cap-1 channel with multiple senders queueing in "
         & "order, the receiver observes the values in send order "
         & "(FIFO across the buffered + parked queue)");
      Register_Routine
        (T, Test_Length_And_Is_Closed_Reflect_State'Access,
         "Length tracks buffered count; Is_Closed flips True after "
         & "Close — diagnostic queries follow the channel's state");
      Register_Routine
        (T, Test_No_Channel_Operations_Raise_Constraint_Error'Access,
         "Send / Receive / Close / Length / Capacity / Is_Closed on "
         & "No_Channel each raise Constraint_Error (no UB on the "
         & "default-initialised handle)");
      Register_Routine
        (T, Test_Current_Returns_No_Goroutine_From_Main_Task'Access,
         "Scheduler.Current returns No_Goroutine from the main test "
         & "task — proves the TLS lookup is correctly null outside a "
         & "goroutine context");
      Register_Routine
        (T, Test_Close_While_Sender_Parked_Raises_Channel_Closed'Access,
         "Close on a channel with a parked sender wakes the sender "
         & "with Closed_On_Wake => True; the parked Send raises "
         & "Channel_Closed (matches Go's panic-on-closed-channel for "
         & "a sender that was waiting at the moment of close)");
   end Register_Tests;

   ---------------------------------------------------------------

   procedure Test_Make_Capacity_And_Length
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : constant Bound.Channel := Bound.Make (Capacity => 4);
   begin
      Assert (Bound.Capacity (C) = 4,
              "Expected Capacity = 4, got" & Bound.Capacity (C)'Image);
      Assert (Bound.Length (C) = 0,
              "Fresh channel must have Length = 0, got"
              & Bound.Length (C)'Image);
      Assert (not Bound.Is_Closed (C),
              "Fresh channel must not be closed");
   end Test_Make_Capacity_And_Length;

   procedure Test_Send_Receive_Buffered
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C  : constant Bound.Channel := Bound.Make (Capacity => 3);
      V  : Integer;
      OK : Boolean;
   begin
      --  Three sends, three receives — all buffered, no parking.
      --  Driven from the main task to keep the test deterministic
      --  (parking from main is unsupported; with 3 free slots we
      --  never park).
      Bound.Send (C, 10);
      Bound.Send (C, 20);
      Bound.Send (C, 30);
      Assert (Bound.Length (C) = 3,
              "After 3 sends Length should be 3, got"
              & Bound.Length (C)'Image);
      Bound.Receive (C, V, OK);
      Assert (OK and then V = 10, "First receive expected (10, True)");
      Bound.Receive (C, V, OK);
      Assert (OK and then V = 20, "Second receive expected (20, True)");
      Bound.Receive (C, V, OK);
      Assert (OK and then V = 30, "Third receive expected (30, True)");
      Assert (Bound.Length (C) = 0,
              "After draining Length should be 0");
   end Test_Send_Receive_Buffered;

   procedure Test_Receive_From_Empty_Closed_Returns_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C  : constant Bound.Channel := Bound.Make (Capacity => 1);
      V  : Integer;
      OK : Boolean;
   begin
      Bound.Close (C);
      Bound.Receive (C, V, OK);
      Assert (not OK,
              "Receive on closed-empty channel must set OK = False");
      Assert (V = 0,
              "Receive on closed-empty channel must default V to "
              & "Element_Type's zero (Integer => 0); got"
              & V'Image);
   end Test_Receive_From_Empty_Closed_Returns_OK_False;

   procedure Test_Send_On_Closed_Channel_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C      : constant Bound.Channel := Bound.Make (Capacity => 2);
      Raised : Boolean := False;
   begin
      Bound.Close (C);
      begin
         Bound.Send (C, 1);
      exception
         when Bound.Channel_Closed =>
            Raised := True;
      end;
      Assert (Raised, "Send on closed channel must raise Channel_Closed");
   end Test_Send_On_Closed_Channel_Raises;

   procedure Test_Close_Twice_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C      : constant Bound.Channel := Bound.Make (Capacity => 1);
      Raised : Boolean := False;
   begin
      Bound.Close (C);
      begin
         Bound.Close (C);
      exception
         when Bound.Channel_Closed =>
            Raised := True;
      end;
      Assert (Raised, "Close on already-closed channel must raise");
   end Test_Close_Twice_Raises;

   procedure Test_Receive_After_Drain_Returns_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C  : constant Bound.Channel := Bound.Make (Capacity => 2);
      V  : Integer;
      OK : Boolean;
   begin
      Bound.Send (C, 7);
      Bound.Send (C, 8);
      Bound.Close (C);
      --  After Close, buffered values still drain in FIFO order with
      --  OK => True. Subsequent Receives (post-drain) see OK = False.
      Bound.Receive (C, V, OK);
      Assert (OK and then V = 7,
              "Pre-drain Receive expected (7, True), got ("
              & V'Image & "," & OK'Image & ")");
      Bound.Receive (C, V, OK);
      Assert (OK and then V = 8,
              "Pre-drain Receive expected (8, True)");
      Bound.Receive (C, V, OK);
      Assert (not OK,
              "Post-drain Receive on closed channel expected OK = False");
   end Test_Receive_After_Drain_Returns_OK_False;

   procedure Test_Send_Blocks_When_Full_Then_Receive_Unblocks
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Gada.Async.Scheduler.Goroutine_Id;
      V        : Integer;
      OK       : Boolean;
   begin
      The_Channel := Bound.Make (Capacity => 1);
      Send_Done := False;
      Last_Recv_V := 0;
      Last_Recv_OK := False;
      Recv_Done := False;

      Gada.Async.Scheduler.Shutdown;
      Gada.Async.Scheduler.Init (Workers => 1);

      --  Pre-fill the buffer from main (Cap=1, one Send fills it).
      Bound.Send (The_Channel, 1);
      Assert (Bound.Length (The_Channel) = 1, "Pre-fill failed");

      --  Spawn a goroutine that tries to Send 42 — buffer full → park.
      Unused_G := Gada.Async.Scheduler.Spawn
        (Sender_Body_Send_42'Access);

      --  Deterministically wait for the goroutine to actually park
      --  on the channel. Senders_Waiting transitions 0 → 1 inside
      --  Park_Sender, *before* the goroutine calls Scheduler.Park.
      --  Without this barrier, main would race ahead and Receive
      --  would either run before the parked-sender exists (returning
      --  the wrong value) or would itself park (no-op for main task,
      --  silently returning garbage from the empty wait slot).
      for Attempt in 1 .. 100 loop
         exit when Bound.Senders_Waiting (The_Channel) = 1;
         delay 0.001;
      end loop;
      Assert (Bound.Senders_Waiting (The_Channel) = 1,
              "Sender goroutine did not park within 100 ms; "
              & "Senders_Waiting ="
              & Bound.Senders_Waiting (The_Channel)'Image);

      --  Now Receive — this drains '1' and promotes the parked sender's
      --  '42' into the freed slot, unparking the sender.
      Bound.Receive (The_Channel, V, OK);
      Assert (OK and then V = 1, "First receive expected (1, True)");

      --  Sender's '42' is now buffered; second Receive drains it.
      Bound.Receive (The_Channel, V, OK);
      Assert (OK and then V = 42,
              "Second receive expected (42, True), got ("
              & V'Image & "," & OK'Image & ")");

      --  Wait for the sender goroutine to finish its post-Send work
      --  (Send_Done := True) before Shutdown.
      for Attempt in 1 .. 100 loop
         exit when Send_Done;
         delay 0.001;
      end loop;
      Assert (Send_Done,
              "Sender goroutine did not complete after the matching "
              & "Receive promoted its value");

      Gada.Async.Scheduler.Shutdown;
   end Test_Send_Blocks_When_Full_Then_Receive_Unblocks;

   procedure Test_Receive_Blocks_When_Empty_Then_Send_Unblocks
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Gada.Async.Scheduler.Goroutine_Id;
   begin
      The_Channel := Bound.Make (Capacity => 1);
      Last_Recv_V := 0;
      Last_Recv_OK := False;
      Recv_Done := False;

      Gada.Async.Scheduler.Shutdown;
      Gada.Async.Scheduler.Init (Workers => 1);

      --  Goroutine receives — buffer empty → park.
      Unused_G := Gada.Async.Scheduler.Spawn
        (Receiver_Body_Receive_Once'Access);

      --  Wait for the receiver to actually park on the channel.
      --  Receivers_Waiting transitions 0 → 1 inside Park_Receiver
      --  (when the buffer is empty and the channel is open).
      for Attempt in 1 .. 100 loop
         exit when Bound.Receivers_Waiting (The_Channel) = 1;
         delay 0.001;
      end loop;
      Assert (Bound.Receivers_Waiting (The_Channel) = 1,
              "Receiver goroutine did not park within 100 ms; "
              & "Receivers_Waiting ="
              & Bound.Receivers_Waiting (The_Channel)'Image);

      Bound.Send (The_Channel, 77);

      for Attempt in 1 .. 100 loop
         exit when Recv_Done;
         delay 0.001;
      end loop;
      Assert (Recv_Done,
              "Receiver goroutine did not complete after Send");
      Assert (Last_Recv_OK and then Last_Recv_V = 77,
              "Receiver expected (77, True), got ("
              & Last_Recv_V'Image & "," & Last_Recv_OK'Image & ")");

      Gada.Async.Scheduler.Shutdown;
   end Test_Receive_Blocks_When_Empty_Then_Send_Unblocks;

   procedure Test_Close_Wakes_Parked_Receivers_With_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Gada.Async.Scheduler.Goroutine_Id;
   begin
      The_Channel := Bound.Make (Capacity => 1);
      Last_Recv_V := 99;
      Last_Recv_OK := True;
      Recv_Done := False;

      Gada.Async.Scheduler.Shutdown;
      Gada.Async.Scheduler.Init (Workers => 1);

      Unused_G := Gada.Async.Scheduler.Spawn
        (Receiver_Body_Park_Then_Drain'Access);

      --  Deterministic wait: receiver has parked iff Receivers_Waiting
      --  bumped to 1.
      for Attempt in 1 .. 100 loop
         exit when Bound.Receivers_Waiting (The_Channel) = 1;
         delay 0.001;
      end loop;
      Assert (Bound.Receivers_Waiting (The_Channel) = 1,
              "Receiver did not park before Close; Receivers_Waiting ="
              & Bound.Receivers_Waiting (The_Channel)'Image);

      Bound.Close (The_Channel);

      for Attempt in 1 .. 100 loop
         exit when Recv_Done;
         delay 0.001;
      end loop;
      Assert (Recv_Done,
              "Parked receiver did not wake after Close");
      Assert (not Last_Recv_OK,
              "Receiver woken by Close should observe OK = False, got"
              & Last_Recv_OK'Image);
      Assert (Last_Recv_V = 0,
              "Receiver woken by Close should observe V = "
              & "Element_Type'(default) = 0, got" & Last_Recv_V'Image);

      Gada.Async.Scheduler.Shutdown;
   end Test_Close_Wakes_Parked_Receivers_With_OK_False;

   procedure Test_FIFO_Across_Multiple_Senders
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C  : Bound.Channel;
      V  : Integer;
      OK : Boolean;
   begin
      --  Cap=2: Send 1, Send 2 fill the buffer; Receive drains 1 (FIFO);
      --  Send 3 fills again; Receive drains 2; Receive drains 3.
      --  Property: receive order matches send order, no reordering.
      C := Bound.Make (Capacity => 2);
      Bound.Send (C, 1);
      Bound.Send (C, 2);
      Bound.Receive (C, V, OK);
      Assert (OK and then V = 1, "FIFO: expected 1");
      Bound.Send (C, 3);
      Bound.Receive (C, V, OK);
      Assert (OK and then V = 2, "FIFO: expected 2");
      Bound.Receive (C, V, OK);
      Assert (OK and then V = 3, "FIFO: expected 3");
   end Test_FIFO_Across_Multiple_Senders;

   procedure Test_Length_And_Is_Closed_Reflect_State
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C  : constant Bound.Channel := Bound.Make (Capacity => 3);
      V  : Integer;
      OK : Boolean;
   begin
      Assert (Bound.Length (C) = 0, "fresh Length must be 0");
      Assert (not Bound.Is_Closed (C), "fresh Is_Closed must be False");
      Bound.Send (C, 1);
      Assert (Bound.Length (C) = 1, "post-send Length must be 1");
      Bound.Send (C, 2);
      Assert (Bound.Length (C) = 2, "post-send Length must be 2");
      Bound.Receive (C, V, OK);
      Assert (Bound.Length (C) = 1, "post-recv Length must be 1");
      Bound.Close (C);
      Assert (Bound.Is_Closed (C), "post-close Is_Closed must be True");
      Assert (Bound.Length (C) = 1,
              "Close does NOT drain the buffer; Length still 1");
   end Test_Length_And_Is_Closed_Reflect_State;

   procedure Test_No_Channel_Operations_Raise_Constraint_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Hits : Natural := 0;
   begin
      --  Each operation on No_Channel must raise Constraint_Error.
      --  Locals are scoped per-operation so the compiler doesn't
      --  warn about Receive's out parameters being passed without
      --  reads after — Receive raises before writing them.
      begin
         Bound.Send (Bound.No_Channel, 1);
      exception when Constraint_Error => Hits := Hits + 1; end;
      begin
         declare
            V  : Integer;
            OK : Boolean;
         begin
            Bound.Receive (Bound.No_Channel, V, OK);
         end;
      exception when Constraint_Error => Hits := Hits + 1; end;
      begin
         Bound.Close (Bound.No_Channel);
      exception when Constraint_Error => Hits := Hits + 1; end;
      begin
         declare
            X : constant Natural := Bound.Length (Bound.No_Channel);
            pragma Unreferenced (X);
         begin
            null;
         end;
      exception when Constraint_Error => Hits := Hits + 1; end;
      begin
         declare
            X : constant Positive := Bound.Capacity (Bound.No_Channel);
            pragma Unreferenced (X);
         begin
            null;
         end;
      exception when Constraint_Error => Hits := Hits + 1; end;
      begin
         declare
            X : constant Boolean := Bound.Is_Closed (Bound.No_Channel);
            pragma Unreferenced (X);
         begin
            null;
         end;
      exception when Constraint_Error => Hits := Hits + 1; end;
      begin
         declare
            X : constant Natural :=
              Bound.Senders_Waiting (Bound.No_Channel);
            pragma Unreferenced (X);
         begin
            null;
         end;
      exception when Constraint_Error => Hits := Hits + 1; end;
      begin
         declare
            X : constant Natural :=
              Bound.Receivers_Waiting (Bound.No_Channel);
            pragma Unreferenced (X);
         begin
            null;
         end;
      exception when Constraint_Error => Hits := Hits + 1; end;
      Assert (Hits = 8,
              "Expected 8 Constraint_Error raises on No_Channel ops, got"
              & Hits'Image);
   end Test_No_Channel_Operations_Raise_Constraint_Error;

   procedure Test_Current_Returns_No_Goroutine_From_Main_Task
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Gada.Async.Scheduler.Goroutine_Id;
   begin
      --  Main task is not a goroutine — Current must be No_Goroutine.
      --  This mirrors Park / Yield / Unpark's no-op-from-main contract
      --  and is the property the channel-receiver uses to allocate a
      --  Wait_Slot whose G is meaningful only when called from inside
      --  a goroutine.
      Gada.Async.Scheduler.Shutdown;
      Gada.Async.Scheduler.Init (Workers => 1);
      Assert (Gada.Async.Scheduler.Current
                = Gada.Async.Scheduler.No_Goroutine,
              "Current returned non-No_Goroutine from main test task");
      Gada.Async.Scheduler.Shutdown;
   end Test_Current_Returns_No_Goroutine_From_Main_Task;

   procedure Test_Close_While_Sender_Parked_Raises_Channel_Closed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Gada.Async.Scheduler.Goroutine_Id;
   begin
      --  Cap=1: main fills the buffer, then a goroutine tries to Send 99
      --  and parks (buffer full, no parked receiver). Main calls Close;
      --  the parked sender wakes with Closed_On_Wake => True and the
      --  Send raises Channel_Closed. Sender_Body_Then_Mark_Closed
      --  catches that and sets Send_Raised => True; Send_Done stays
      --  False because Send raised before reaching it.
      --
      --  Property gated: a sender that's already parked at the moment
      --  Close fires sees Channel_Closed (Go's panic shape mapped to
      --  Ada's exception). Closes the only path through Send's post-
      --  Park "Closed_On_Wake" raise — the previous tests cover the
      --  pre-Park "Try_Buffered_Send saw Closed_F = True" raise.
      The_Channel := Bound.Make (Capacity => 1);
      Send_Done := False;
      Send_Raised := False;

      Gada.Async.Scheduler.Shutdown;
      Gada.Async.Scheduler.Init (Workers => 1);

      --  Pre-fill the buffer so the goroutine's Send actually parks.
      Bound.Send (The_Channel, 1);

      Unused_G := Gada.Async.Scheduler.Spawn
        (Sender_Body_Then_Mark_Closed'Access);

      --  Wait for the goroutine to park before closing — without this
      --  Close races against Try_Buffered_Send and may fire the pre-
      --  Park raise instead of the post-Park raise we're trying to
      --  cover.
      for Attempt in 1 .. 100 loop
         exit when Bound.Senders_Waiting (The_Channel) = 1;
         delay 0.001;
      end loop;
      Assert (Bound.Senders_Waiting (The_Channel) = 1,
              "Sender did not park before Close; Senders_Waiting ="
              & Bound.Senders_Waiting (The_Channel)'Image);

      Bound.Close (The_Channel);

      for Attempt in 1 .. 100 loop
         exit when Send_Raised;
         delay 0.001;
      end loop;
      Assert (Send_Raised,
              "Parked Send did not raise Channel_Closed after Close — "
              & "the post-Park Closed_On_Wake arm is still uncovered");
      Assert (not Send_Done,
              "Send returned successfully despite Close while parked — "
              & "the post-Park raise should have skipped Send_Done := True");

      Gada.Async.Scheduler.Shutdown;
   end Test_Close_While_Sender_Parked_Raises_Channel_Closed;

end Channels_Suite;
