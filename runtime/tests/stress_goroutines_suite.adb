--  Body of Stress_Goroutines_Suite — see spec for design notes.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;
with Gada.Async.Scheduler;

package body Stress_Goroutines_Suite is

   overriding function Name
     (T : Stress_Goroutines_Test) return AUnit.Message_String is
     (AUnit.Format
        ("GADA goroutine-leak stress suite (PKG=stress.goroutines)"));

   --  ## Run_Counter — race-safe tally of completed goroutine bodies
   --
   --  Unlike Stress_Scheduler_Suite, this test runs at the *default*
   --  worker count (Number_Of_CPUs >= 2 on every CI runner) so that the
   --  leak gate exercises real multi-worker spawn fan-out and teardown.
   --  At that concurrency a plain `Counter := @ + 1` on an Atomic
   --  Natural would lose increments (the Atomic aspect makes the load
   --  and store individually tear-free but does NOT fuse the read-
   --  modify-write into an atomic add). A protected object serialises
   --  the increments instead — the same pattern Scheduler_Suite's
   --  Worker_Recorder uses for its multi-worker observation surface.
   --
   --  Value is the only observable proxy for "every spawned body ran
   --  exactly once": the 100k goroutines each call Bump, and the test
   --  asserts Value = 100_000 after Shutdown. A dropped goroutine
   --  undershoots; a record reused while still live (a reaping leak)
   --  double-runs and overshoots.
   protected Run_Counter is
      procedure Bump;
      procedure Reset;
      function  Value return Natural;
   private
      Count : Natural := 0;
   end Run_Counter;

   protected body Run_Counter is

      procedure Bump is
      begin
         Count := @ + 1;
      end Bump;

      procedure Reset is
      begin
         Count := 0;
      end Reset;

      function Value return Natural is (Count);

   end Run_Counter;

   --  Goroutine body: spawned 100k times. Returns naturally after a
   --  single Bump so the worker takes the DONE reap arm (Free_Goroutine
   --  + co_delete) rather than the YIELDED / PARKED limbo arms. The
   --  body is parameterless (Goroutine_Body is `access procedure`),
   --  reaching file-scope Run_Counter exactly like Scheduler_Suite's
   --  bodies reach their globals.
   procedure Tally_And_Return;

   procedure Tally_And_Return is
   begin
      Run_Counter.Bump;
   end Tally_And_Return;

   overriding procedure Register_Tests
     (T : in out Stress_Goroutines_Test)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_100k_Spawn_Complete_Returns_To_Baseline'Access,
         "spawning + completing 100k goroutines runs every body "
         & "exactly once (no drops, no double-runs => no leaked or "
         & "stuck goroutine records), and a clean second Init/Spawn/"
         & "Shutdown cycle afterwards still tallies exactly — proving "
         & "the worker pool tore down to baseline and nothing bled "
         & "across the Shutdown barrier");
   end Register_Tests;

   procedure Test_100k_Spawn_Complete_Returns_To_Baseline
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use Gada.Async.Scheduler;
      Unused_G : Goroutine_Id;

      --  100_000 spawn-and-return goroutines, driven in bounded batches.
      --  Each live goroutine owns a 256 KB libco stack; if the worker's
      --  DONE arm failed to Free_Goroutine / co_delete, the unfreed
      --  stacks would exhaust vmem and Spawn would raise Storage_Error.
      --
      --  Throttling (PR #22 review): spawning all 100k from the main
      --  task in one tight loop lets the run queue back up to ~100k
      --  in-flight before the workers drain it — ~25 GB of mapped VA and
      --  far past Linux's default vm.max_map_count (65_530), which would
      --  crash the test on a stock CI runner before it could prove
      --  anything. We instead spawn in batches of Batch_Size with a full
      --  Shutdown between them, capping peak in-flight at Batch_Size.
      --  Total spawned + completed is still N_Batches * Batch_Size =
      --  100_000, and draining to baseline N_Batches times is a *stronger*
      --  leak gate than a single drain. The Run_Counter accumulates
      --  across batches; matching the exact tally is the leak proof.
      Batch_Size : constant := 5_000;
      N_Batches  : constant := 20;
      N_Goroutines : constant := Batch_Size * N_Batches;  --  100_000

      --  A deliberately smaller second cycle. Its only job is to prove
      --  the runtime returned to a usable baseline after the big run —
      --  a pool left half-torn-down (workers not joined, Init's
      --  not-initialised precondition tripped) would raise or hang here,
      --  and a record bleeding across the first Shutdown would skew this
      --  second exact count.
      N_Second_Cycle : constant := 1_000;
   begin
      --  Defensive: a prior test that raised before its own Shutdown
      --  could leave the scheduler initialised. Shutdown-when-not-init
      --  is a documented no-op, so this is always safe.
      Shutdown;

      --  ## Cycle 1 — the 100k burst at default (multi-worker) width,
      --  in bounded batches so peak in-flight stays <= Batch_Size.
      Run_Counter.Reset;
      for Batch in 1 .. N_Batches loop
         Init;  --  Workers => 0 => Number_Of_CPUs: real concurrency.
         for Iteration in 1 .. Batch_Size loop
            Unused_G := Spawn (Tally_And_Return'Access);
         end loop;
         Shutdown;  --  drains this batch fully → baseline before the next.
      end loop;

      Assert
        (Run_Counter.Value = N_Goroutines,
         "Expected" & N_Goroutines'Image
         & " goroutine bodies to run exactly once, got"
         & Run_Counter.Value'Image
         & " — a shortfall means dropped/stuck goroutines, an excess "
         & "means a reaped record was reused while still live");

      --  ## Cycle 2 — clean baseline re-check.
      --
      --  Init must succeed (the first Shutdown returned the scheduler
      --  to the not-initialised state). Re-running a smaller burst to
      --  an exact tally proves the pool rebuilt from a clean slate and
      --  the prior cycle left no live goroutines behind.
      Run_Counter.Reset;
      Init;
      for Iteration in 1 .. N_Second_Cycle loop
         Unused_G := Spawn (Tally_And_Return'Access);
      end loop;
      Shutdown;

      Assert
        (Run_Counter.Value = N_Second_Cycle,
         "Second Init/Spawn/Shutdown cycle expected"
         & N_Second_Cycle'Image & " bodies, got"
         & Run_Counter.Value'Image
         & " — the 100k run did not return the runtime to baseline "
         & "(leaked records or workers bled into the next cycle)");
   end Test_100k_Spawn_Complete_Returns_To_Baseline;

end Stress_Goroutines_Suite;
