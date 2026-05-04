--  Scheduler_Bench body — Gada.Async.Scheduler micro-benchmarks.
--
--  Three rows captured against the Phase 3 (sub-items 3a + 3b + 3d)
--  surface:
--
--    * Scheduler_Spawn_1W — Init (Workers => 1), spawn N empty
--      goroutines, Shutdown. Per-op cost = (spawn + worker pickup +
--      empty body run + reap) / N. The single-worker shape isolates
--      raw allocation + run-queue + libco trampoline overhead from
--      multi-worker contention.
--
--    * Scheduler_Spawn_NW — same shape with Init (Workers => 0),
--      defaulting to System.Multiprocessors.Number_Of_CPUs. Compared
--      against Spawn_1W this is the multi-worker throughput row; the
--      ratio Spawn_1W/Spawn_NW gives per-CPU speedup. The shared FIFO
--      run queue caps speedup below Number_Of_CPUs (work-stealing,
--      sub-item 3c, will close some of that gap).
--
--    * Scheduler_Yield — single goroutine yielding N times against
--      one worker. Measures the libco co_switch round-trip cost +
--      State=YIELDED handoff through the per-worker Inbox + protected
--      requeue (3d). This is the dominant cost on every Park, channel
--      send/recv, and select wait that arrives in items 4–6.
--
--  Each bench body does Init → Reset_Timer → loop → Shutdown once per
--  harness call. The Gada_Bench harness scales Iter_Count between
--  calls until the inner loop runs for >= Min_Time, so per-op timing
--  averages over a million-plus operations and the per-call
--  Init/Shutdown overhead amortises away.

with Interfaces;

with Gada_Bench;
with Gada.Async.Scheduler;

package body Scheduler_Bench is

   use Interfaces;

   --  How many times Yielding_Body should yield before returning.
   --  Set by Bench_Yield from the harness's Iter_Count; read by the
   --  goroutine body. Volatile because the body runs on a worker
   --  task while the bench setup runs on the main task — without
   --  Volatile the optimiser is free to hoist the read out of the
   --  for-loop bound in Yielding_Body.
   Yield_Iters : Natural := 0
     with Volatile;

   --  Anti-dead-code-elimination sink. Empty_Body increments this
   --  on each call; without an observable side effect, gnat at -O2
   --  is allowed to prove the indirect call through Goroutine_Body
   --  is pure-and-unused and elide the whole worker dispatch.
   --
   --  Multi-worker reads/writes race here on Spawn_NW. We never read
   --  the value back, so the race is benign for measurement — the
   --  store is what matters as a fence against the optimiser. (If we
   --  ever need a true cross-worker counter, switch to a protected
   --  object or an atomic_64 RMW; today neither is needed.)
   Sink : Interfaces.Unsigned_64 := 0
     with Volatile;

   procedure Empty_Body;
   procedure Yielding_Body;

   procedure Empty_Body is
   begin
      Sink := Sink + 1;
   end Empty_Body;

   procedure Yielding_Body is
   begin
      for I in 1 .. Yield_Iters loop
         Gada.Async.Scheduler.Yield;
      end loop;
   end Yielding_Body;

   procedure Bench_Spawn_1W
     (B : in out Gada_Bench.Benchmark_State);
   procedure Bench_Spawn_NW
     (B : in out Gada_Bench.Benchmark_State);
   procedure Bench_Yield
     (B : in out Gada_Bench.Benchmark_State);

   ---------------------------------------------------------------
   --  Spawn cost, single worker. Init/Shutdown are billed before
   --  Reset_Timer / after the inner loop, but the loop body is
   --  the spawn call only — Shutdown drains as part of teardown
   --  and is included in the wall-clock window because that is the
   --  "spawn-to-reap" cost the cron prompt asked for.
   ---------------------------------------------------------------
   procedure Bench_Spawn_1W
     (B : in out Gada_Bench.Benchmark_State)
   is
      N : constant Positive := Gada_Bench.Iter_Count (B);
      G : Gada.Async.Scheduler.Goroutine_Id;
      pragma Unreferenced (G);
   begin
      Gada.Async.Scheduler.Init (Workers => 1);
      Gada_Bench.Reset_Timer (B);
      for I in 1 .. N loop
         G := Gada.Async.Scheduler.Spawn (Empty_Body'Access);
      end loop;
      Gada.Async.Scheduler.Shutdown;
   end Bench_Spawn_1W;

   ---------------------------------------------------------------
   --  Spawn cost, multi-worker (Number_Of_CPUs). Same shape as
   --  Bench_Spawn_1W. Ratio against Spawn_1W is the speedup.
   ---------------------------------------------------------------
   procedure Bench_Spawn_NW
     (B : in out Gada_Bench.Benchmark_State)
   is
      N : constant Positive := Gada_Bench.Iter_Count (B);
      G : Gada.Async.Scheduler.Goroutine_Id;
      pragma Unreferenced (G);
   begin
      Gada.Async.Scheduler.Init (Workers => 0);
      Gada_Bench.Reset_Timer (B);
      for I in 1 .. N loop
         G := Gada.Async.Scheduler.Spawn (Empty_Body'Access);
      end loop;
      Gada.Async.Scheduler.Shutdown;
   end Bench_Spawn_NW;

   ---------------------------------------------------------------
   --  Yield ping-pong. Spawn one goroutine that yields N times,
   --  Shutdown when it finishes. Per-op cost = libco co_switch
   --  round-trip + protected per-worker Inbox push/pop + state
   --  transition. The N here is set via the file-local Yield_Iters
   --  global because Goroutine_Body is `access procedure` with no
   --  parameter slot — same pattern slices_bench uses with its
   --  Volatile Sink_Slot.
   ---------------------------------------------------------------
   procedure Bench_Yield
     (B : in out Gada_Bench.Benchmark_State)
   is
      N : constant Positive := Gada_Bench.Iter_Count (B);
      G : Gada.Async.Scheduler.Goroutine_Id;
      pragma Unreferenced (G);
   begin
      Gada.Async.Scheduler.Init (Workers => 1);
      Yield_Iters := N;
      Gada_Bench.Reset_Timer (B);
      G := Gada.Async.Scheduler.Spawn (Yielding_Body'Access);
      Gada.Async.Scheduler.Shutdown;
   end Bench_Yield;

   ---------------------------------------------------------------
   --  Registration — wired into bench_runner.adb sequence after
   --  Maps_Bench.Register_All so phase ordering in the output
   --  follows the layered runtime (Core → Async).
   ---------------------------------------------------------------
   procedure Register_All is
   begin
      Gada_Bench.Register
        ("Scheduler_Spawn_1W", Bench_Spawn_1W'Access);
      Gada_Bench.Register
        ("Scheduler_Spawn_NW", Bench_Spawn_NW'Access);
      Gada_Bench.Register
        ("Scheduler_Yield", Bench_Yield'Access);
   end Register_All;

end Scheduler_Bench;
