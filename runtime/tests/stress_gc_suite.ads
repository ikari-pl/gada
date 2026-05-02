--  AUnit suite for the runtime's GC under sustained load.
--
--  Phase 2 item 10's contract is "10 s of allocation-heavy load
--  completes with RSS < 200 MB". The realised shape is a fixed
--  five-million atomic allocations of 64 bytes each (= 320 MB of
--  raw nominal allocation pressure) with periodic Collect calls;
--  the runtime under test is free to reuse heap pages so the
--  observed Heap_Size after the run must stay under 200 MB even
--  though the cumulative allocation pressure is well above that.
--  The five-million count finishes well under 10 s on the dev
--  host and inside the CI runner's time budget; bumping the
--  count to a wall-time-bounded loop would add CI flakiness on
--  variable-speed runners for no extra signal.
--
--  Opt-in by design: the test_runner only registers this suite
--  when the explicit `make -C runtime test PKG=stress.gc` invocation
--  selects it. The default `make test` (and therefore `make ci`)
--  *does not* run it — see `runtime/tests/test_runner.adb` for the
--  registration filter.

with AUnit;
with AUnit.Test_Cases;

package Stress_Gc_Suite is

   type Stress_Gc_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Stress_Gc_Test);
   overriding function  Name (T : Stress_Gc_Test) return AUnit.Message_String;

   procedure Test_Five_Million_Atomic_Allocs_Bounded_Heap
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Stress_Gc_Suite;
