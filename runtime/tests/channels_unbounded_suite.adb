--  Body of Channels_Unbounded_Suite — see spec for property index.
--
--  Mirrors the bounded suite's organisation: file-scope channel
--  handle + per-test counters because Spawn'd Goroutine_Body access
--  procedures have no closure mechanism. Tests reset the globals
--  they read before driving Spawn.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Async.Scheduler;
with Gada.Async.Channels.Unbounded;

package body Channels_Unbounded_Suite is

   --  Single instantiation reused across every test.
   package Unbnd is new Gada.Async.Channels.Unbounded
     (Element_Type => Integer);

   The_Channel  : Unbnd.Channel := Unbnd.No_Channel;

   --  Receive results captured by goroutine bodies.
   Last_Recv_V    : Integer := 0;
   Last_Recv_OK   : Boolean := False;
   Recv_Done      : Boolean := False;

   --  Body procedures used by Spawn.
   procedure Receiver_Body_Receive_Once;

   procedure Receiver_Body_Receive_Once is
   begin
      Unbnd.Receive (The_Channel, Last_Recv_V, Last_Recv_OK);
      Recv_Done := True;
   end Receiver_Body_Receive_Once;

   ---------------------------------------------------------------

   overriding function Name
     (T : Channels_Unbounded_Test) return AUnit.Message_String is
     (AUnit.Format
        ("Gada.Async.Channels.Unbounded suite "
         & "(PKG=async.channels.unbounded)"));

   overriding procedure Register_Tests
     (T : in out Channels_Unbounded_Test)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Make_Length_Starts_At_Zero'Access,
         "Make returns a non-No_Channel handle whose Length starts "
         & "at 0 and Is_Closed is False");
      Register_Routine
        (T, Test_Send_Many_Without_Receiver_Never_Blocks'Access,
         "1000 Sends without an intervening Receive complete in "
         & "main-task time without parking — Length grows to 1000 "
         & "(sub-item 5 verify gate — send never blocks)");
      Register_Routine
        (T, Test_Send_Receive_FIFO_Order'Access,
         "Send N values, then Receive N values from main; the receive "
         & "order matches the send order (per-channel FIFO)");
      Register_Routine
        (T, Test_Receive_From_Empty_Closed_Returns_OK_False'Access,
         "Receive on an empty closed channel returns "
         & "(default Element_Type, OK => False) — Go's zero-value-"
         & "with-ok-false signal");
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
        (T, Test_Receive_Blocks_When_Empty_Then_Send_Unblocks'Access,
         "A Receive on an empty open channel parks the receiver; "
         & "the next Send hands the value directly into the parked "
         & "receiver's slot and unblocks them");
      Register_Routine
        (T, Test_Close_Wakes_Parked_Receivers_With_OK_False'Access,
         "Close on a channel with parked Receivers wakes each one "
         & "with OK => False — Go's broadcast-close-to-receivers "
         & "semantics");
      Register_Routine
        (T, Test_Length_And_Is_Closed_Reflect_State'Access,
         "Length tracks buffered count; Is_Closed flips True after "
         & "Close — diagnostic queries follow the channel's state");
      Register_Routine
        (T, Test_No_Channel_Operations_Raise_Constraint_Error'Access,
         "Send / Receive / Close / Length / Is_Closed / Receivers_"
         & "Waiting on No_Channel each raise Constraint_Error");
      Register_Routine
        (T, Test_Send_During_Receiver_Park_Hands_Off_Directly'Access,
         "Send on a channel with a parked receiver hands the value "
         & "directly into the receiver's slot without growing the "
         & "buffer — Length stays 0 across the round-trip");
      Register_Routine
        (T, Test_Receive_Park_From_Non_Goroutine_Raises'Access,
         "Receive that would park (empty buffer + open channel) "
         & "from a non-goroutine context raises Program_Error "
         & "rather than allocating an orphaned Wait_Slot — mirror "
         & "of the Channels.Bounded.Receive guard");
   end Register_Tests;

   ---------------------------------------------------------------

   procedure Test_Make_Length_Starts_At_Zero
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : constant Unbnd.Channel := Unbnd.Make;
   begin
      Assert (Unbnd.Length (C) = 0,
              "Fresh channel must have Length = 0, got"
              & Unbnd.Length (C)'Image);
      Assert (not Unbnd.Is_Closed (C),
              "Fresh channel must not be closed");
      Assert (Unbnd.Receivers_Waiting (C) = 0,
              "Fresh channel must have 0 parked receivers");
   end Test_Make_Length_Starts_At_Zero;

   procedure Test_Send_Many_Without_Receiver_Never_Blocks
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C  : constant Unbnd.Channel := Unbnd.Make;
      N  : constant := 1000;
      V  : Integer;
      OK : Boolean;
   begin
      --  Send N from main without any Receiver. Main has no
      --  goroutine context, so a blocking Send would hang the test.
      --  Reaching the assertion proves Send never blocked.
      for I in 1 .. N loop
         Unbnd.Send (C, I);
      end loop;
      Assert (Unbnd.Length (C) = N,
              "After" & N'Image & " sends Length should be" & N'Image
              & ", got" & Unbnd.Length (C)'Image);

      --  Drain to confirm FIFO across a large run.
      for I in 1 .. N loop
         Unbnd.Receive (C, V, OK);
         Assert (OK and then V = I,
                 "Drain expected (" & I'Image & ", True), got ("
                 & V'Image & "," & OK'Image & ")");
      end loop;
      Assert (Unbnd.Length (C) = 0,
              "After drain Length must be 0, got"
              & Unbnd.Length (C)'Image);
   end Test_Send_Many_Without_Receiver_Never_Blocks;

   procedure Test_Send_Receive_FIFO_Order
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C  : constant Unbnd.Channel := Unbnd.Make;
      V  : Integer;
      OK : Boolean;
   begin
      Unbnd.Send (C, 10);
      Unbnd.Send (C, 20);
      Unbnd.Send (C, 30);
      Unbnd.Receive (C, V, OK);
      Assert (OK and then V = 10, "First receive expected (10, True)");
      Unbnd.Receive (C, V, OK);
      Assert (OK and then V = 20, "Second receive expected (20, True)");
      Unbnd.Receive (C, V, OK);
      Assert (OK and then V = 30, "Third receive expected (30, True)");
   end Test_Send_Receive_FIFO_Order;

   procedure Test_Receive_From_Empty_Closed_Returns_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C  : constant Unbnd.Channel := Unbnd.Make;
      V  : Integer;
      OK : Boolean;
   begin
      --  Pre-set V to a sentinel so we can assert "Receive did not
      --  alter V" — the closed-empty contract is OK = False with V
      --  unmodified (Ada generic cannot synthesise a portable zero
      --  for an opaque private Element_Type; Phase 4 compiler emit
      --  handles V's zero-init at the call site).
      V := 12345;
      Unbnd.Close (C);
      Unbnd.Receive (C, V, OK);
      Assert (not OK,
              "Receive on closed-empty channel must set OK = False");
      Assert (V = 12345,
              "Receive on closed-empty channel must leave V "
              & "unmodified (caller-side zero-init contract); got"
              & V'Image);
   end Test_Receive_From_Empty_Closed_Returns_OK_False;

   procedure Test_Send_On_Closed_Channel_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C      : constant Unbnd.Channel := Unbnd.Make;
      Raised : Boolean := False;
   begin
      Unbnd.Close (C);
      begin
         Unbnd.Send (C, 1);
      exception
         when Unbnd.Channel_Closed =>
            Raised := True;
      end;
      Assert (Raised, "Send on closed channel must raise Channel_Closed");
   end Test_Send_On_Closed_Channel_Raises;

   procedure Test_Close_Twice_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C      : constant Unbnd.Channel := Unbnd.Make;
      Raised : Boolean := False;
   begin
      Unbnd.Close (C);
      begin
         Unbnd.Close (C);
      exception
         when Unbnd.Channel_Closed =>
            Raised := True;
      end;
      Assert (Raised, "Close on already-closed channel must raise");
   end Test_Close_Twice_Raises;

   procedure Test_Receive_After_Drain_Returns_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C  : constant Unbnd.Channel := Unbnd.Make;
      V  : Integer;
      OK : Boolean;
   begin
      Unbnd.Send (C, 7);
      Unbnd.Send (C, 8);
      Unbnd.Close (C);
      Unbnd.Receive (C, V, OK);
      Assert (OK and then V = 7,
              "Pre-drain Receive expected (7, True)");
      Unbnd.Receive (C, V, OK);
      Assert (OK and then V = 8,
              "Pre-drain Receive expected (8, True)");
      Unbnd.Receive (C, V, OK);
      Assert (not OK,
              "Post-drain Receive on closed channel expected OK = False");
   end Test_Receive_After_Drain_Returns_OK_False;

   procedure Test_Receive_Blocks_When_Empty_Then_Send_Unblocks
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Gada.Async.Scheduler.Goroutine_Id;
   begin
      The_Channel := Unbnd.Make;
      Last_Recv_V := 0;
      Last_Recv_OK := False;
      Recv_Done := False;

      Gada.Async.Scheduler.Shutdown;
      Gada.Async.Scheduler.Init (Workers => 1);

      --  Goroutine receives — buffer empty → park.
      Unused_G := Gada.Async.Scheduler.Spawn
        (Receiver_Body_Receive_Once'Access);

      --  Wait for the receiver to actually park.
      for Attempt in 1 .. 100 loop
         exit when Unbnd.Receivers_Waiting (The_Channel) = 1;
         delay 0.001;
      end loop;
      Assert (Unbnd.Receivers_Waiting (The_Channel) = 1,
              "Receiver goroutine did not park within 100 ms; "
              & "Receivers_Waiting ="
              & Unbnd.Receivers_Waiting (The_Channel)'Image);

      Unbnd.Send (The_Channel, 77);

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
      The_Channel := Unbnd.Make;
      Last_Recv_V := 99;
      Last_Recv_OK := True;
      Recv_Done := False;

      Gada.Async.Scheduler.Shutdown;
      Gada.Async.Scheduler.Init (Workers => 1);

      Unused_G := Gada.Async.Scheduler.Spawn
        (Receiver_Body_Receive_Once'Access);

      for Attempt in 1 .. 100 loop
         exit when Unbnd.Receivers_Waiting (The_Channel) = 1;
         delay 0.001;
      end loop;
      Assert (Unbnd.Receivers_Waiting (The_Channel) = 1,
              "Receiver did not park before Close");

      Unbnd.Close (The_Channel);

      for Attempt in 1 .. 100 loop
         exit when Recv_Done;
         delay 0.001;
      end loop;
      Assert (Recv_Done,
              "Parked receiver did not wake after Close");
      Assert (not Last_Recv_OK,
              "Receiver woken by Close should observe OK = False");
      --  V's content is unspecified on the close-while-parked path —
      --  see the spec note. Tests assert OK only.

      Gada.Async.Scheduler.Shutdown;
   end Test_Close_Wakes_Parked_Receivers_With_OK_False;

   procedure Test_Length_And_Is_Closed_Reflect_State
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C  : constant Unbnd.Channel := Unbnd.Make;
      V  : Integer;
      OK : Boolean;
   begin
      Assert (Unbnd.Length (C) = 0, "fresh Length must be 0");
      Assert (not Unbnd.Is_Closed (C), "fresh Is_Closed must be False");
      Unbnd.Send (C, 1);
      Assert (Unbnd.Length (C) = 1, "post-send Length must be 1");
      Unbnd.Send (C, 2);
      Assert (Unbnd.Length (C) = 2, "post-send Length must be 2");
      Unbnd.Receive (C, V, OK);
      Assert (Unbnd.Length (C) = 1, "post-recv Length must be 1");
      Unbnd.Close (C);
      Assert (Unbnd.Is_Closed (C), "post-close Is_Closed must be True");
      Assert (Unbnd.Length (C) = 1,
              "Close does NOT drain the buffer; Length still 1");
   end Test_Length_And_Is_Closed_Reflect_State;

   procedure Test_No_Channel_Operations_Raise_Constraint_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Hits : Natural := 0;
   begin
      begin
         Unbnd.Send (Unbnd.No_Channel, 1);
      exception when Constraint_Error => Hits := @ + 1; end;
      begin
         declare
            V  : Integer;
            OK : Boolean;
         begin
            Unbnd.Receive (Unbnd.No_Channel, V, OK);
         end;
      exception when Constraint_Error => Hits := @ + 1; end;
      begin
         Unbnd.Close (Unbnd.No_Channel);
      exception when Constraint_Error => Hits := @ + 1; end;
      begin
         declare
            X : constant Natural := Unbnd.Length (Unbnd.No_Channel);
            pragma Unreferenced (X);
         begin
            null;
         end;
      exception when Constraint_Error => Hits := @ + 1; end;
      begin
         declare
            X : constant Boolean := Unbnd.Is_Closed (Unbnd.No_Channel);
            pragma Unreferenced (X);
         begin
            null;
         end;
      exception when Constraint_Error => Hits := @ + 1; end;
      begin
         declare
            X : constant Natural :=
              Unbnd.Receivers_Waiting (Unbnd.No_Channel);
            pragma Unreferenced (X);
         begin
            null;
         end;
      exception when Constraint_Error => Hits := @ + 1; end;
      Assert (Hits = 6,
              "Expected 6 Constraint_Error raises on No_Channel ops, got"
              & Hits'Image);
   end Test_No_Channel_Operations_Raise_Constraint_Error;

   procedure Test_Send_During_Receiver_Park_Hands_Off_Directly
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Gada.Async.Scheduler.Goroutine_Id;
   begin
      --  Property gated: when a receiver is parked AND Send arrives,
      --  the protected hands V directly into the receiver's slot
      --  without allocating a Node. Length never goes positive
      --  across the round-trip — proves the direct-handoff fast
      --  path fired (the buffer-then-drain alternative would
      --  briefly bump Length to 1).
      The_Channel := Unbnd.Make;
      Last_Recv_V := 0;
      Last_Recv_OK := False;
      Recv_Done := False;

      Gada.Async.Scheduler.Shutdown;
      Gada.Async.Scheduler.Init (Workers => 1);

      Unused_G := Gada.Async.Scheduler.Spawn
        (Receiver_Body_Receive_Once'Access);

      for Attempt in 1 .. 100 loop
         exit when Unbnd.Receivers_Waiting (The_Channel) = 1;
         delay 0.001;
      end loop;
      Assert (Unbnd.Receivers_Waiting (The_Channel) = 1,
              "Receiver did not park before Send");
      Assert (Unbnd.Length (The_Channel) = 0,
              "Buffer should be empty before Send");

      Unbnd.Send (The_Channel, 555);

      --  After Send, buffer must still be 0 — the value went
      --  straight into the parked receiver's slot.
      Assert (Unbnd.Length (The_Channel) = 0,
              "Direct handoff: Length must stay 0 after Send to a "
              & "parked receiver, got" & Unbnd.Length (The_Channel)'Image);

      for Attempt in 1 .. 100 loop
         exit when Recv_Done;
         delay 0.001;
      end loop;
      Assert (Recv_Done and then Last_Recv_OK
                and then Last_Recv_V = 555,
              "Direct-handoff receive expected (555, True), got ("
              & Last_Recv_V'Image & "," & Last_Recv_OK'Image & ")");

      Gada.Async.Scheduler.Shutdown;
   end Test_Send_During_Receiver_Park_Hands_Off_Directly;

   ---------------------------------------------------------------

   procedure Test_Receive_Park_From_Non_Goroutine_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C      : constant Unbnd.Channel := Unbnd.Make;
      V      : Integer := 0;
      OK     : Boolean;
      Raised : Boolean := False;
   begin
      --  Channel is empty AND open: Receive must park. Calling from
      --  the main task (Scheduler.Current = No_Goroutine) trips the
      --  guard added in 8e0bf22 and raises Program_Error before
      --  Slot allocation.
      begin
         Unbnd.Receive (C, V, OK);
         Assert (False,
                 "Unbnd.Receive on empty open channel from main "
                 & "task should have raised Program_Error");
      exception
         when Program_Error =>
            Raised := True;
      end;
      Assert (Raised, "Program_Error must propagate");
   end Test_Receive_Park_From_Non_Goroutine_Raises;

end Channels_Unbounded_Suite;
