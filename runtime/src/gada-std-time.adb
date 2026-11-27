--  Body of Gada.Std.Time — see spec for the Go-semantics contract.

with Ada.Calendar.Formatting;
with Ada.Calendar.Time_Zones;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;

package body Gada.Std.Time is

   package RT renames Ada.Real_Time;
   package Cal renames Ada.Calendar;
   package Fmt renames Ada.Calendar.Formatting;

   function "+" (L, R : Duration) return Duration is
     (Duration (Long_Integer (L) + Long_Integer (R)));
   function "-" (L, R : Duration) return Duration is
     (Duration (Long_Integer (L) - Long_Integer (R)));
   function "<" (L, R : Duration) return Boolean is
     (Long_Integer (L) < Long_Integer (R));
   function "<=" (L, R : Duration) return Boolean is
     (Long_Integer (L) <= Long_Integer (R));
   function ">" (L, R : Duration) return Boolean is
     (Long_Integer (L) > Long_Integer (R));
   function ">=" (L, R : Duration) return Boolean is
     (Long_Integer (L) >= Long_Integer (R));
   function "=" (L, R : Duration) return Boolean is
     (Long_Integer (L) = Long_Integer (R));

   function Nanoseconds (D : Duration) return Long_Integer is
     (Long_Integer (D));

   ---------------------------------------------------------------
   --  Duration.String — Go's algorithm: largest units first, the
   --  fraction printed with trailing zeros trimmed.
   ---------------------------------------------------------------

   --  Appends N >= 0 as decimal digits (no padding). Callers pass
   --  magnitudes only (To_String emits the sign itself).
   procedure Append_Num (B : in out Unbounded_String; N : Long_Integer) is
      Digs : constant String := Long_Integer'Image (N);
   begin
      --  'Image has a leading space for non-negative values.
      Append (B, Digs (Digs'First + 1 .. Digs'Last));
   end Append_Num;

   --  Appends R as a Width-digit fraction with trailing zeros trimmed.
   procedure Append_Frac (B : in out Unbounded_String; R : Long_Integer;
                          Width : Positive) is
      Digs : constant String := Long_Integer'Image (R);
      D      : constant String := Digs (Digs'First + 1 .. Digs'Last);
      S      : String (1 .. Width);
   begin
      if D'Length >= Width then
         S := D (D'Last - Width + 1 .. D'Last);
      else
         S := (1 .. Width - D'Length => '0') & D;
      end if;
      declare
         Last : Natural := Width;
      begin
         while Last > 0 and then S (Last) = '0' loop
            Last := Last - 1;
         end loop;
         if Last > 0 then
            Append (B, '.' & S (1 .. Last));
         end if;
      end;
   end Append_Frac;

   use type Interfaces.Unsigned_64;

   --  |N| in Unsigned_64: -Long_Integer'First overflows Long_Integer.
   function Magnitude (N : Long_Integer) return Interfaces.Unsigned_64 is
     (if N < 0 then Interfaces.Unsigned_64 (-(N + 1)) + 1
      else Interfaces.Unsigned_64 (N));

   function To_String (D : Duration) return String is
      Ns : constant Long_Integer := Long_Integer (D);
      --  Magnitude in Unsigned_64: -Long_Integer'First overflows
      --  (Go's math.MinInt64 Duration prints "-2562047h47m16.854775808s").
      U  : constant Interfaces.Unsigned_64 := Magnitude (Ns);
      function L (X : Interfaces.Unsigned_64) return Long_Integer is
        (Long_Integer (X));
      B  : Unbounded_String;
   begin
      if Ns < 0 then
         Append (B, '-');
      end if;
      if U = 0 then
         return To_String (B) & "0s";
      elsif U < Interfaces.Unsigned_64 (Second) then
         if U < 1_000 then
            Append_Num (B, L (U));
            Append (B, "ns");
         elsif U < 1_000_000 then
            Append_Num (B, L (U / 1_000));
            Append_Frac (B, L (U mod 1_000), 3);
            Append (B, "µs");
         else
            Append_Num (B, L (U / 1_000_000));
            Append_Frac (B, L (U mod 1_000_000), 6);
            Append (B, "ms");
         end if;
      else
         declare
            H : constant Long_Integer := L (U / 3_600_000_000_000);
            M : constant Long_Integer :=
              L ((U mod 3_600_000_000_000) / 60_000_000_000);
            S : constant Long_Integer :=
              L ((U mod 60_000_000_000) / 1_000_000_000);
            F : constant Long_Integer := L (U mod 1_000_000_000);
         begin
            if H > 0 then
               Append_Num (B, H);
               Append (B, 'h');
            end if;
            if H > 0 or else M > 0 then
               Append_Num (B, M);
               Append (B, 'm');
            end if;
            Append_Num (B, S);
            Append_Frac (B, F, 9);
            Append (B, 's');
         end;
      end if;
      return To_String (B);
   end To_String;

   ---------------------------------------------------------------
   --  Time
   ---------------------------------------------------------------

   function Now return Time is
      R : constant RT.Time := RT.Clock;
      W : constant Cal.Time := Cal.Clock;
   begin
      --  Sub-second part from the wall clock (GNAT Calendar keeps
      --  millisecond resolution; the 124-year span since Time_First
      --  would overflow Duration, so don't go through To_Duration).
      --  Date() carries exact nanoseconds.
      return (Mono => R,
              Wall => W,
              Ns   => Natural
                (Long_Integer (Long_Float (Cal.Seconds (W)) * 1.0e9)
                 mod 1_000_000_000),
              UTC  => False);
   end Now;

   package TZ renames Ada.Calendar.Time_Zones;

   --  The display zone's offset at T's instant: 0 for UTC, the host
   --  zone's offset (DST-aware) for Local. Wall always holds the true
   --  instant; every split passes this explicitly, because
   --  Ada.Calendar.Formatting defaults to UTC while Ada.Calendar's own
   --  Year/Month/Day/Time_Of use the host zone.
   function Zone (T : Time) return TZ.Time_Offset is
     (if T.UTC then 0 else TZ.UTC_Time_Offset (T.Wall));

   function Date (Year : Cal.Year_Number;
                  Month : Cal.Month_Number;
                  Day : Cal.Day_Number;
                  Hour, Minute, Second : Natural;
                  Ns : Natural;
                  In_UTC : Boolean) return Time is
      Secs : constant Cal.Day_Duration :=
        Cal.Day_Duration (Hour * 3600 + Minute * 60 + Second);
      --  Components read as UTC first; for Local, re-read them in the
      --  host offset in force at (approximately) that instant.
      As_UTC : constant Cal.Time :=
        Fmt.Time_Of (Year, Month, Day, Secs, Time_Zone => 0);
      Off    : constant TZ.Time_Offset :=
        (if In_UTC then 0 else TZ.UTC_Time_Offset (As_UTC));
   begin
      return (Mono => RT.Clock,
              Wall => Fmt.Time_Of (Year, Month, Day, Secs,
                                   Time_Zone => Off),
              Ns   => Ns,
              UTC  => In_UTC);
   end Date;

   --  Real_Time span as Go nanoseconds.
   function To_Ns (S : RT.Time_Span) return Duration is
     (Duration (Long_Integer (Long_Float (RT.To_Duration (S)) * 1.0e9)));

   function Since (T : Time) return Duration is
     (To_Ns (RT."-" (RT.Clock, T.Mono)));

   function Until_K (T : Time; U : Time) return Duration is
     (To_Ns (RT."-" (U.Mono, T.Mono)));

   --  Zone conversions (Go: same instant, other zone): only the
   --  display flag changes; Wall is the instant either way.
   function UTC (T : Time) return Time is
     ((T with delta UTC => True));

   function Local (T : Time) return Time is
     ((T with delta UTC => False));

   function Year (T : Time) return Cal.Year_Number is
     (Fmt.Year (T.Wall, Time_Zone => Zone (T)));
   function Month (T : Time) return Cal.Month_Number is
     (Fmt.Month (T.Wall, Time_Zone => Zone (T)));
   function Day (T : Time) return Cal.Day_Number is
     (Fmt.Day (T.Wall, Time_Zone => Zone (T)));
   function Hour_Of (T : Time) return Natural is
     (Natural (Fmt.Hour (T.Wall, Time_Zone => Zone (T))));
   function Minute_Of (T : Time) return Natural is
     (Natural (Fmt.Minute (T.Wall, Time_Zone => Zone (T))));
   function Second_Of (T : Time) return Natural is
     (Natural (Fmt.Second (T.Wall)));
   function Nanosecond_Of (T : Time) return Natural is (T.Ns);

   function Dig2 (N : Natural) return String is
      Img : constant String := Natural'Image (N);
   begin
      --  'Image has a leading space for non-negative values.
      if N < 10 then
         return '0' & Img (Img'Last);
      else
         return Img (Img'First + 1 .. Img'Last);
      end if;
   end Dig2;

   --  "2026-11-26T07:08:09" in T's display zone.
   function Image_Date_Time (T : Time) return String is
   begin
      return Dig2 (Natural (Year (T)))
        & '-' & Dig2 (Natural (Month (T)))
        & '-' & Dig2 (Natural (Day (T)))
        & 'T' & Dig2 (Hour_Of (T))
        & ':' & Dig2 (Minute_Of (T))
        & ':' & Dig2 (Second_Of (T));
   end Image_Date_Time;

   --  "2026-11-26T07:08:09.123456789Z" (UTC) or "…+01:00" (Local).
   function RFC3339_Nano (T : Time) return String is
      B : Unbounded_String;
   begin
      Append (B, Image_Date_Time (T));
      Append_Frac (B, Long_Integer (T.Ns), 9);
      if T.UTC then
         Append (B, 'Z');
      else
         declare
            Mins : constant Integer := Integer (Zone (T));
            Sign : constant Character := (if Mins < 0 then '-' else '+');
            A    : constant Natural := (if Mins < 0 then -Mins else Mins);
         begin
            Append (B, Sign & Dig2 (A / 60) & ':' & Dig2 (A mod 60));
         end;
      end if;
      return To_String (B);
   end RFC3339_Nano;

   ---------------------------------------------------------------
   --  Timers
   --
   --  Queue is a protected, deadline-ordered intrusive doubly linked
   --  list of Timer_Nodes (O(1) Stop; insertion scans from the tail,
   --  O(1) for the common "new deadline is the latest" case). Service
   --  is the single timer task: it sleeps until the head deadline and
   --  calls Fire_Due, which delivers every due entry *inside* the
   --  protected action — so a Stop either removes a pending entry
   --  (returns True, nothing is ever sent) or finds it gone (it fired;
   --  returns False). Inserting a new head deadline kicks Service so
   --  it re-reads the queue instead of oversleeping. With nothing
   --  queued Service waits on an accept with a terminate alternative,
   --  so it never keeps a program's environment task alive by itself.
   ---------------------------------------------------------------

   use type RT.Time;
   use type RT.Time_Span;
   use type Time_Channels.Channel;

   protected Queue is
      --  Link N in deadline order (FIFO among equal deadlines).
      --  New_Head is True when N became the earliest deadline.
      procedure Insert (N : Timer_Node_Access; New_Head : out Boolean);
      --  Unlink N if queued; Was_Queued reports whether it was.
      procedure Remove (N : Timer_Node_Access; Was_Queued : out Boolean);
      --  Unlink the first queued node feeding Ch, if any.
      procedure Remove_Channel (Ch : Time_Channels.Channel);
      procedure Clear;
      --  Earliest deadline, if anything is queued.
      procedure Earliest (At_Time : out RT.Time; Any : out Boolean);
      --  Deliver every entry due at Now: one-shots send and leave the
      --  queue; tickers send only into an empty channel (Go's cap-1
      --  drop) and re-queue one period on.
      procedure Fire_Due (Now : RT.Time);
      function Count return Natural;
   private
      Head, Tail : Timer_Node_Access;
      N_Queued   : Natural := 0;
   end Queue;

   protected body Queue is

      procedure Unlink (N : Timer_Node_Access) is
      begin
         if N.Prev = null then
            Head := N.Next;
         else
            N.Prev.Next := N.Next;
         end if;
         if N.Next = null then
            Tail := N.Prev;
         else
            N.Next.Prev := N.Prev;
         end if;
         N.Prev   := null;
         N.Next   := null;
         N.Queued := False;
         N_Queued := N_Queued - 1;
      end Unlink;

      procedure Link (N : Timer_Node_Access) is
         After_Node : Timer_Node_Access := Tail;
      begin
         while After_Node /= null
           and then After_Node.Deadline > N.Deadline
         loop
            After_Node := After_Node.Prev;
         end loop;
         N.Prev := After_Node;
         if After_Node = null then
            N.Next := Head;
            Head   := N;
         else
            N.Next := After_Node.Next;
            After_Node.Next := N;
         end if;
         if N.Next = null then
            Tail := N;
         else
            N.Next.Prev := N;
         end if;
         N.Queued := True;
         N_Queued := N_Queued + 1;
      end Link;

      procedure Insert (N : Timer_Node_Access; New_Head : out Boolean) is
      begin
         Link (N);
         New_Head := Head = N;
      end Insert;

      procedure Remove (N : Timer_Node_Access; Was_Queued : out Boolean) is
      begin
         Was_Queued := N.Queued;
         if Was_Queued then
            Unlink (N);
         end if;
      end Remove;

      procedure Remove_Channel (Ch : Time_Channels.Channel) is
         N : Timer_Node_Access := Head;
      begin
         while N /= null loop
            if N.Ch = Ch then
               Unlink (N);
               return;
            end if;
            N := N.Next;
         end loop;
      end Remove_Channel;

      procedure Clear is
      begin
         while Head /= null loop
            Unlink (Head);
         end loop;
      end Clear;

      procedure Earliest (At_Time : out RT.Time; Any : out Boolean) is
      begin
         Any := Head /= null;
         At_Time := (if Any then Head.Deadline else RT.Time_Last);
      end Earliest;

      procedure Fire_Due (Now : RT.Time) is
         N : Timer_Node_Access;
      begin
         while Head /= null and then Head.Deadline <= Now loop
            N := Head;
            Unlink (N);
            if N.Period = RT.Time_Span_Zero then
               Time_Channels.Send (N.Ch, True);
            else
               if Time_Channels.Length (N.Ch) = 0 then
                  Time_Channels.Send (N.Ch, True);
               end if;
               --  Next tick one period on; if the service fell behind
               --  by more than a period, realign on Now (dropping the
               --  missed ticks, as Go's runtime timer does).
               N.Deadline := N.Deadline + N.Period;
               if N.Deadline <= Now then
                  N.Deadline := Now + N.Period;
               end if;
               Link (N);
            end if;
         end loop;
      end Fire_Due;

      function Count return Natural is (N_Queued);

   end Queue;

   task Service is
      entry Kick;
   end Service;

   task body Service is
      Next : RT.Time;
      Any  : Boolean;
   begin
      loop
         Queue.Earliest (Next, Any);
         if Any then
            select
               accept Kick;
            or
               delay until Next;
               Queue.Fire_Due (RT.Clock);
            end select;
         else
            select
               accept Kick;
            or
               terminate;
            end select;
         end if;
      end loop;
   end Service;

   --  Durations beyond this are "never" in practice (and would
   --  overflow Integer seconds / Real_Time arithmetic): such timers
   --  are queued at Time_Last and never come due.
   Max_Seconds : constant Long_Integer := 10 * 366 * 86_400;

   function Is_Never (D : Duration) return Boolean is
     (Long_Integer (D) / 1_000_000_000 > Max_Seconds);

   --  D (0 < D, not Is_Never) as a Real_Time span, nanosecond-exact.
   function Span_Of (D : Duration) return RT.Time_Span is
     (RT.Seconds (Integer (Long_Integer (D) / 1_000_000_000))
      + RT.Nanoseconds (Integer (Long_Integer (D) mod 1_000_000_000)));

   --  Queue a fresh node for Ch due after D (D > 0). Periodic nodes
   --  re-arm every D.
   function Arm (Ch : Time_Channels.Channel; D : Duration;
                 Periodic : Boolean) return Timer_Node_Access is
      N        : constant Timer_Node_Access := new Timer_Node;
      New_Head : Boolean;
   begin
      N.Ch := Ch;
      if Is_Never (D) then
         N.Deadline := RT.Time_Last;
      else
         N.Deadline := RT.Clock + Span_Of (D);
         if Periodic then
            N.Period := Span_Of (D);
         end if;
      end if;
      Queue.Insert (N, New_Head);
      if New_Head then
         --  Service may be sleeping on a later deadline (or waiting
         --  with nothing queued): make it re-read the head.
         Service.Kick;
      end if;
      return N;
   end Arm;

   --  One-shot on a fresh channel: d <= 0 delivers at once (Go fires
   --  such timers immediately); otherwise a queued node.
   function One_Shot (D : Duration) return Timer is
      Ch : constant Time_Channels.Channel := Time_Channels.Make;
   begin
      if D <= 0 then
         Time_Channels.Send (Ch, True);
         return (C => Ch, Node => new Timer_Node'(Ch => Ch, others => <>));
      end if;
      return (C => Ch, Node => Arm (Ch, D, Periodic => False));
   end One_Shot;

   function New_Timer (D : Duration) return Timer is (One_Shot (D));

   function Stop (T : Timer) return Boolean is
      Was_Queued : Boolean := False;
   begin
      if T.Node /= null then
         Queue.Remove (T.Node, Was_Queued);
      end if;
      return Was_Queued;
   end Stop;

   procedure Stop (T : Timer) is
      Unused : constant Boolean := Stop (T);
   begin
      null;
   end Stop;

   function Chan (T : Timer) return Time_Channels.Channel is (T.C);

   procedure Stop_Channel (Ch : Time_Channels.Channel) is
   begin
      Queue.Remove_Channel (Ch);
   end Stop_Channel;

   procedure Stop_All is
   begin
      Queue.Clear;
   end Stop_All;

   function Pending_Timers return Natural is (Queue.Count);

   function After (D : Duration) return Time_Channels.Channel is
     (One_Shot (D).C);

   function Tick (D : Duration) return Time_Channels.Channel is
   begin
      if D <= 0 then
         return Time_Channels.No_Channel;
      end if;
      declare
         Ch     : constant Time_Channels.Channel := Time_Channels.Make;
         Unused : constant Timer_Node_Access :=
           Arm (Ch, D, Periodic => True);
      begin
         return Ch;
      end;
   end Tick;

end Gada.Std.Time;
