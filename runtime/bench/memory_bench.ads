--  Memory_Bench — micro-benchmarks for `Gada.Core.Memory`.
--
--  These benchmarks exist primarily as the bench-harness scaffold's
--  smoke test — they run, produce numbers, and the numbers land in
--  runtime/PERF.md. The "real" target benchmarks come with each
--  later module (Slices, Maps, …).

with Gada_Bench;

package Memory_Bench is

   --  Register every benchmark in this suite with the harness.
   --  Called from runtime/bench/bench_runner.adb at startup.
   procedure Register_All;

   procedure Bench_Allocate_64
     (B : in out Gada_Bench.Benchmark_State);
   procedure Bench_Allocate_Atomic_64
     (B : in out Gada_Bench.Benchmark_State);
   procedure Bench_Allocate_Atomic_4K
     (B : in out Gada_Bench.Benchmark_State);

end Memory_Bench;
