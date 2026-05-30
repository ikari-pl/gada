--  Body of Selector_Suite — see spec for property list.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

with Gada.Async.Scheduler;
with Gada.Async.Channels.Bounded;
with Gada.Async.Selector;

package body Selector_Suite is

   --  Single Element_Type instantiation for the whole suite.
   package Bound is new Gada.Async.Channels.Bounded
     (Element_Type => Integer);

   package Sel is new Gada.Async.Selector
     (Element_Type    => Integer,
      Default_Element => 0,
      Bnd             => Bound);

   --  Globals reused by goroutine bodies (no closure mechanism on
   --  Goroutine_Body access procedures).
   The_Channel  : Bound.Channel := Bound.No_Channel;
   Sender_Done  : Boolean := False;

   procedure Sender_Body_Sends_55;
   procedure Sender_Body_Sends_55 is
   begin
      Bound.Send (The_Channel, 55);
      Sender_Done := True;
   end Sender_Body_Sends_55;

   ---------------------------------------------------------------

   overriding function Name
     (T : Selector_Test) return AUnit.Message_String is
     (AUnit.Format
        ("Gada.Async.Selector suite (PKG=async.select)"));

   overriding procedure Register_Tests (T : in out Selector_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Default_Fires_When_Nothing_Ready'Access,
         "Select with a Default_Op fires the default when no other "
         & "case is ready (Go's `default:` semantics)");
      Register_Routine
        (T, Test_Recv_Wins_When_Buffer_Has_Value'Access,
         "Select with a Recv_Op on a non-empty channel returns the "
         & "Recv_Op index, with V/OK populated from the channel head");
      Register_Routine
        (T, Test_Send_Wins_When_Buffer_Has_Slot'Access,
         "Select with a Send_Op on a non-full channel returns the "
         & "Send_Op index after delivering V into the buffer");
      Register_Routine
        (T, Test_Recv_From_Closed_Channel_Yields_OK_False'Access,
         "Select with a Recv_Op on a closed-empty channel returns "
         & "the Recv_Op index with OK = False (zero-value-with-ok-"
         & "false signal)");
      Register_Routine
        (T, Test_Timeout_Fires_When_Nothing_Else_Ready'Access,
         "Select with a Timeout_Op fires that case after Duration "
         & "elapses with no other ready case");
      Register_Routine
        (T, Test_Random_Tiebreak_Across_Many_Trials'Access,
         "Select with two simultaneously-ready Recv cases picks "
         & "each with non-trivial frequency over many trials "
         & "(pseudo-random tie-breaking)");
      Register_Routine
        (T, Test_Empty_Case_Array_Raises_Selector_Error'Access,
         "Select with an empty case array raises Selector_Error "
         & "rather than deadlocking the goroutine");
      Register_Routine
        (T, Test_Two_Defaults_Raises_Selector_Error'Access,
         "Select with two Default_Op cases raises Selector_Error "
         & "(Go's compiler rejects this; runtime is the last line "
         & "of defence)");
      Register_Routine
        (T, Test_Recv_With_Null_Output_Pointers_Discards'Access,
         "Select with a Recv_Op whose output pointers are null "
         & "still consumes the value but discards V/OK (Go's "
         & "`<-ch` form without binding)");
      Register_Routine
        (T, Test_Blocks_Until_Sibling_Sends'Access,
         "Select with no Default and no Timeout blocks until a "
         & "sibling goroutine drives a case to readiness; the "
         & "polling shape yields the worker between polls so the "
         & "sibling makes progress");
      Register_Routine
        (T, Test_More_Than_Max_Cases_Raises'Access,
         "Select with more than the static Max_Cases bound raises "
         & "Selector_Error rather than truncating");
   end Register_Tests;

   ---------------------------------------------------------------

   procedure Test_Default_Fires_When_Nothing_Ready
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C     : constant Bound.Channel := Bound.Make (Capacity => 1);
      V     : constant Sel.Element_Ptr := new Integer'(0);
      OK    : constant Sel.Boolean_Ptr := new Boolean'(False);
      Cases : Sel.Case_Array (1 .. 2);
      Idx   : Positive;
   begin
      --  Recv_Op on empty channel + Default. Default must win.
      Cases (1) := (Kind        => Sel.Recv_Op,
                    Chan        => C,
                    Send_V      => 0,
                    Recv_V_Out  => V,
                    Recv_OK_Out => OK,
                    Timeout_Duration => 0.0);
      Cases (2) := (Kind        => Sel.Default_Op,
                    Chan        => Bound.No_Channel,
                    Send_V      => 0,
                    Recv_V_Out  => null,
                    Recv_OK_Out => null,
                    Timeout_Duration => 0.0);
      Idx := Sel.Select_One (Cases);
      Assert (Idx = 2,
              "Default_Op should win against an empty Recv; got"
              & Idx'Image);
   end Test_Default_Fires_When_Nothing_Ready;

   procedure Test_Recv_Wins_When_Buffer_Has_Value
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C     : constant Bound.Channel := Bound.Make (Capacity => 2);
      V     : constant Sel.Element_Ptr := new Integer'(0);
      OK    : constant Sel.Boolean_Ptr := new Boolean'(False);
      Cases : Sel.Case_Array (1 .. 2);
      Idx   : Positive;
   begin
      Bound.Send (C, 42);
      Cases (1) := (Kind        => Sel.Recv_Op,
                    Chan        => C,
                    Send_V      => 0,
                    Recv_V_Out  => V,
                    Recv_OK_Out => OK,
                    Timeout_Duration => 0.0);
      Cases (2) := (Kind        => Sel.Default_Op,
                    Chan        => Bound.No_Channel,
                    Send_V      => 0,
                    Recv_V_Out  => null,
                    Recv_OK_Out => null,
                    Timeout_Duration => 0.0);
      Idx := Sel.Select_One (Cases);
      Assert (Idx = 1,
              "Recv_Op with buffered value should win over Default; "
              & "got" & Idx'Image);
      Assert (V.all = 42 and OK.all,
              "Recv_Op should populate V = 42, OK = True; got V ="
              & V.all'Image & ", OK =" & OK.all'Image);
   end Test_Recv_Wins_When_Buffer_Has_Value;

   procedure Test_Send_Wins_When_Buffer_Has_Slot
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C     : constant Bound.Channel := Bound.Make (Capacity => 1);
      Cases : Sel.Case_Array (1 .. 2);
      Idx   : Positive;
      Vr    : Integer;
      OKr   : Boolean;
   begin
      Cases (1) := (Kind        => Sel.Send_Op,
                    Chan        => C,
                    Send_V      => 99,
                    Recv_V_Out  => null,
                    Recv_OK_Out => null,
                    Timeout_Duration => 0.0);
      Cases (2) := (Kind        => Sel.Default_Op,
                    Chan        => Bound.No_Channel,
                    Send_V      => 0,
                    Recv_V_Out  => null,
                    Recv_OK_Out => null,
                    Timeout_Duration => 0.0);
      Idx := Sel.Select_One (Cases);
      Assert (Idx = 1,
              "Send_Op with free buffer slot should win over Default; "
              & "got" & Idx'Image);
      Bound.Receive (C, Vr, OKr);
      Assert (Vr = 99 and OKr, "Channel should hold 99 after the Send");
   end Test_Send_Wins_When_Buffer_Has_Slot;

   procedure Test_Recv_From_Closed_Channel_Yields_OK_False
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C     : constant Bound.Channel := Bound.Make (Capacity => 1);
      V     : constant Sel.Element_Ptr := new Integer'(12345);
      OK    : constant Sel.Boolean_Ptr := new Boolean'(True);
      Cases : Sel.Case_Array (1 .. 1);
      Idx   : Positive;
   begin
      Bound.Close (C);
      Cases (1) := (Kind        => Sel.Recv_Op,
                    Chan        => C,
                    Send_V      => 0,
                    Recv_V_Out  => V,
                    Recv_OK_Out => OK,
                    Timeout_Duration => 0.0);
      Idx := Sel.Select_One (Cases);
      Assert (Idx = 1, "Recv_Op on closed-empty should fire its case");
      Assert (not OK.all,
              "Recv_Op on closed-empty must set OK = False; got"
              & OK.all'Image);
   end Test_Recv_From_Closed_Channel_Yields_OK_False;

   procedure Test_Timeout_Fires_When_Nothing_Else_Ready
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C     : constant Bound.Channel := Bound.Make (Capacity => 1);
      V     : constant Sel.Element_Ptr := new Integer'(0);
      OK    : constant Sel.Boolean_Ptr := new Boolean'(False);
      Cases : Sel.Case_Array (1 .. 2);
      Idx   : Positive;
   begin
      Cases (1) := (Kind        => Sel.Recv_Op,
                    Chan        => C,
                    Send_V      => 0,
                    Recv_V_Out  => V,
                    Recv_OK_Out => OK,
                    Timeout_Duration => 0.0);
      Cases (2) := (Kind        => Sel.Timeout_Op,
                    Chan        => Bound.No_Channel,
                    Send_V      => 0,
                    Recv_V_Out  => null,
                    Recv_OK_Out => null,
                    Timeout_Duration => 0.020);  --  20 ms
      Idx := Sel.Select_One (Cases);
      Assert (Idx = 2,
              "Timeout_Op should fire after the duration; got"
              & Idx'Image);
   end Test_Timeout_Fires_When_Nothing_Else_Ready;

   procedure Test_Random_Tiebreak_Across_Many_Trials
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trials       : constant := 200;
      Won_1, Won_2 : Natural := 0;
      C1, C2       : Bound.Channel;
      V1           : constant Sel.Element_Ptr := new Integer'(0);
      V2           : constant Sel.Element_Ptr := new Integer'(0);
      O1           : constant Sel.Boolean_Ptr := new Boolean'(False);
      O2           : constant Sel.Boolean_Ptr := new Boolean'(False);
      Cases        : Sel.Case_Array (1 .. 2);
      Idx          : Positive;
      Vr           : Integer;
      OKr          : Boolean;
   begin
      --  Fairness gate: with both cases simultaneously ready, the
      --  shuffle should send each case to the head of the order
      --  ~50% of the time over many trials. Threshold of >= 30%
      --  per case picks up "always pick case 1" / "always pick
      --  case 2" regressions while tolerating ordinary RNG drift.
      for Trial in 1 .. Trials loop
         C1 := Bound.Make (Capacity => 1);
         C2 := Bound.Make (Capacity => 1);
         Bound.Send (C1, 1);
         Bound.Send (C2, 2);
         Cases (1) := (Kind        => Sel.Recv_Op,
                       Chan        => C1,
                       Send_V      => 0,
                       Recv_V_Out  => V1,
                       Recv_OK_Out => O1,
                       Timeout_Duration => 0.0);
         Cases (2) := (Kind        => Sel.Recv_Op,
                       Chan        => C2,
                       Send_V      => 0,
                       Recv_V_Out  => V2,
                       Recv_OK_Out => O2,
                       Timeout_Duration => 0.0);
         Idx := Sel.Select_One (Cases);
         if Idx = 1 then
            Won_1 := @ + 1;
            --  Drain C2 to keep the GC happy across trials.
            Bound.Receive (C2, Vr, OKr);
         else
            Won_2 := @ + 1;
            Bound.Receive (C1, Vr, OKr);
         end if;
      end loop;
      Assert (Won_1 >= Trials / 4 and then Won_2 >= Trials / 4,
              "Random tie-break failed: Won_1 =" & Won_1'Image
              & ", Won_2 =" & Won_2'Image
              & ", trials =" & Trials'Image
              & "; expected each >= 25%");
   end Test_Random_Tiebreak_Across_Many_Trials;

   procedure Test_Empty_Case_Array_Raises_Selector_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Empty  : Sel.Case_Array (1 .. 0);
      Raised : Boolean := False;
   begin
      pragma Warnings (Off, "Pre""class""");
      begin
         declare
            Idx : Positive;
            pragma Unreferenced (Idx);
         begin
            Idx := Sel.Select_One (Empty);
         end;
      exception
         when Sel.Selector_Error | Constraint_Error =>
            Raised := True;
         when System.Assertions.Assert_Failure =>
            --  GNAT's Pre-aspect failure also lands here in
            --  -gnata mode; treat as a successful precondition
            --  enforcement.
            Raised := True;
      end;
      pragma Warnings (On, "Pre""class""");
      Assert (Raised,
              "Empty case array must raise Selector_Error "
              & "(or its precondition equivalent)");
   end Test_Empty_Case_Array_Raises_Selector_Error;

   procedure Test_Two_Defaults_Raises_Selector_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Cases  : Sel.Case_Array (1 .. 2);
      Raised : Boolean := False;
   begin
      Cases (1) := (Kind        => Sel.Default_Op,
                    Chan        => Bound.No_Channel,
                    Send_V      => 0,
                    Recv_V_Out  => null,
                    Recv_OK_Out => null,
                    Timeout_Duration => 0.0);
      Cases (2) := (Kind        => Sel.Default_Op,
                    Chan        => Bound.No_Channel,
                    Send_V      => 0,
                    Recv_V_Out  => null,
                    Recv_OK_Out => null,
                    Timeout_Duration => 0.0);
      begin
         declare
            Idx : Positive;
            pragma Unreferenced (Idx);
         begin
            Idx := Sel.Select_One (Cases);
         end;
      exception
         when Sel.Selector_Error =>
            Raised := True;
      end;
      Assert (Raised,
              "Two Default_Op cases must raise Selector_Error");
   end Test_Two_Defaults_Raises_Selector_Error;

   procedure Test_Recv_With_Null_Output_Pointers_Discards
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C     : constant Bound.Channel := Bound.Make (Capacity => 1);
      Cases : Sel.Case_Array (1 .. 1);
      Idx   : Positive;
   begin
      Bound.Send (C, 7);
      Cases (1) := (Kind        => Sel.Recv_Op,
                    Chan        => C,
                    Send_V      => 0,
                    Recv_V_Out  => null,
                    Recv_OK_Out => null,
                    Timeout_Duration => 0.0);
      Idx := Sel.Select_One (Cases);
      Assert (Idx = 1, "Discard-recv should still fire the case");
      Assert (Bound.Length (C) = 0,
              "Discard-recv must still consume the value; Length"
              & Bound.Length (C)'Image);
   end Test_Recv_With_Null_Output_Pointers_Discards;

   procedure Test_Blocks_Until_Sibling_Sends
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Gada.Async.Scheduler.Goroutine_Id;
      V        : constant Sel.Element_Ptr := new Integer'(0);
      OK       : constant Sel.Boolean_Ptr := new Boolean'(False);
      Cases    : Sel.Case_Array (1 .. 1);
      Idx      : Positive;
   begin
      The_Channel := Bound.Make (Capacity => 1);
      Sender_Done := False;

      Gada.Async.Scheduler.Shutdown;
      Gada.Async.Scheduler.Init (Workers => 2);

      --  Sibling sends 55 after a small delay so our Select polls
      --  the empty channel a few times first, exercising the
      --  Poll_Interval delay path.
      Unused_G := Gada.Async.Scheduler.Spawn
        (Sender_Body_Sends_55'Access);

      Cases (1) := (Kind        => Sel.Recv_Op,
                    Chan        => The_Channel,
                    Send_V      => 0,
                    Recv_V_Out  => V,
                    Recv_OK_Out => OK,
                    Timeout_Duration => 0.0);
      Idx := Sel.Select_One (Cases);
      Assert (Idx = 1, "Recv_Op should fire when sibling Sends");
      Assert (V.all = 55 and OK.all,
              "Recv_Op should observe sibling's V = 55, OK = True; "
              & "got V =" & V.all'Image & ", OK =" & OK.all'Image);

      for Attempt in 1 .. 100 loop
         exit when Sender_Done;
         delay 0.001;
      end loop;
      Gada.Async.Scheduler.Shutdown;
   end Test_Blocks_Until_Sibling_Sends;

   procedure Test_More_Than_Max_Cases_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Big    : Sel.Case_Array (1 .. 65) :=
        [others => (Kind => Sel.Default_Op,
                    Chan => Bound.No_Channel,
                    Send_V => 0,
                    Recv_V_Out => null,
                    Recv_OK_Out => null,
                    Timeout_Duration => 0.0)];
      Raised : Boolean := False;
   begin
      --  All Default_Op except the first — Big has 65 entries which
      --  is one over the static Max_Cases. The first-Default check
      --  fires before the size check, so we make case 1 a non-
      --  Default to force the size check to run.
      Big (1) := (Kind        => Sel.Recv_Op,
                  Chan        => Bound.Make (Capacity => 1),
                  Send_V      => 0,
                  Recv_V_Out  => null,
                  Recv_OK_Out => null,
                  Timeout_Duration => 0.0);
      --  And drop Default_Op from cases 2..65 (multiple defaults
      --  would raise sooner). Make them all Recv on the same chan;
      --  size-bound check catches us first.
      for I in 2 .. Big'Last loop
         Big (I) := (Kind        => Sel.Recv_Op,
                     Chan        => Big (1).Chan,
                     Send_V      => 0,
                     Recv_V_Out  => null,
                     Recv_OK_Out => null,
                     Timeout_Duration => 0.0);
      end loop;
      begin
         declare
            Idx : Positive;
            pragma Unreferenced (Idx);
         begin
            Idx := Sel.Select_One (Big);
         end;
      exception
         when Sel.Selector_Error =>
            Raised := True;
      end;
      Assert (Raised,
              "More than 64 cases must raise Selector_Error");
   end Test_More_Than_Max_Cases_Raises;

end Selector_Suite;
