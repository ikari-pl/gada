--  AUnit suite for the scheduler under sustained spawn-and-reap load.
--
--  Phase 3 item 3f exit-criterion #7: "goroutine that returns
--  naturally is reaped without leaking its libco stack" gated as a
--  1000-cycle stress assertion. The realised shape is a 1000-spawn
--  burst of bodies that return immediately; if Spawn's `Make ->
--  co_create` ever raised Storage_Error from stack-mapping
--  exhaustion (Linux's typical ~65 530 vmem-region cap, or macOS's
--  per-task vmem ceiling), 1000 unfreed 256 KB stacks would have
--  consumed ~256 MB of vmem and the run would surface the failure.
--  Conversely, if every cothread is freed in the worker's DONE
--  reap arm, the test runs cleanly.
--
--  Opt-in by design (same shape as Stress_Gc_Suite): the test_runner
--  only registers this suite when `make -C runtime test PKG=stress.
--  scheduler` selects it. The default `make test` (and `make ci`)
--  does not run it — see `runtime/tests/test_runner.adb` for the
--  registration filter.

with AUnit;
with AUnit.Test_Cases;

package Stress_Scheduler_Suite is

   type Stress_Scheduler_Test is
     new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Stress_Scheduler_Test);
   overriding function  Name
     (T : Stress_Scheduler_Test) return AUnit.Message_String;

   procedure Test_1000_Cycles_Spawn_Return_Reap_Leaks_None
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Stress_Scheduler_Suite;
