--  Body of Deadlock_Suite — see spec for test rationale.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Async.Channels.Bounded;
with Gada.Async.Channels.Unbounded;
with Gada.Async.Scheduler;
with Gada.Async.Selector;
with Gada.Core.Process;
with Gada.Std.Time;

package body Deadlock_Suite is

   package Scheduler renames Gada.Async.Scheduler;
   package Process renames Gada.Core.Process;
   package Time renames Gada.Std.Time;
   use type Time.Duration;

   package Unb is new Gada.Async.Channels.Unbounded (Integer);
   package Bnd is new Gada.Async.Channels.Bounded (Integer);
   package Sel is new Gada.Async.Selector
     (Element_Type => Integer, Default_Element => 0, Bnd => Bnd);

   Exit_Called : exception;
   Last_Code   : Integer := -1;

   procedure Record_Exit (Code : Integer) is
   begin
      Last_Code := Code;
      raise Exit_Called;
   end Record_Exit;

   procedure Record_Only (Code : Integer) is
   begin
      Last_Code := Code;
   end Record_Only;

   procedure Arm is
   begin
      Last_Code := -1;
      Scheduler.Shutdown;  --  no goroutine may be in flight
      Process.Set_Exit_Handler (Record_Exit'Access);
      Scheduler.Set_Deadlock_Detection (True);
   end Arm;

   overriding procedure Tear_Down (T : in out Deadlock_Test) is
   begin
      Scheduler.Set_Deadlock_Detection (False);
      Process.Set_Exit_Handler (null);
   end Tear_Down;

   overriding function Name
     (T : Deadlock_Test) return AUnit.Message_String is
     (AUnit.Format ("Deadlock detection suite (PKG=async.deadlock)"));

   overriding procedure Register_Tests (T : in out Deadlock_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Unbounded_Receive'Access,
                        "main receive, no sender: deadlock exit 2");
      Register_Routine (T, Test_Bounded_Send_Receive'Access,
                        "bounded send (full) / receive: deadlock");
      Register_Routine (T, Test_Select'Access,
                        "main select, nothing ready: deadlock");
      Register_Routine (T, Test_Stopped_Ticker'Access,
                        "receive on a stopped ticker: deadlock");
      Register_Routine (T, Test_No_False_Positive'Access,
                        "pending timer / live goroutine: no report");
      Register_Routine (T, Test_Disabled_And_Returning_Handler'Access,
                        "detection off by default; handler return");
   end Register_Tests;

   procedure Test_Unbounded_Receive (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      C     : constant Unb.Channel := Unb.Make;
      V     : Integer := 0;
      OK    : Boolean;
   begin
      Arm;
      begin
         Unb.Receive (C, V, OK);
         Assert (False, "receive with no possible sender must report");
      exception
         when Exit_Called =>
            null;
      end;
      Assert (Last_Code = 2, "deadlock exits with status 2");
   end Test_Unbounded_Receive;

   procedure Test_Bounded_Send_Receive (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      C  : constant Bnd.Channel := Bnd.Make (1);
      V  : Integer := 0;
      OK : Boolean;
   begin
      Arm;
      begin
         Bnd.Receive (C, V, OK);
         Assert (False, "empty bounded receive must report");
      exception
         when Exit_Called =>
            null;
      end;
      Assert (Last_Code = 2, "bounded receive deadlock exits 2");
      Last_Code := -1;
      Bnd.Send (C, 1);   --  fills the single slot (no block)
      begin
         Bnd.Send (C, 2);
         Assert (False, "send on a full channel nobody drains must report");
      exception
         when Exit_Called =>
            null;
      end;
      Assert (Last_Code = 2, "bounded send deadlock exits 2");
   end Test_Bounded_Send_Receive;

   procedure Test_Select (T : in out AUnit.Test_Cases.Test_Case'Class) is
      C     : constant Bnd.Channel := Bnd.Make (1);
      Cases : Sel.Case_Array (1 .. 1);
      Idx   : Positive;
      pragma Unreferenced (Idx);
   begin
      Cases (1) := (Kind             => Sel.Recv_Op,
                    Chan             => C,
                    Send_V           => 0,
                    Recv_V_Out       => new Integer'(0),
                    Recv_OK_Out      => new Boolean'(False),
                    Timeout_Duration => 0.0);
      Arm;
      begin
         Idx := Sel.Select_One (Cases);
         Assert (False, "select with nothing ready must report");
      exception
         when Exit_Called =>
            null;
      end;
      Assert (Last_Code = 2, "select deadlock exits 2");
   end Test_Select;

   procedure Test_Stopped_Ticker (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      W0 : constant Natural := Scheduler.Pending_Wakers;
      Tk : constant Time.Time_Channels.Channel :=
        Time.Tick (Time.Millisecond);
      V, OK : Boolean;
   begin
      Assert (Scheduler.Pending_Wakers = W0 + 1, "a live ticker is a waker");
      Time.Time_Channels.Receive (Tk, V, OK);
      Assert (OK, "ticker ticks while live");
      Time.Stop_Channel (Tk);
      Assert (Scheduler.Pending_Wakers = W0, "stopping releases it");
      Arm;
      begin
         --  At most one tick was pending at Stop; drain it, then the
         --  next receive can never complete.
         for I in 1 .. 2 loop
            Time.Time_Channels.Receive (Tk, V, OK);
         end loop;
         Assert (False, "receive on a stopped ticker must report");
      exception
         when Exit_Called =>
            null;
      end;
      Assert (Last_Code = 2, "stopped-ticker deadlock exits 2");
   end Test_Stopped_Ticker;

   --  A goroutine that sends after main has started waiting.
   Late_Chan : Unb.Channel;

   procedure Late_Sender is
   begin
      delay 0.03;   --  blocks its worker; main is its own task
      Unb.Send (Late_Chan, 42);
   end Late_Sender;

   procedure Test_No_False_Positive (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      W0       : constant Natural := Scheduler.Pending_Wakers;
      V, OK    : Boolean;
      N        : Integer := 0;
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Arm;
      --  Pending one-shot timer: main must wait for it, not report.
      Time.Time_Channels.Receive (Time.After (20 * Time.Millisecond), V, OK);
      Assert (OK and then Last_Code = -1, "timer delivered, no report");
      Assert (Scheduler.Pending_Wakers = W0,
              "a fired one-shot releases its waker");
      --  Live goroutine that sends later.
      Late_Chan := Unb.Make;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Late_Sender'Access);
      Unb.Receive (Late_Chan, N, OK);
      Assert (OK and then N = 42 and then Last_Code = -1,
              "goroutine's send delivered, no report");
      Scheduler.Shutdown;
   end Test_No_False_Positive;

   procedure Test_Disabled_And_Returning_Handler (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      C  : constant Unb.Channel := Unb.Make;
      V  : Integer := 0;
      OK : Boolean := True;
      Cases : Sel.Case_Array (1 .. 1);
      Idx   : Positive;
      pragma Unreferenced (Idx);
   begin
      Scheduler.Shutdown;
      Assert (not Scheduler.No_Progress_Possible,
              "detection is off unless a generated main enables it");
      --  A handler that returns (only tests can install one): the
      --  blocking op gives up instead of spinning, the select raises.
      Arm;
      Process.Set_Exit_Handler (Record_Only'Access);
      Unb.Receive (C, V, OK);
      Assert (Last_Code = 2 and then not OK,
              "returning handler: receive gives up with OK = False");
      Last_Code := -1;
      Cases (1) := (Kind             => Sel.Recv_Op,
                    Chan             => Bnd.Make (1),
                    Send_V           => 0,
                    Recv_V_Out       => new Integer'(0),
                    Recv_OK_Out      => new Boolean'(False),
                    Timeout_Duration => 0.0);
      begin
         Idx := Sel.Select_One (Cases);
         Assert (False, "select must not return a case after a report");
      exception
         when Program_Error =>
            null;
      end;
      Assert (Last_Code = 2, "select reported before raising");
   end Test_Disabled_And_Returning_Handler;

end Deadlock_Suite;
