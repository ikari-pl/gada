--  Gada.Std.Time — the Go `time` package, ported (Phase 6 wave 2).
--
--  Go's time.Time carries a wall clock and a monotonic reading; the
--  port stores both (Ada.Calendar.Time for the wall, Ada.Real_Time
--  for the monotonic clock) so Since/Until measure real elapsed time,
--  not wall adjustments. The display zone is a UTC flag on the value:
--  Now returns Local (Go's default), UTC()/Local() convert the zone.
--
--  Go's time.Duration is int64 nanoseconds — modelled as a derived
--  Long_Integer with the Go unit constants and String() formatting.
--
--  After/Tick/NewTimer are channels fed by dedicated Ada tasks that
--  block on Real_Time delays (one-shot and repeating), with a
--  protected Stop flag so Stop() prevents the pending send.

with Ada.Calendar;
with Ada.Real_Time;
with Gada.Async.Channels.Unbounded;

package Gada.Std.Time is

   ---------------------------------------------------------------
   --  Duration — Go's int64 nanoseconds
   ---------------------------------------------------------------

   type Duration is new Long_Integer;

   Nanosecond  : constant Duration := 1;
   Microsecond : constant Duration := 1_000;
   Millisecond : constant Duration := 1_000_000;
   Second      : constant Duration := 1_000_000_000;
   Minute      : constant Duration := 60 * Second;
   Hour        : constant Duration := 60 * Minute;

   --  "*", "/", unary "-" come from the inherited predefined operators
   --  of the derived type (declaring mixed Long_Integer profiles here
   --  would be ambiguous with them).
   function "+" (L, R : Duration) return Duration;
   function "-" (L, R : Duration) return Duration;
   function "<" (L, R : Duration) return Boolean;
   function "<=" (L, R : Duration) return Boolean;
   function ">" (L, R : Duration) return Boolean;
   function ">=" (L, R : Duration) return Boolean;
   function "=" (L, R : Duration) return Boolean;

   --  Go: func (d Duration) String() — "1h2m3.004s", "300ms", "1.5µs".
   --  Named To_String (Ada idiom; "String" would hide the type).
   function To_String (D : Duration) return String;

   function Nanoseconds (D : Duration) return Long_Integer;

   ---------------------------------------------------------------
   --  Time
   ---------------------------------------------------------------

   type Time is record
      Mono : Ada.Real_Time.Time;      --  monotonic reading
      Wall : Ada.Calendar.Time;       --  wall clock at the same instant
      Ns   : Natural := 0;            --  sub-second part of Wall
      UTC  : Boolean := False;        --  display zone (Go: Local default)
   end record;

   --  Go: time.Now() — Local zone, wall + monotonic.
   function Now return Time;

   --  Go: time.Date(y, m, d, h, mi, s, ns, loc).
   function Date (Year : Ada.Calendar.Year_Number;
                  Month : Ada.Calendar.Month_Number;
                  Day : Ada.Calendar.Day_Number;
                  Hour, Minute, Second : Natural;
                  Ns : Natural;
                  In_UTC : Boolean) return Time;

   --  Go: time.Since(t) — monotonic elapsed. Until maps to
   --  Until_K ("until" is reserved, same _K rule as New_K/Is_K).
   function Since (T : Time) return Duration;
   function Until_K (T : Time; U : Time) return Duration;

   --  Zone conversions (Go: t.UTC(), t.Local()) — same instant,
   --  different display zone.
   function UTC (T : Time) return Time;
   function Local (T : Time) return Time;

   --  Calendar accessors (Go: t.Year(), t.Month(), ...).
   function Year (T : Time) return Ada.Calendar.Year_Number;
   function Month (T : Time) return Ada.Calendar.Month_Number;
   function Day (T : Time) return Ada.Calendar.Day_Number;
   --  (Hour_Of/Minute_Of/Second_Of: the plain names are taken by the
   --  Duration unit constants Hour/Minute/Second.)
   function Hour_Of (T : Time) return Natural;
   function Minute_Of (T : Time) return Natural;
   function Second_Of (T : Time) return Natural;
   function Nanosecond_Of (T : Time) return Natural;

   --  Go: t.Format(time.RFC3339Nano) — v1 fixes the layout.
   function RFC3339_Nano (T : Time) return String;

   ---------------------------------------------------------------
   --  Timers — channels fed by Ada tasks on Real_Time delays
   ---------------------------------------------------------------

   package Time_Channels is
      new Gada.Async.Channels.Unbounded (Boolean);

   --  Timer_Core carries the channel + delay + stop flag; the timer
   --  tasks hold it by access (task discriminants must be access
   --  types, so the channel itself rides inside this protected).
   protected type Timer_Core is
      procedure Setup (Ch_Val : Time_Channels.Channel;
                     Dly_Val : Duration);
      function Ch return Time_Channels.Channel;
      function D return Duration;
      procedure Stop;
      function Stopped return Boolean;
   private
      Chan : Time_Channels.Channel := Time_Channels.No_Channel;
      Dly  : Duration := 0;
      S    : Boolean := False;
   end Timer_Core;

   type Timer_Core_Access is access all Timer_Core;

   --  Go: type Timer struct { C <-chan Time; ... }
   type Timer is record
      C    : Time_Channels.Channel;
      Core : Timer_Core_Access;
   end record;

   --  Go: time.NewTimer(d) — fires once after d on C.
   function New_Timer (D : Duration) return Timer;
   --  Go: timer.Stop() bool — v1: procedure; check Stopped after.
   procedure Stop (T : in out Timer);
   function Chan (T : Timer) return Time_Channels.Channel;

   --  Go: time.After(d) <-chan Time — one-shot channel.
   function After (D : Duration) return Time_Channels.Channel;

   --  Go: time.Tick(d) <-chan Time — repeating (leaky by design in Go).
   function Tick (D : Duration) return Time_Channels.Channel;

   --  v1 extension (Go's After/Tick expose no handle): stops the timer
   --  feeding Ch so its task terminates promptly. No-op if Ch is
   --  unknown or already stopped.
   procedure Stop_Channel (Ch : Time_Channels.Channel);

end Gada.Std.Time;
