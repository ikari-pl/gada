--  Body of Time_Suite — see spec for test rationale.
--
--  Channel receives must run inside goroutines (Park is a no-op in
--  the main task), so After/Tick tests spawn a waiter and the main
--  task polls a flag with Yield. A watchdog After keeps a broken
--  timer from hanging CI forever.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Environment_Variables;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Gada.Async.Scheduler;
with Gada.Std.Time; use Gada.Std.Time;
use type Gada.Std.Time.Time_Channels.Channel;

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
      Register_Routine
        (T, Test_Zones_Non_UTC'Access, "Warsaw/Kolkata zone splits");
      Register_Routine (T, Test_After'Access, "After fires");
      Register_Routine (T, Test_Timer_Stop'Access, "NewTimer + Stop");
      Register_Routine (T, Test_Nonpositive'Access,
                        "NewTimer/After/Tick with d <= 0");
      Register_Routine (T, Test_Tick'Access, "Tick repeats");
      Register_Routine (T, Test_Tick_Slow_Receiver'Access,
                        "Tick drops ticks for a slow receiver");
      Register_Routine (T, Test_Timer_Queue'Access,
                        "timer queue: many timers, earlier head kicks");
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
      --  Regression (#16): math.MinInt64 / MaxInt64 must not overflow.
      Assert (To_String (Gada.Std.Time.Duration'First) = "-2562047h47m16.854775808s",
              "MinInt64, got " & To_String (Gada.Std.Time.Duration'First));
      Assert (To_String (Gada.Std.Time.Duration'Last) = "2562047h47m16.854775807s",
              "MaxInt64, got " & To_String (Gada.Std.Time.Duration'Last));
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

   --  Pins the process time zone for a zone-dependent test: TZ plus
   --  tzset(3) so the C library re-reads it (GNAT's UTC_Time_Offset
   --  goes through localtime_r). Restore_TZ puts the host value back.
   procedure C_Tzset with Import, Convention => C, External_Name => "tzset";

   Saved_TZ     : Ada.Strings.Unbounded.Unbounded_String;
   Saved_TZ_Set : Boolean := False;

   procedure Set_TZ (Name : String) is
   begin
      if not Saved_TZ_Set then
         Saved_TZ_Set := Ada.Environment_Variables.Exists ("TZ");
         if Saved_TZ_Set then
            Saved_TZ := Ada.Strings.Unbounded.To_Unbounded_String
              (Ada.Environment_Variables.Value ("TZ"));
         end if;
      end if;
      Ada.Environment_Variables.Set ("TZ", Name);
      C_Tzset;
   end Set_TZ;

   procedure Restore_TZ is
   begin
      if Saved_TZ_Set then
         Ada.Environment_Variables.Set
           ("TZ", Ada.Strings.Unbounded.To_String (Saved_TZ));
      else
         Ada.Environment_Variables.Clear ("TZ");
      end if;
      Saved_TZ_Set := False;
      C_Tzset;
   end Restore_TZ;

   procedure Test_UTC_Local_Format (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Set_TZ ("UTC");
      declare
         D  : constant Time :=
           Date (2026, 11, 26, 7, 8, 9, 123_456_789, True);
         LU : constant Time := Local (UTC (D));
         DL : constant Time := Date (2026, 11, 26, 7, 8, 9, 123_456_789,
                                     False);
         U2 : constant Time := UTC (DL);
         L2 : constant Time := Local (DL);
      begin
         Assert (RFC3339_Nano (UTC (D)) = "2026-11-26T07:08:09.123456789Z",
                 "UTC format, got " & RFC3339_Nano (UTC (D)));
         Assert (RFC3339_Nano (LU) = "2026-11-26T07:08:09.123456789+00:00",
                 "Local under TZ=UTC, got " & RFC3339_Nano (LU));
         Assert (U2.UTC and then not L2.UTC,
                 "UTC() sets the zone flag, Local() keeps it");
         Assert (Nanosecond_Of (U2) = 123_456_789
                   and then Nanosecond_Of (L2) = 123_456_789,
                 "zone conversion keeps the instant");
      end;
      Restore_TZ;
   end Test_UTC_Local_Format;

   --  Regression (#2): Formatting splits defaulted to UTC while Calendar
   --  splits and Time_Of were local, and UTC()/Local() shifted the
   --  instant on top — every non-UTC host printed wrong hours. Pinned
   --  against Go for whole-hour (east and west of UTC) and half-hour zones.
   procedure Test_Zones_Non_UTC (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      type Case_Rec is record
         Zone, In_Local, Local_Date, Local_As_UTC, Midnight : access String;
      end record;
      Cases : constant array (1 .. 3) of Case_Rec :=
        [(new String'("Europe/Warsaw"),
          new String'("2026-11-26T08:08:09.123456789+01:00"),
          new String'("2026-11-26T07:08:09.123456789+01:00"),
          new String'("2026-11-26T06:08:09.123456789Z"),
          new String'("2026-11-27T00:30:00+01:00")),
         (new String'("Asia/Kolkata"),
          new String'("2026-11-26T12:38:09.123456789+05:30"),
          new String'("2026-11-26T07:08:09.123456789+05:30"),
          new String'("2026-11-26T01:38:09.123456789Z"),
          new String'("2026-11-27T05:00:00+05:30")),
         (new String'("America/New_York"),
          new String'("2026-11-26T02:08:09.123456789-05:00"),
          new String'("2026-11-26T07:08:09.123456789-05:00"),
          new String'("2026-11-26T12:08:09.123456789Z"),
          new String'("2026-11-26T18:30:00-05:00"))];
   begin
      for C of Cases loop
         Set_TZ (C.Zone.all);
         declare
            U : constant Time :=
              Date (2026, 11, 26, 7, 8, 9, 123_456_789, True);
            L : constant Time :=
              Date (2026, 11, 26, 7, 8, 9, 123_456_789, False);
            M : constant Time := Local (Date (2026, 11, 26, 23, 30, 0, 0,
                                              True));
         begin
            Assert (RFC3339_Nano (U) = "2026-11-26T07:08:09.123456789Z"
                      and then Hour_Of (U) = 7,
                    C.Zone.all & ": UTC date, got " & RFC3339_Nano (U));
            Assert (RFC3339_Nano (Local (U)) = C.In_Local.all,
                    C.Zone.all & ": UTC->Local, got "
                    & RFC3339_Nano (Local (U)));
            Assert (RFC3339_Nano (L) = C.Local_Date.all
                      and then Hour_Of (L) = 7 and then Minute_Of (L) = 8,
                    C.Zone.all & ": local date, got " & RFC3339_Nano (L));
            Assert (RFC3339_Nano (UTC (L)) = C.Local_As_UTC.all,
                    C.Zone.all & ": Local->UTC, got "
                    & RFC3339_Nano (UTC (L)));
            Assert (RFC3339_Nano (M) = C.Midnight.all
                      and then Day (M) = (if C.Midnight (10) = '7' then 27
                                          else 26)
                      and then Month (M) = 11 and then Year (M) = 2026,
                    C.Zone.all & ": date rolls with the hour, got "
                    & RFC3339_Nano (M));
         end;
      end loop;
      Restore_TZ;
   exception
      when others =>
         Restore_TZ;
         raise;
   end Test_Zones_Non_UTC;

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

   --  Wait up to Ms milliseconds for Ch to hold a value.
   function Wait_Value (Ch : Time_Channels.Channel; Ms : Positive)
     return Boolean is
   begin
      for I in 1 .. Ms loop
         if Time_Channels.Length (Ch) > 0 then
            return True;
         end if;
         delay 0.001;
      end loop;
      return Time_Channels.Length (Ch) > 0;
   end Wait_Value;

   procedure Test_Timer_Stop (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Tm  : constant Timer := New_Timer (20 * Millisecond);
      --  Control deadline strictly later than Tm's, so "Ctl fired"
      --  proves Tm's deadline had already passed (regression #14:
      --  with equal deadlines a no-op Stop could still pass).
      Ctl : constant Timer := New_Timer (80 * Millisecond);
   begin
      Assert (Stop (Tm), "Stop of a pending timer returns True");
      Assert (not Stop (Tm), "second Stop returns False");
      Assert (Wait_Value (Chan (Ctl), 5_000),
              "control timer fired (test can fail)");
      Assert (Time_Channels.Length (Chan (Tm)) = 0,
              "stopped timer sent nothing despite elapsed deadline");
      --  Stop after fire: Go's Stop returns False, the value stays.
      declare
         F : constant Timer := New_Timer (Millisecond);
      begin
         Assert (Wait_Value (Chan (F), 5_000), "1ms timer fired");
         Assert (not Stop (F), "Stop after fire returns False");
         Assert (Time_Channels.Length (Chan (F)) = 1,
                 "fired value stays in C");
      end;
      Stop (Ctl);  --  statement form on a fired timer: no-op
   end Test_Timer_Stop;

   --  Go: NewTimer/After with d <= 0 fire immediately; Tick(d <= 0)
   --  returns a nil channel and arms nothing (regression #9: it used
   --  to spin a task flooding the channel).
   procedure Test_Nonpositive (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      P0 : constant Natural := Pending_Timers;
      Z  : constant Timer := New_Timer (0);
      A  : constant Time_Channels.Channel := After (-5 * Second);
   begin
      Assert (Time_Channels.Length (Chan (Z)) = 1, "NewTimer(0) fired");
      Assert (not Stop (Z), "Stop on a fired d<=0 timer is False");
      Assert (Time_Channels.Length (A) = 1, "After(-5s) fired");
      Assert (Tick (0) = Time_Channels.No_Channel, "Tick(0) is nil");
      Assert (Tick (-Second) = Time_Channels.No_Channel,
              "Tick(-1s) is nil");
      Assert (Pending_Timers = P0, "d <= 0 queues nothing");
   end Test_Nonpositive;

   --  Regression (#8): a slow Tick receiver must not accumulate a
   --  backlog — Go's ticker channel holds one tick and drops the rest.
   procedure Test_Tick_Slow_Receiver (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Ch : constant Time_Channels.Channel := Tick (2 * Millisecond);
      V, OK : Boolean;
   begin
      delay 0.06;  --  ~30 periods without receiving
      Assert (Time_Channels.Length (Ch) = 1,
              "at most one pending tick, got"
              & Natural'Image (Time_Channels.Length (Ch)));
      --  Draining it lets the next tick through.
      Time_Channels.Receive (Ch, V, OK);
      Assert (OK, "pending tick received");
      Assert (Wait_Value (Ch, 5_000), "ticker keeps ticking");
      Stop_Channel (Ch);
   end Test_Tick_Slow_Receiver;

   --  Regressions (#12, #15): timers are queue entries, not tasks —
   --  many of them are cheap, register synchronously, and an earlier
   --  deadline inserted after a later one still fires on time (the
   --  service is kicked instead of oversleeping).
   procedure Test_Timer_Queue (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      P0   : constant Natural := Pending_Timers;
      Late : constant Timer := New_Timer (10 * Second);
      Huge : constant Timer := New_Timer (Gada.Std.Time.Duration'Last);
      Soon : Time_Channels.Channel;
      T0   : constant RT.Time := RT.Clock;
   begin
      Soon := After (5 * Millisecond);
      Assert (Pending_Timers = P0 + 3, "three timers queued");
      Assert (Wait_Value (Soon, 2_000), "earlier deadline fired");
      Assert (RT.To_Duration (RT."-" (RT.Clock, T0)) < 2.0,
              "fired well before the 10s head");
      Assert (Pending_Timers = P0 + 2, "fired one-shot left the queue");
      for I in 1 .. 10_000 loop
         declare
            Unused : constant Time_Channels.Channel := After (Hour);
         begin
            null;
         end;
      end loop;
      Assert (Pending_Timers = P0 + 10_002, "10k After entries queued");
      Assert (Stop (Late) and then Stop (Huge), "stop the long timers");
      Stop_All;
      Assert (Pending_Timers = 0, "Stop_All empties the queue");
      Assert (not Stop (Timer'(C => Soon, Node => null)),
              "Stop on a node-less Timer is False");
   end Test_Timer_Queue;

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
      Tk : constant Time_Channels.Channel := Tick (Millisecond);
   begin
      Stop_All;
      --  Positive control armed after Stop_All, due later than Tm: once
      --  it fires, Tm's deadline has passed, so an empty Tm proves
      --  Stop_All actually stopped it.
      declare
         Ctl : constant Timer := New_Timer (80 * Millisecond);
      begin
         Assert (Wait_Value (Chan (Ctl), 5_000),
                 "control timer fired (test can fail)");
      end;
      Assert (Time_Channels.Length (Chan (Tm)) = 0,
              "Stop_All silenced a pending timer");
      Assert (Time_Channels.Length (Tk) <= 1, "stopped ticker is quiet");
      Assert (Pending_Timers = 0, "nothing left queued");
   end Test_Stop_All;

end Time_Suite;
