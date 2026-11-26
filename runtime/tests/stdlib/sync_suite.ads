--  AUnit suite for `Gada.Std.Sync` (Go `sync` port, Phase 6).
--
--  Covers the Go semantics contract: Mutex Lock/Unlock/TryLock
--  (incl. unlock-of-unlocked panic), RWMutex reader/writer exclusion,
--  WaitGroup Add/Done/Wait (incl. underflow panic), Once exactly-once
--  (incl. the panic path), and Cond Wait/Signal/Broadcast driven by
--  real goroutines through Gada.Async.Scheduler.

with AUnit;
with AUnit.Test_Cases;

package Sync_Suite is

   type Sync_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Sync_Test);
   overriding function  Name (T : Sync_Test) return AUnit.Message_String;

   procedure Test_Mutex_Basic (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Mutex_Mutual_Exclusion (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_RWMutex (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_WaitGroup (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Once (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Cond_Signal (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Cond_Broadcast (T : in out
      AUnit.Test_Cases.Test_Case'Class);

end Sync_Suite;
