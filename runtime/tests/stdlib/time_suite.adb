--  Body of Time_Suite — see spec for test rationale.
--
--  Channel receives must run inside goroutines (Park is a no-op in
--  the main task), so After/Tick tests spawn a waiter and the main
--  task polls a flag with Yield. A watchdog After keeps a broken
--  timer from hanging CI forever.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Real_Time;
with Gada.Async.Scheduler;
with Gada.Std.Time; use Gada.Std.Time;

package body Time_Suite is

   package Scheduler renames Gada.Async.Scheduler;
   package RT renames Ada.Real_Time;

   --  Cross-task flags: volatile so the poll loops re-read memory.
   Waiter_Flag  : Boolean := False;
   pragma Volatile (Waiter_Flag);
   Tick_Count   : Natural := 0;
   pragma Volatile (Tick_Count);
   Watchdog_Hit : Boolean := False;
   pragma Volatile (Watchdog_Hit);

   Waiter_Chan   : Time_Channels.Channel;
   Tick_Chan     : Time_Channels.Channel;
   Watchdog_Chan : Time_Channels.Channel;

   procedure Waiter_Body is
      V  : Boolean;
      OK : Boolean;
   begin
      Time_Channels.Receive (Waiter_Chan, V, OK);
      Waiter_Flag := OK;
   end Waiter_Body;

   procedure Tick_Body is
      V  : Boolean;
      OK : Boolean;
   begin
      for I in 1 .. 2 loop
         Time_Channels.Receive (Tick_Chan, V, OK);
         if OK then
            Tick_Count := Tick_Count + 1;
         else
            exit;  --  channel closed: stop counting
         end if;
      end loop;
   end Tick_Body;

   procedure Watchdog_Body is
      V  : Boolean;
      OK : Boolean;
   begin
      Time_Channels.Receive (Watchdog_Chan, V, OK);
      Watchdog_Hit := OK;
   end Watchdog_Body;

   overriding function Name
     (T : Time_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Time suite"));

   overriding procedure Register_Tests (T : in out Time_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Duration_String'Access, "Duration.String");
      Register_Routine
        (T, Test_Duration_Arith'Access, "Duration arithmetic");
      Register_Routine (T, Test_Now_Since'Access, "Now/Since monotonic");
      Register_Routine
        (T, Test_Date_Accessors'Access, "Date + accessors");
      Register_Routine
        (T, Test_UTC_Local_Format'Access, "UTC/Local RFC3339");
      Register_Routine (T, Test_After'Access, "After fires");
      Register_Routine (T, Test_Sleep'Access, "Sleep duration");
      Register_Routine (T, Test_Timer_Stop'Access, "NewTimer + Stop");
      Register_Routine (T, Test_Tick'Access, "Tick repeats");
      Register_Routine (T, Test_Stop_All'Access, "Stop_All silences timers");
   end Register_Tests;

   --  All Duration.String expectations pinned against Go 1.27.
   procedure Test_Duration_String (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (To_String (0 * Nanosecond) = "0s", "0s");
      Assert (To_String (Nanosecond) = "1ns", "1ns");
      Assert (To_String (1500 * Nanosecond) = "1.5µs", "1.5µs");
      Assert (To_String (Microsecond) = "1µs", "1µs");
      Assert (To_String (300 * Millisecond) = "300ms", "300ms");
      Assert (To_String (1500 * Millisecond) = "1.5s", "1.5s");
      Assert (To_String (90 * Second) = "1m30s", "1m30s");
      Assert (To_String (Hour + 2 * Minute + 3 * Second + 4 * Millisecond)
                = "1h2m3.004s", "1h2m3.004s");
      Assert (To_String (-1500 * Millisecond) = "-1.5s", "-1.5s");
      Assert (To_String (24 * Hour) = "24h0m0s", "24h0m0s");
   end Test_Duration_String;

   procedure Test_Duration_Arith (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Hour + 2 * Minute = 3_720_000_000_000 * Nanosecond,
              "h + 2m");
      Assert (Second - 250 * Millisecond = 750_000_000 * Nanosecond,
              "s - 250ms");
      Assert (100 * Millisecond * 3 = 300 * Millisecond, "d * n");
      Assert (Second / 4 = 250 * Millisecond, "d / n");
      Assert (Millisecond < Second and Second <= Second
              and Hour > Minute, "comparisons");
      Assert (Nanoseconds (Hour + 2 * Minute) = 3_720_000_000_000,
              "Nanoseconds");
   end Test_Duration_Arith;

   procedure Test_Now_Since (T : in out AUnit.Test_Cases.Test_Case'Class) is
      T0 : constant Time := Now;
   begin
      delay until RT."+" (RT.Clock, RT.Milliseconds (20));
      declare
         D : constant Gada.Std.Time.Duration := Since (T0);
      begin
         Assert (D >= 15 * Millisecond,
                 "Since >= 15ms after a 20ms delay, got " & To_String (D));
         Assert (D < 5 * Second, "Since is sane, got " & To_String (D));
         Assert (Until_K (T0, T0) = 0, "Until(t, t) = 0");
      end;
   end Test_Now_Since;

   procedure Test_Date_Accessors (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      D : constant Time :=
        Date (2026, 11, 26, 7, 8, 9, 123_456_789, True);
   begin
      Assert (Year (D) = 2026 and Month (D) = 11 and Day (D) = 26,
              "date y/m/d");
      Assert (Hour_Of (D) = 7 and Minute_Of (D) = 8 and Second_Of (D) = 9,
              "date h/m/s");
      Assert (Nanosecond_Of (D) = 123_456_789, "nanosecond");
   end Test_Date_Accessors;

   procedure Test_UTC_Local_Format (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      D  : constant Time :=
        Date (2026, 11, 26, 7, 8, 9, 123_456_789, True);
      LU : constant Time := Local (UTC (D));
   begin
      Assert (RFC3339_Nano (UTC (D)) = "2026-11-26T07:08:09.123456789Z",
              "UTC format, got " & RFC3339_Nano (UTC (D)));
      --  Local keeps the instant; only the zone suffix differs.
      Assert (Year (LU) = 2026 and Nanosecond_Of (LU) = 123_456_789,
              "Local keeps instant");
      declare
         S : constant String := RFC3339_Nano (LU);
      begin
         Assert (S'Length >= 29 and then S (S'First .. S'First + 28)
                   = "2026-11-26T07:08:09.123456789",
                 "Local date-time part, got " & S);
      end;
      --  Converting a Local value exercises UTC's wall-shift body;
      --  Local() on a Local value is the identity early return.
      declare
         DL : constant Time := Date (2026, 11, 26, 7, 8, 9, 123_456_789,
                                     False);
         U2 : constant Time := UTC (DL);
         L2 : constant Time := Local (DL);
      begin
         Assert (U2.UTC and then not L2.UTC,
                 "UTC() sets the zone flag, Local() keeps it");
         Assert (Nanosecond_Of (U2) = 123_456_789
                   and then Nanosecond_Of (L2) = 123_456_789,
                 "zone conversion keeps the instant");
      end;
   end Test_UTC_Local_Format;

   --  Sleep(d) must block at least d; d <= 0 returns immediately
   --  (the guard arm).
   procedure Test_Sleep (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Start : constant Time := Now;
   begin
      Sleep (20 * Millisecond);
      Assert (Since (Start) >= 20 * Millisecond,
              "Sleep returned before the requested duration");
      Sleep (0);
      Sleep (-Second);
   end Test_Sleep;

   procedure Test_After (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Waiter_Flag := False;
      Watchdog_Hit := False;
      Waiter_Chan := After (10 * Millisecond);
      Watchdog_Chan := After (30 * Second);
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Waiter_Body'Access);
      Unused_G := Scheduler.Spawn (Watchdog_Body'Access);
      --  Poll with a real delay: Yield is a no-op outside a goroutine,
      --  so only a timed wait gives the worker task CPU time.
      for I in 1 .. 5_000 loop
         exit when Waiter_Flag;
         delay 0.001;
      end loop;
      --  Release the watchdog before Shutdown: stop its timer and
      --  close its channel so the parked watchdog goroutine wakes
      --  with OK => False and the drain can finish.
      Stop_Channel (Watchdog_Chan);
      Time_Channels.Close (Watchdog_Chan);
      Scheduler.Shutdown;
      Assert (Waiter_Flag, "After(10ms) fired");
      Assert (not Watchdog_Hit, "watchdog did not fire");
   end Test_After;

   procedure Test_Timer_Stop (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Tm  : Timer := New_Timer (30 * Millisecond);
      Ctl : Timer := New_Timer (30 * Millisecond);
   begin
      Stop (Tm);   --  stopped before its 30ms deadline
      --  Positive control: an unstopped timer of the same duration
      --  MUST fire, so "stopped sent nothing" can actually fail.
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      for I in 1 .. 500 loop
         exit when Time_Channels.Length (Chan (Ctl)) > 0;
         delay 0.001;
      end loop;
      Scheduler.Shutdown;
      Assert (Time_Channels.Length (Chan (Ctl)) > 0,
              "control timer fired (test can fail)");
      Assert (Time_Channels.Length (Chan (Tm)) = 0,
              "stopped timer sent nothing despite elapsed deadline");
   end Test_Timer_Stop;

   procedure Test_Tick (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Tick_Count := 0;
      Tick_Chan := Tick (5 * Millisecond);
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Tick_Body'Access);
      for I in 1 .. 5_000 loop
         exit when Tick_Count >= 2;
         delay 0.001;
      end loop;
      --  Release the repeater task and wake a possibly-parked ticker
      --  goroutine so Shutdown's drain and the runner can exit.
      Stop_Channel (Tick_Chan);
      Time_Channels.Close (Tick_Chan);
      Scheduler.Shutdown;
      Assert (Tick_Count >= 2, "Tick fired at least twice, got"
              & Natural'Image (Tick_Count));
   end Test_Tick;

   procedure Test_Stop_All (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Tm : constant Timer := New_Timer (30 * Millisecond);
   begin
      --  Stop_All is what generated mains call before Scheduler.Shutdown;
      --  a pending timer must not fire afterwards.
      Stop_All;
      for I in 1 .. 150 loop
         exit when Time_Channels.Length (Chan (Tm)) > 0;
         delay 0.001;
      end loop;
      Assert (Time_Channels.Length (Chan (Tm)) = 0,
              "Stop_All silenced a pending timer");
   end Test_Stop_All;

end Time_Suite;
