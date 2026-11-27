--  Gada.Std.Time — the Go `time` package, ported (Phase 6 wave 2).
--
--  Go's time.Time carries a wall clock and a monotonic reading; the
--  port stores both (Ada.Calendar.Time for the wall, Ada.Real_Time
--  for the monotonic clock) so Since/Until measure real elapsed time,
--  not wall adjustments. Wall is always the true instant; the display
--  zone is a UTC flag on the value (Now returns Local, Go's default;
--  UTC()/Local() only flip it). Every calendar split and the RFC3339
--  rendering pass the display zone's offset explicitly (0, or the
--  host offset at that instant).
--
--  Go's time.Duration is int64 nanoseconds — modelled as a derived
--  Long_Integer with the Go unit constants and String() formatting.
--
--  After/Tick/NewTimer are channels fed by one timer-service task
--  that owns a deadline-ordered queue (see the Timers section).

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

   --  Go: time.Since(t) — monotonic elapsed. v1 Until_K is the
   --  binary U - T ("until" is reserved, same _K rule as New_K/Is_K);
   --  Go's unary time.Until(t) has no lowering yet.
   function Since (T : Time) return Duration;
   function Until_K (T : Time; U : Time) return Duration;

   --  Zone conversions (Go: t.UTC(), t.Local()) — same instant (Wall
   --  untouched), different display zone.
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
   --  Timers — one timer-service task over a deadline-ordered queue
   ---------------------------------------------------------------

   --  v1: the channel element is a dummy Boolean (Go delivers the
   --  firing time.Time; the port discards it — receives are usually
   --  `<-time.After(d)` in statement/select position).
   package Time_Channels is
      new Gada.Async.Channels.Unbounded (Boolean);

   --  One queue entry per live timer (heap, owned by the queue while
   --  pending). No task per timer: a single library-level service
   --  task sleeps until the earliest deadline and fires every entry
   --  that is due, so a time.After in a hot select loop costs one
   --  small heap node, not an OS thread.
   type Timer_Node is limited private;
   type Timer_Node_Access is access all Timer_Node;

   --  Go: type Timer struct { C <-chan Time; ... }
   type Timer is record
      C    : Time_Channels.Channel;
      Node : Timer_Node_Access;
   end record;

   --  Go: time.NewTimer(d) — fires once after d on C; d <= 0 fires
   --  immediately (the value is already in C on return).
   function New_Timer (D : Duration) return Timer;
   --  Go: timer.Stop() bool — True if the call stopped a pending
   --  timer, False if it had already fired or been stopped. As in Go
   --  (pre-1.23), a value already delivered stays in C.
   function Stop (T : Timer) return Boolean;
   --  Statement form of Stop (Go code usually discards the result).
   procedure Stop (T : Timer);
   function Chan (T : Timer) return Time_Channels.Channel;

   --  Go: time.After(d) <-chan Time — one-shot channel (d <= 0 fires
   --  immediately).
   function After (D : Duration) return Time_Channels.Channel;

   --  Go: time.Tick(d) <-chan Time — repeating. Like Go's ticker the
   --  channel holds at most one pending tick: a tick that comes due
   --  while the previous one is still unconsumed is dropped, so a slow
   --  receiver never builds a backlog. d <= 0 returns No_Channel (Go
   --  returns a nil channel) and arms nothing.
   function Tick (D : Duration) return Time_Channels.Channel;

   --  v1 extension (Go's After/Tick expose no handle): stops the timer
   --  feeding Ch. No-op if Ch is unknown, fired or already stopped.
   procedure Stop_Channel (Ch : Time_Channels.Channel);

   --  v1 extension: stops every pending timer (hand-written Ada that
   --  wants its environment task to finish while a Tick is live).
   procedure Stop_All;

   --  Number of timers currently queued (pending one-shots plus live
   --  tickers) — introspection for tests and deadlock detection.
   function Pending_Timers return Natural;

private

   type Timer_Node is limited record
      Ch       : Time_Channels.Channel;
      Deadline : Ada.Real_Time.Time := Ada.Real_Time.Time_First;
      --  Zero for a one-shot; the tick interval for Tick.
      Period   : Ada.Real_Time.Time_Span := Ada.Real_Time.Time_Span_Zero;
      Queued   : Boolean := False;
      Prev     : Timer_Node_Access;
      Next     : Timer_Node_Access;
   end record;

end Gada.Std.Time;
