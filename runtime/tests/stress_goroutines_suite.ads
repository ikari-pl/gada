--  AUnit suite for the scheduler under a 100k spawn-and-complete burst.
--
--  Phase 3 item "Goroutine leak test" (roadmap/03-concurrency.md): a
--  goroutine that is spawned and runs to natural completion must leave
--  no residue — its Goroutine_Record is Free'd on the worker's DONE
--  reap arm, its libco cothread is co_delete'd, and the worker pool is
--  fully torn down by Shutdown (The_Workers := null). After 100_000
--  such goroutines the runtime must be back at baseline: no leaked
--  records, no leaked Ada tasks, no growth that bleeds into the next
--  Init/Spawn/Shutdown cycle.
--
--  The test cannot read the scheduler's private state (Run_Queue,
--  The_Workers, the Goroutine_Record free-list) directly, so it asserts
--  on observable proxies that a leak would perturb:
--
--    (1) Exactness — a protected counter incremented by each of the
--        100_000 goroutine bodies equals *exactly* 100_000 after
--        Shutdown. A dropped goroutine (worker died, queue lost it)
--        undershoots; a double-run (record reused while still live)
--        overshoots. Either way the leak is loud.
--
--    (2) Clean second cycle — a second, smaller Init/Spawn/Shutdown
--        burst after the big run produces its own exact count. A pool
--        that did not return to baseline (workers not joined, records
--        bleeding across the Shutdown barrier) would corrupt the second
--        cycle's count or hang its Shutdown. Running a full second
--        cycle to an exact tally proves teardown returned the runtime
--        to the same baseline Init found the first time.
--
--    (3) Live-task baseline — Ada.Task_Identification cannot enumerate
--        tasks portably, but the worker pool is the only task source
--        the scheduler creates, and (2) already proves it is rebuildable
--        from a clean slate. The exactness + clean-second-cycle proxies
--        together are the contract; a direct OS task-count probe is not
--        deterministic on macOS (the AdaCore FSF runtime spins helper
--        tasks lazily) so it is intentionally not asserted on.
--
--  Opt-in by design (same shape as Stress_Gc_Suite / Stress_Scheduler_
--  Suite): the test_runner only registers this suite under the explicit
--  `make -C runtime test PKG=stress.goroutines` invocation. The default
--  `make test` (and therefore `make ci`) does *not* run it — see
--  `runtime/tests/test_runner.adb` for the registration filter.

with AUnit;
with AUnit.Test_Cases;

package Stress_Goroutines_Suite is

   type Stress_Goroutines_Test is
     new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests
     (T : in out Stress_Goroutines_Test);
   overriding function  Name
     (T : Stress_Goroutines_Test) return AUnit.Message_String;

   procedure Test_100k_Spawn_Complete_Returns_To_Baseline
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Stress_Goroutines_Suite;
