--  AUnit suite for `Gada.Std.Runtime` (Go `runtime` port, Phase 6
--  wave 2).
--
--  Covers Num_Goroutine (baseline, +2 while two blockers are parked,
--  back to baseline after drain), Go_Max_Procs (query, resize from
--  the main task), Go_Sched (no-op outside a goroutine, must not
--  crash), and GC (forces a collection, must not crash).

with AUnit;
with AUnit.Test_Cases;

package Runtime_Suite is

   type Runtime_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Runtime_Test);
   overriding function  Name (T : Runtime_Test) return AUnit.Message_String;

   procedure Test_Num_Goroutine (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Go_Max_Procs (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Go_Sched_And_GC (T : in out
      AUnit.Test_Cases.Test_Case'Class);

end Runtime_Suite;
