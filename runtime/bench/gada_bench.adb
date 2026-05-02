--  Gada_Bench body — see spec for methodology overview.

--  Suppress -gnatw_a on the `new String'(Name)` allocator inside
--  `Register`: storing names by reference is the cleanest way to
--  hold a heterogeneous string set; per-callsite suppression would
--  be noisier than file-scope. Same trade-off as
--  runtime/tests/test_runner.adb (and tracked in
--  docs/imperfections.md).
pragma Warnings (Off, "use of an anonymous access type allocator");

with Ada.Text_IO;

with Gada.Core.Memory;

package body Gada_Bench is

   use type Ada.Real_Time.Time;
   use type Ada.Real_Time.Time_Span;

   --  Registry of (Name, Procedure) pairs. Bounded — 64 benchmarks
   --  is comfortably above what any one phase produces; doubling
   --  is a one-line change if we ever need it.
   type Bench_Entry is record
      Name : access constant String;
      Proc : Benchmark_Procedure;
   end record;

   Max_Bench_Count : constant := 64;
   Registered : array (1 .. Max_Bench_Count) of Bench_Entry;
   Bench_Count : Natural := 0;

   --  Forward declarations (-gnatys requires every body to follow a
   --  visible spec).
   function Next_Iters
     (Prev_Iters : Positive;
      Elapsed    : Ada.Real_Time.Time_Span;
      Target     : Duration) return Positive;

   ---------------------------------------------------------------
   --  Iteration scaling: from Go's testing.B. If the previous run
   --  took less than 1% of Min_Time, jump 100x. Otherwise scale by
   --  the elapsed-vs-target ratio with a 1.2x guard so we don't
   --  undershoot Min_Time on the next try.
   ---------------------------------------------------------------
   function Next_Iters
     (Prev_Iters : Positive;
      Elapsed    : Ada.Real_Time.Time_Span;
      Target     : Duration) return Positive
   is
      Elapsed_Sec : constant Duration := Ada.Real_Time.To_Duration (Elapsed);
      Ratio       : Float;
      Bumped      : Long_Long_Integer;
   begin
      if Elapsed_Sec <= 0.0 then
         return Prev_Iters * 100;
      end if;
      Ratio := Float (Target) / Float (Elapsed_Sec);
      Bumped := Long_Long_Integer (Float (Prev_Iters) * Ratio * 1.2);
      if Bumped <= Long_Long_Integer (Prev_Iters) then
         Bumped := Long_Long_Integer (Prev_Iters) * 2;
      end if;
      if Bumped > Long_Long_Integer (Positive'Last) then
         Bumped := Long_Long_Integer (Positive'Last);
      end if;
      return Positive (Bumped);
   end Next_Iters;

   ---------------------------------------------------------------
   --  Public surface
   ---------------------------------------------------------------

   function Iter_Count (B : Benchmark_State) return Positive is
   begin
      return B.Iters;
   end Iter_Count;

   procedure Reset_Timer (B : in out Benchmark_State) is
   begin
      B.Start_Time := Ada.Real_Time.Clock;
      B.Start_Bytes := Gada.Core.Memory.Total_Bytes_Allocated;
   end Reset_Timer;

   procedure Run
     (Name     : String;
      Bench    : Benchmark_Procedure;
      Min_Time : Duration := 1.0)
   is
      use Ada.Real_Time;
      use System.Storage_Elements;

      State        : Benchmark_State;
      Post_Bytes   : Storage_Count;
      Elapsed      : Time_Span;
      Elapsed_Sec  : Duration;
      Final_Iters  : Positive := 1;
      Bytes_Used   : Storage_Count;
      Ns_Per_Op    : Long_Long_Integer;
      Bytes_Per_Op : Long_Long_Integer;
   begin
      --  Ensure the GC is initialised so Total_Bytes_Allocated is
      --  meaningful. Idempotent.
      Gada.Core.Memory.Initialize;

      loop
         State.Iters := Final_Iters;
         State.Start_Bytes := Gada.Core.Memory.Total_Bytes_Allocated;
         State.Start_Time := Clock;

         Bench.all (State);

         --  Post-snapshots (Bench may have called Reset_Timer to
         --  overwrite Start_Time/Start_Bytes after one-time setup).
         Elapsed := Clock - State.Start_Time;
         Post_Bytes := Gada.Core.Memory.Total_Bytes_Allocated;
         Elapsed_Sec := To_Duration (Elapsed);

         exit when Elapsed_Sec >= Min_Time;
         Final_Iters := Next_Iters (Final_Iters, Elapsed, Min_Time);
      end loop;

      Bytes_Used := Post_Bytes - State.Start_Bytes;
      Ns_Per_Op :=
        Long_Long_Integer (Elapsed_Sec * 1_000_000_000.0)
        / Long_Long_Integer (Final_Iters);
      Bytes_Per_Op :=
        Long_Long_Integer (Bytes_Used)
        / Long_Long_Integer (Final_Iters);

      --  benchstat-compatible single line. The "-1" is GOMAXPROCS.
      Ada.Text_IO.Put_Line
        ("Benchmark" & Name & "-1"
         & ASCII.HT & Long_Long_Integer'Image (Long_Long_Integer (Final_Iters))
         & ASCII.HT & Long_Long_Integer'Image (Ns_Per_Op) & " ns/op"
         & ASCII.HT & Long_Long_Integer'Image (Bytes_Per_Op) & " B/op"
         & ASCII.HT & " 0 allocs/op");
   end Run;

   procedure Register
     (Name  : String;
      Bench : Benchmark_Procedure)
   is
   begin
      Bench_Count := Bench_Count + 1;
      Registered (Bench_Count) :=
        (Name => new String'(Name), Proc => Bench);
   end Register;

   procedure Run_All (Min_Time : Duration := 1.0) is
   begin
      for I in 1 .. Bench_Count loop
         Run (Registered (I).Name.all, Registered (I).Proc, Min_Time);
      end loop;
   end Run_All;

end Gada_Bench;
