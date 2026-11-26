--  Body of Gada.Std.Time — see spec for the Go-semantics contract.

with Ada.Calendar.Formatting;
with Ada.Calendar.Time_Zones;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with System;

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

   function To_String (D : Duration) return String is
      Ns : constant Long_Integer := Long_Integer (D);
      U  : constant Long_Integer := (if Ns < 0 then -Ns else Ns);
      B  : Unbounded_String;
   begin
      if Ns < 0 then
         Append (B, '-');
      end if;
      if U = 0 then
         return To_String (B) & "0s";
      elsif U < Long_Integer (Second) then
         if U < 1_000 then
            Append_Num (B, U);
            Append (B, "ns");
         elsif U < 1_000_000 then
            Append_Num (B, U / 1_000);
            Append_Frac (B, U mod 1_000, 3);
            Append (B, "µs");
         else
            Append_Num (B, U / 1_000_000);
            Append_Frac (B, U mod 1_000_000, 6);
            Append (B, "ms");
         end if;
      else
         declare
            H : constant Long_Integer := U / 3_600_000_000_000;
            M : constant Long_Integer :=
              (U mod 3_600_000_000_000) / 60_000_000_000;
            S : constant Long_Integer :=
              (U mod 60_000_000_000) / 1_000_000_000;
            F : constant Long_Integer := U mod 1_000_000_000;
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
      R    : constant RT.Time := RT.Clock;
      W    : constant Cal.Time := Cal.Clock;
      Secs : constant Cal.Day_Duration := Cal.Seconds (W);
      Frac : constant Cal.Day_Duration :=
        Secs - Cal.Day_Duration (Natural (Secs));
   begin
      --  Sub-second part from the wall clock (GNAT Calendar keeps
      --  millisecond resolution; the 124-year span since Time_First
      --  would overflow Duration, so don't go through To_Duration).
      --  Date() carries exact nanoseconds.
      return (Mono => R,
              Wall => W,
              Ns   => Natural (Long_Integer (Long_Float (Frac) * 1.0e9)),
              UTC  => False);
   end Now;

   function Date (Year : Cal.Year_Number;
                  Month : Cal.Month_Number;
                  Day : Cal.Day_Number;
                  Hour, Minute, Second : Natural;
                  Ns : Natural;
                  In_UTC : Boolean) return Time is
   begin
      return (Mono => RT.Clock,
              Wall => Cal.Time_Of
                (Year, Month, Day,
                 Cal.Day_Duration (Hour * 3600 + Minute * 60 + Second)),
              Ns   => Ns,
              UTC  => In_UTC);
   end Date;

   function Since (T : Time) return Duration is
   begin
      return Duration
        (Long_Integer (Long_Float (RT.To_Duration
           (RT."-" (RT.Clock, T.Mono))) * 1_000_000_000.0));
   end Since;

   function Until_K (T : Time; U : Time) return Duration is
   begin
      return Duration
        (Long_Integer (Long_Float (RT.To_Duration
           (RT."-" (U.Mono, T.Mono))) * 1_000_000_000.0));
   end Until_K;

   function UTC (T : Time) return Time is
     (Mono => T.Mono, Wall => T.Wall, Ns => T.Ns, UTC => True);
   function Local (T : Time) return Time is
     (Mono => T.Mono, Wall => T.Wall, Ns => T.Ns, UTC => False);

   function Year (T : Time) return Cal.Year_Number is
     (Cal.Year (T.Wall));
   function Month (T : Time) return Cal.Month_Number is
     (Cal.Month (T.Wall));
   function Day (T : Time) return Cal.Day_Number is
     (Cal.Day (T.Wall));
   function Hour_Of (T : Time) return Natural is
     (Natural (Fmt.Hour (T.Wall)));
   function Minute_Of (T : Time) return Natural is
     (Natural (Fmt.Minute (T.Wall)));
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

   --  "2026-11-26T07:08:09" from the wall clock.
   function Image_Date_Time (T : Time) return String is
   begin
      return Dig2 (Natural (Fmt.Year (T.Wall)))
        & '-' & Dig2 (Natural (Fmt.Month (T.Wall)))
        & '-' & Dig2 (Natural (Fmt.Day (T.Wall)))
        & 'T' & Dig2 (Natural (Fmt.Hour (T.Wall)))
        & ':' & Dig2 (Natural (Fmt.Minute (T.Wall)))
        & ':' & Dig2 (Natural (Fmt.Second (T.Wall)));
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
            Off  : constant Ada.Calendar.Time_Zones.Time_Offset :=
              Ada.Calendar.Time_Zones.UTC_Time_Offset (T.Wall);
            Mins : constant Integer := Integer (Off);
            Sign : constant Character :=
              (if Mins < 0 then '-' else '+');
            A    : constant Natural := (if Mins < 0 then -Mins else Mins);
         begin
            Append (B, Sign & Dig2 (A / 60) & ':' & Dig2 (A mod 60));
         end;
      end if;
      return To_String (B);
   end RFC3339_Nano;

   ---------------------------------------------------------------
   --  Timers
   ---------------------------------------------------------------

   protected body Timer_Core is

      procedure Setup (Ch_Val : Time_Channels.Channel;
                       Dly_Val : Duration) is
      begin
         Chan := Ch_Val;
         Dly  := Dly_Val;
      end Setup;

      function Ch return Time_Channels.Channel is (Chan);
      function D return Duration is (Dly);

      procedure Stop is
      begin
         S := True;
      end Stop;

      function Stopped return Boolean is (S);

   end Timer_Core;

   function To_Span (D : Duration) return Standard.Duration is
     (Standard.Duration (Long_Float (Long_Integer (D)) / 1.0e9));

   --  Timer tasks sleep in slices of at most Slice_Limit so a Stop
   --  is noticed within that bound and the task can terminate (a
   --  never-stopped Repeater would block its master's completion).
   Slice_Limit : constant Duration := 50 * Millisecond;

   --  Registry of live timers: pins the heap task objects for the GC
   --  and lets Stop_Channel find the timer feeding a bare channel.
   type Timer_Entry is record
      Core : Timer_Core_Access;
      Ch   : Time_Channels.Channel;
      Obj  : System.Address;
   end record;

   package Entry_Vectors is
      new Ada.Containers.Indefinite_Vectors (Positive, Timer_Entry);

   use type Time_Channels.Channel;

   protected type Keeper is
      procedure Register (Core : Timer_Core_Access;
                         Ch   : Time_Channels.Channel;
                         Obj  : System.Address);
      procedure Stop_For (Ch : Time_Channels.Channel);
   private
      Items : Entry_Vectors.Vector;
   end Keeper;

   protected body Keeper is
      procedure Register (Core : Timer_Core_Access;
                          Ch   : Time_Channels.Channel;
                          Obj  : System.Address) is
         E : constant Timer_Entry := (Core => Core, Ch => Ch, Obj => Obj);
      begin
         Items.Append (E);
      end Register;

      procedure Stop_For (Ch : Time_Channels.Channel) is
      begin
         for E of Items loop
            if E.Ch = Ch then
               E.Core.Stop;
            end if;
         end loop;
      end Stop_For;
   end Keeper;

   Keep : Keeper;

   --  Task discriminants must be access types; the protected core
   --  rides inside a heap record.
   type Timer_Rec is record
      Core : Timer_Core_Access;
   end record;

   type Timer_Rec_Access is access all Timer_Rec;

   --  No discriminants (GNAT rejects discriminant aggregates on task
   --  allocators here); the heap record is handed over via a Set entry.
   task type One_Shot is
      entry Set (Rec : Timer_Rec_Access);
   end One_Shot;

   type One_Shot_Access is access all One_Shot;

   task body One_Shot is
      R         : Timer_Rec_Access;
      Remaining : Duration;
      Slice     : Duration;
   begin
      accept Set (Rec : Timer_Rec_Access) do
         R := Rec;
      end Set;
      Remaining := R.Core.D;
      while Remaining > 0 and then not R.Core.Stopped loop
         Slice := (if Remaining < Slice_Limit then Remaining
                   else Slice_Limit);
         delay To_Span (Slice);
         Remaining := Remaining - Slice;
      end loop;
      if not R.Core.Stopped then
         Time_Channels.Send (R.Core.Ch, True);
      end if;
   end One_Shot;

   task type Repeater is
      entry Set (Rec : Timer_Rec_Access);
   end Repeater;

   type Repeater_Access is access all Repeater;

   task body Repeater is
      R         : Timer_Rec_Access;
      Remaining : Duration;
      Slice     : Duration;
   begin
      accept Set (Rec : Timer_Rec_Access) do
         R := Rec;
      end Set;
      loop
         Remaining := R.Core.D;
         while Remaining > 0 and then not R.Core.Stopped loop
            Slice := (if Remaining < Slice_Limit then Remaining
                      else Slice_Limit);
            delay To_Span (Slice);
            Remaining := Remaining - Slice;
         end loop;
         exit when R.Core.Stopped;
         Time_Channels.Send (R.Core.Ch, True);
      end loop;
   end Repeater;

   function New_Timer (D : Duration) return Timer is
      Core : constant Timer_Core_Access := new Timer_Core;
      Rec : constant Timer_Rec_Access := new Timer_Rec'(Core => Core);
      T   : constant One_Shot_Access := new One_Shot;
   begin
      Core.Setup (Time_Channels.Make, D);
      T.Set (Rec);
      Keep.Register (Core, Core.Ch, T.all'Address);
      return (C => Core.Ch, Core => Core);
   end New_Timer;

   procedure Stop (T : in out Timer) is
   begin
      T.Core.Stop;
   end Stop;

   function Chan (T : Timer) return Time_Channels.Channel is (T.C);

   procedure Stop_Channel (Ch : Time_Channels.Channel) is
   begin
      Keep.Stop_For (Ch);
   end Stop_Channel;

   function After (D : Duration) return Time_Channels.Channel is
      Core : constant Timer_Core_Access := new Timer_Core;
      Rec : constant Timer_Rec_Access := new Timer_Rec'(Core => Core);
      T   : constant One_Shot_Access := new One_Shot;
   begin
      Core.Setup (Time_Channels.Make, D);
      T.Set (Rec);
      Keep.Register (Core, Core.Ch, T.all'Address);
      return Core.Ch;
   end After;

   function Tick (D : Duration) return Time_Channels.Channel is
      Core : constant Timer_Core_Access := new Timer_Core;
      Rec : constant Timer_Rec_Access := new Timer_Rec'(Core => Core);
      T   : constant Repeater_Access := new Repeater;
   begin
      Core.Setup (Time_Channels.Make, D);
      T.Set (Rec);
      Keep.Register (Core, Core.Ch, T.all'Address);
      return Core.Ch;
   end Tick;

end Gada.Std.Time;
