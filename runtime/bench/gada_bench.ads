--  Gada_Bench — minimal in-tree benchmark harness for the GADA
--  runtime.
--
--  Methodology cribbed from Go's `testing.B`:
--    - Iteration count is auto-scaled until the inner loop runs for
--      at least Min_Time, so per-op timing is statistically
--      meaningful regardless of the unit-under-test's per-call cost.
--    - Wall clock via Ada.Real_Time.Clock for sub-microsecond
--      resolution.
--    - Allocation tracking via Gada.Core.Memory.Total_Bytes_Allocated
--      delta around the inner loop — libgc gives us the cumulative
--      total for free, so per-op B/op falls out of two snapshots.
--    - Output format compatible with `benchstat` so a future Go-side
--      comparison harness (Phase 11 validation) can ingest both
--      sides without reformatting.
--
--  Per docs/adr/0006-runtime-performance-bar.md.

with Ada.Real_Time;
with System.Storage_Elements;

package Gada_Bench is

   type Benchmark_State is private;

   --  Inside a benchmark function, loop Iter_Count times calling
   --  the unit under test. The runner scales this between calls.
   function Iter_Count (B : Benchmark_State) return Positive;

   --  Reset the timer and the byte-counter snapshots. Call this
   --  after any one-time setup that should not be billed against
   --  per-op cost.
   procedure Reset_Timer (B : in out Benchmark_State);

   type Benchmark_Procedure is access procedure
     (B : in out Benchmark_State);

   --  Run Bench, scaling the iteration count between attempts until
   --  the inner loop runs for at least Min_Time, then print one
   --  benchstat-format line to stdout:
   --
   --    Bench{Name}-1   ITERS   NS/op   B/op   N allocs/op
   --
   --  The "-1" suffix is GOMAXPROCS, fixed at 1 for the v1
   --  single-threaded runtime to stay benchstat-parseable.
   --
   --  Allocs/op is currently 0 in all reports because libgc does
   --  not expose per-allocation count via its public API; we
   --  derive bytes-per-op from `GC_get_total_bytes` deltas. The
   --  field is kept for benchstat compatibility and will become
   --  meaningful once the runtime tracks allocation calls itself.
   procedure Run
     (Name     : String;
      Bench    : Benchmark_Procedure;
      Min_Time : Duration := 1.0);

   --  Top-level entry: runs every Benchmark_Procedure registered
   --  via Register, then exits 0. Used by `bench_runner.adb`.
   procedure Register
     (Name  : String;
      Bench : Benchmark_Procedure);
   procedure Run_All (Min_Time : Duration := 1.0);

private

   type Benchmark_State is record
      Iters       : Positive := 1;
      --  Snapshots set by Run before calling Bench, optionally
      --  overwritten by Reset_Timer if the bench has setup work
      --  it doesn't want billed.
      Start_Time  : Ada.Real_Time.Time := Ada.Real_Time.Time_First;
      Start_Bytes : System.Storage_Elements.Storage_Count := 0;
   end record;

end Gada_Bench;
