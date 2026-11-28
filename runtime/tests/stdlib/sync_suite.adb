--  Body of Sync_Suite — see spec for test rationale.
--
--  Goroutine bodies passed to Spawn are parameterless access
--  procedures, so per-test state lives in file-scope globals, reset
--  at the start of each test (same pattern as Scheduler_Suite).
--  Worker count is 1 everywhere: the blocking paths under test park
--  through the scheduler (Cond's channel), and the mutex exclusion
--  test spins on Try_Lock + Yield, which is cooperative and cannot
--  deadlock a single worker.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Async.Scheduler;
with Gada.Std.Sync; use Gada.Std.Sync;

package body Sync_Suite is

   package Scheduler renames Gada.Async.Scheduler;

   --  Shared state for the goroutine bodies.
   Shared_Mutex   : aliased Mutex;
   Shared_Counter : Natural := 0;
   Shared_WG      : Wait_Group;
   Once_Counter   : Natural := 0;
   pragma Volatile (Once_Counter);
   Once_Obj       : aliased Once;
   --  Separate object for the race test: Test_Once's spawned body
   --  already marks Once_Obj done, and Once is exactly-once per object.
   Race_Once      : aliased Once;
   Once_Raised    : Boolean := False;
   Cond_Flag      : Boolean := False;
   Cond_Flags     : array (1 .. 2) of Boolean := (others => False);
   Cond_Obj       : Cond_Access;
   Cond_Mutex     : aliased Mutex;

   overriding function Name
     (T : Sync_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Sync suite"));

   overriding procedure Register_Tests (T : in out Sync_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Mutex_Basic'Access, "Mutex Lock/Unlock/TryLock");
      Register_Routine
        (T, Test_Mutex_Mutual_Exclusion'Access, "Mutex excludes goroutines");
      Register_Routine (T, Test_RWMutex'Access, "RWMutex reader/writer");
      Register_Routine (T, Test_WaitGroup'Access, "WaitGroup Add/Done/Wait");
      Register_Routine (T, Test_Once'Access, "Once runs exactly once");
      Register_Routine (T, Test_Once_Concurrent'Access,
                        "Once exactly once under 4 racing goroutines");
      Register_Routine (T, Test_Cond_Signal'Access, "Cond Signal wakes one");
      Register_Routine
        (T, Test_Cond_Broadcast'Access, "Cond Broadcast wakes all");
      Register_Routine (T, Test_Mutex_Parks'Access,
                        "Mutex contender parks while holder parks (1 worker)");
      Register_Routine (T, Test_RWMutex_Parks'Access,
                        "RWMutex readers/writers park (1 worker)");
      Register_Routine (T, Test_WaitGroup_Parks'Access,
                        "WaitGroup.Wait parks: closer idiom (1 worker)");
      Register_Routine (T, Test_Once_Waits_For_F'Access,
                        "Once: f parks, concurrent Do waits (1 worker)");
      Register_Routine (T, Test_Main_Task_Waits'Access,
                        "main-task Lock/Do block on entries");
   end Register_Tests;

   --  Goroutine body: bump Shared_Counter under the mutex, spinning
   --  on Try_Lock (non-blocking) so a single worker cannot deadlock.
   procedure Bump_Body is
   begin
      loop
         exit when Shared_Mutex.Try_Lock;
         Scheduler.Yield;
      end loop;
      Shared_Counter := Shared_Counter + 1;
      Shared_Mutex.Unlock;
      Shared_WG.Done;
   end Bump_Body;

   procedure Once_Inc is
   begin
      Once_Counter := Once_Counter + 1;
   end Once_Inc;

   procedure Once_Raise is
   begin
      Once_Raised := True;
      raise Constraint_Error with "boom";
   end Once_Raise;

   procedure Once_Body is
   begin
      Once_Obj.Do_K (Once_Inc'Access);
   end Once_Body;

   --  Racing Do_K body: also signals the WaitGroup.
   procedure Once_Race_Body is
   begin
      Race_Once.Do_K (Once_Inc'Access);
      Shared_WG.Done;
   end Once_Race_Body;

   procedure Waiter_Body is
   begin
      Cond_Obj.L.all.Lock;
      Wait (Cond_Obj.all);
      --  Wait reacquired the lock on return.
      Cond_Flag := True;
      Cond_Obj.L.all.Unlock;
      Shared_WG.Done;
   end Waiter_Body;

   procedure Waiter_Body_1 is
   begin
      Cond_Obj.L.all.Lock;
      Wait (Cond_Obj.all);
      Cond_Flags (1) := True;
      Cond_Obj.L.all.Unlock;
      Shared_WG.Done;
   end Waiter_Body_1;

   procedure Waiter_Body_2 is
   begin
      Cond_Obj.L.all.Lock;
      Wait (Cond_Obj.all);
      Cond_Flags (2) := True;
      Cond_Obj.L.all.Unlock;
      Shared_WG.Done;
   end Waiter_Body_2;

   procedure Test_Mutex_Basic (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      M  : aliased Mutex;
   begin
      Assert (not M.Is_Locked, "fresh mutex is unlocked");
      Assert (M.Try_Lock and M.Is_Locked, "TryLock on free mutex succeeds");
      Assert (not M.Try_Lock, "TryLock on held mutex fails");
      M.Unlock;
      Assert (not M.Is_Locked, "Unlock releases");
      M.Lock;
      Assert (M.Is_Locked, "entry Lock acquires");
      M.Unlock;
      --  Go panics on unlock of an unlocked mutex; we raise.
      begin
         M.Unlock;
         Assert (False, "double Unlock must raise");
      exception
         when Constraint_Error =>
            null;  --  expected
      end;
   end Test_Mutex_Basic;

   procedure Test_Mutex_Mutual_Exclusion (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Shared_Counter := 0;
      Shared_WG.Add (4);
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 2);
      for I in 1 .. 4 loop
         Unused_G := Scheduler.Spawn (Bump_Body'Access);
      end loop;
      Shared_WG.Wait;
      Scheduler.Shutdown;
      Assert (Shared_Counter = 4, "4 goroutines each bumped once, got"
              & Integer'Image (Shared_Counter));
   end Test_Mutex_Mutual_Exclusion;

   procedure Test_RWMutex (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Rw : aliased RW_Mutex;
   begin
      Rw.Lock;  --  write lock
      Assert (not Rw.Try_R_Lock, "no read lock while writer holds it");
      Assert (not Rw.Try_Lock, "no second write lock");
      Rw.Unlock;
      Assert (Rw.Try_R_Lock, "read lock after write unlock");
      Rw.R_Lock;  --  main-task blocking read path, uncontended
      Assert (not Rw.Try_Lock, "writer blocked by readers");
      Rw.R_Unlock;
      Rw.R_Unlock;
      Assert (Rw.Try_Lock, "writer ok after all readers released");
      Rw.Unlock;
      --  Go panics on Unlock with no write lock / RUnlock with none.
      begin
         Rw.Unlock;
         Assert (False, "Unlock without write lock must raise");
      exception
         when Constraint_Error =>
            null;
      end;
      begin
         Rw.R_Unlock;
         Assert (False, "RUnlock without read lock must raise");
      exception
         when Constraint_Error =>
            null;
      end;
   end Test_RWMutex;

   procedure Test_WaitGroup (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Shared_WG.Add (2);
      Assert (Shared_WG.Value = 2, "counter is 2");
      Shared_WG.Done;
      Shared_WG.Done;
      Assert (Shared_WG.Value = 0, "counter is 0");
      Shared_WG.Wait;  --  returns immediately at zero
      --  Go panics on counter underflow.
      begin
         Shared_WG.Done;
         Assert (False, "Done at zero must raise");
      exception
         when Constraint_Error =>
            null;
      end;
      begin
         Shared_WG.Add (-1);
         Assert (False, "Add(-1) at zero must raise");
      exception
         when Constraint_Error =>
            null;
      end;
      Shared_WG.Add (5);
      Shared_WG.Add (-3);
      Assert (Shared_WG.Value = 2, "Add(-3) down to 2 ok");
      Shared_WG.Add (-2);
      Shared_WG.Wait;
   end Test_WaitGroup;

   procedure Test_Once (T : in out AUnit.Test_Cases.Test_Case'Class) is
      O        : aliased Once;
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Once_Counter := 0;
      O.Do_K (Once_Inc'Access);
      O.Do_K (Once_Inc'Access);
      Assert (Once_Counter = 1, "Do runs f once, got"
              & Integer'Image (Once_Counter));
      --  From a goroutine too: still exactly once overall.
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Once_Body'Access);
      Scheduler.Shutdown;
      O.Do_K (Once_Inc'Access);
      Assert (Once_Counter = 2, "once per Once object, got"
              & Integer'Image (Once_Counter));
      --  Go marks done even when f panics.
      declare
         O2 : aliased Once;
      begin
         Once_Raised := False;
         begin
            O2.Do_K (Once_Raise'Access);
            Assert (False, "raising f must propagate");
         exception
            when Constraint_Error =>
               null;
         end;
         Assert (Once_Raised, "f ran before raising");
         Once_Counter := 0;
         O2.Do_K (Once_Inc'Access);
         Assert (Once_Counter = 0, "done stays set after panic");
      end;
   end Test_Once;

   procedure Test_Cond_Signal (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Cond_Flag := False;
      Cond_Obj := New_Cond (Cond_Mutex'Access);
      Shared_WG.Add (1);
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Waiter_Body'Access);
      --  Wait until the waiter is parked, then wake it.
      --  Bounded poll with a real delay (Yield is a no-op in the
      --  main task); 5s cap matches the suite's watchdog style.
      for I in 1 .. 5_000 loop
         exit when Cond_Obj.Waiters.Value >= 1;
         delay 0.001;
      end loop;
      Assert (Cond_Obj.Waiters.Value = 1, "waiter parked, got"
              & Natural'Image (Cond_Obj.Waiters.Value));
      Signal (Cond_Obj.all);
      Shared_WG.Wait;
      Scheduler.Shutdown;
      Assert (Cond_Flag, "Signal woke the waiter");
   end Test_Cond_Signal;

   procedure Test_Cond_Broadcast (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Cond_Flags := (others => False);
      Cond_Obj := New_Cond (Cond_Mutex'Access);
      Shared_WG.Add (2);
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Waiter_Body_1'Access);
      Unused_G := Scheduler.Spawn (Waiter_Body_2'Access);
      for I in 1 .. 5_000 loop
         exit when Cond_Obj.Waiters.Value >= 2;
         delay 0.001;
      end loop;
      Assert (Cond_Obj.Waiters.Value >= 2, "both waiters parked");
      Broadcast (Cond_Obj.all);
      Shared_WG.Wait;
      Scheduler.Shutdown;
      Assert (Cond_Flags (1) and Cond_Flags (2),
              "Broadcast woke both waiters");
   end Test_Cond_Broadcast;

   procedure Test_Once_Concurrent (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Once_Counter := 0;
      Shared_WG.Add (4);
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 2);
      for I in 1 .. 4 loop
         Unused_G := Scheduler.Spawn (Once_Race_Body'Access);
      end loop;
      Shared_WG.Wait;
      Scheduler.Shutdown;
      Assert (Once_Counter = 1, "4 racing Do_K ran f exactly once, got"
              & Integer'Image (Once_Counter));
   end Test_Once_Concurrent;

   ---------------------------------------------------------------
   --  Goroutine-aware blocking (regression #3, #7). Workers => 1
   --  everywhere below: a sync wait that blocked the worker's OS
   --  thread instead of parking the goroutine deadlocks here, because
   --  the goroutine that would release it is pinned to that worker.
   ---------------------------------------------------------------

   Gate       : Unit_Channels.Channel;
   Step       : Natural := 0;
   pragma Volatile (Step);
   Seen_At    : Natural := 0;
   pragma Volatile (Seen_At);
   Park_Mutex : aliased Mutex;
   Park_RW    : aliased RW_Mutex;
   Park_WG    : Wait_Group;
   Park_Once  : aliased Once;
   Main_Once  : aliased Once;

   procedure Recv_Gate is
      V, OK : Boolean;
      pragma Unreferenced (V, OK);
   begin
      Unit_Channels.Receive (Gate, V, OK);
   end Recv_Gate;

   --  Wait (bounded) for Step >= N; True if reached.
   function Reached (N : Natural) return Boolean is
   begin
      for I in 1 .. 5_000 loop
         if Step >= N then
            return True;
         end if;
         delay 0.001;
      end loop;
      return Step >= N;
   end Reached;

   --  Holder: takes the lock, then parks on Gate while holding it.
   procedure Mutex_Holder is
   begin
      Park_Mutex.Lock;
      Step := 1;
      Recv_Gate;
      Park_Mutex.Unlock;
   end Mutex_Holder;

   procedure Mutex_Contender is
   begin
      Step := 2;
      Park_Mutex.Lock;   --  must park, freeing the single worker
      Seen_At := Step;
      Step := 4;
      Park_Mutex.Unlock;
   end Mutex_Contender;

   procedure Test_Mutex_Parks (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Step := 0;
      Gate := Unit_Channels.Make;
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Mutex_Holder'Access);
      Assert (Reached (1), "holder took the lock");
      Unused_G := Scheduler.Spawn (Mutex_Contender'Access);
      Assert (Reached (2), "contender started");
      delay 0.02;   --  let the contender reach Lock and park
      Step := 3;
      Unit_Channels.Send (Gate, True);   --  holder resumes, unlocks
      Assert (Reached (4), "contender got the lock after the holder");
      Scheduler.Shutdown;
      Assert (Seen_At = 3, "contender ran only after the release");
      Assert (not Park_Mutex.Is_Locked, "lock released");
   end Test_Mutex_Parks;

   procedure RW_Writer is
   begin
      Park_RW.Lock;
      Step := 1;
      Recv_Gate;           --  park holding the write lock
      Park_RW.Unlock;      --  wakes the parked reader
   end RW_Writer;

   procedure RW_Reader is
   begin
      Step := 2;
      Park_RW.R_Lock;      --  parks: writer holds the lock
      Step := 4;
      Recv_Gate;           --  park holding a read lock
      Park_RW.R_Unlock;    --  readers -> 0: wakes the parked writer
   end RW_Reader;

   procedure RW_Writer_2 is
   begin
      Step := 5;
      Park_RW.Lock;        --  parks: a reader holds the lock
      Step := 6;
      Park_RW.Unlock;
   end RW_Writer_2;

   procedure Test_RWMutex_Parks (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Step := 0;
      Gate := Unit_Channels.Make;
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (RW_Writer'Access);
      Assert (Reached (1), "writer holds the lock");
      Unused_G := Scheduler.Spawn (RW_Reader'Access);
      Assert (Reached (2), "reader started");
      delay 0.02;
      Unit_Channels.Send (Gate, True);   --  writer unlocks
      Assert (Reached (4), "reader got the read lock after the writer");
      Unused_G := Scheduler.Spawn (RW_Writer_2'Access);
      Assert (Reached (5), "second writer started");
      delay 0.02;
      Assert (Step = 5, "second writer parked behind the reader");
      Unit_Channels.Send (Gate, True);   --  reader releases
      Assert (Reached (6), "second writer got the lock");
      Scheduler.Shutdown;
   end Test_RWMutex_Parks;

   --  The `go func(){ wg.Wait(); close(results) }()` closer idiom.
   procedure WG_Closer is
   begin
      Park_WG.Wait;        --  must park, not block the worker
      Step := 10;
   end WG_Closer;

   procedure WG_Worker is
   begin
      Recv_Gate;
      Step := Step + 1;
      Park_WG.Done;
   end WG_Worker;

   procedure Test_WaitGroup_Parks (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Step := 0;
      Gate := Unit_Channels.Make;
      Park_WG.Add (2);
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (WG_Closer'Access);
      Unused_G := Scheduler.Spawn (WG_Worker'Access);
      Unused_G := Scheduler.Spawn (WG_Worker'Access);
      delay 0.02;
      Assert (Step = 0, "closer waits for the workers");
      Unit_Channels.Send (Gate, True);
      Unit_Channels.Send (Gate, True);
      Assert (Reached (10), "closer released when the counter hit 0");
      Scheduler.Shutdown;
      Assert (Park_WG.Value = 0, "counter back to 0");
   end Test_WaitGroup_Parks;

   --  f parks inside Once.Do (a channel receive): it must not run
   --  inside a protected action, and a concurrent Do must wait for it.
   procedure Once_Parking_F is
   begin
      Step := 1;
      Recv_Gate;
      Once_Counter := Once_Counter + 1;
   end Once_Parking_F;

   procedure Once_First is
   begin
      Park_Once.Do_K (Once_Parking_F'Access);
   end Once_First;

   procedure Once_Second is
   begin
      Step := 2;
      Park_Once.Do_K (Once_Inc'Access);   --  parks until f returns
      Seen_At := Once_Counter;
      Step := 3;
   end Once_Second;

   procedure Test_Once_Waits_For_F (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Step := 0;
      Once_Counter := 0;
      Seen_At := 99;
      Gate := Unit_Channels.Make;
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Once_First'Access);
      Assert (Reached (1), "f is running (parked)");
      Unused_G := Scheduler.Spawn (Once_Second'Access);
      Assert (Reached (2), "second Do called");
      delay 0.02;
      Assert (Step = 2, "second Do waits while f runs");
      Unit_Channels.Send (Gate, True);
      Assert (Reached (3), "second Do returned after f");
      Scheduler.Shutdown;
      Assert (Once_Counter = 1 and then Seen_At = 1,
              "f ran once and had completed when the second Do returned");
   end Test_Once_Waits_For_F;

   --  Main-task (non-goroutine) waiters block on the protected entries.
   procedure Slow_Holder is
   begin
      Park_Mutex.Lock;
      Step := 1;
      delay 0.03;          --  blocks the worker; main is its own task
      Step := 2;
      Park_Mutex.Unlock;
   end Slow_Holder;

   procedure Slow_F is
   begin
      Step := 5;
      delay 0.03;
      Once_Counter := Once_Counter + 1;
   end Slow_F;

   procedure Slow_Once is
   begin
      Main_Once.Do_K (Slow_F'Access);
   end Slow_Once;

   procedure Test_Main_Task_Waits (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Step := 0;
      Once_Counter := 0;
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Slow_Holder'Access);
      Assert (Reached (1), "goroutine holds the mutex");
      Park_Mutex.Lock;     --  main blocks on the entry until released
      Assert (Step = 2, "main got the mutex after the goroutine");
      Park_Mutex.Unlock;
      Unused_G := Scheduler.Spawn (Slow_Once'Access);
      Assert (Reached (5), "goroutine is inside f");
      Main_Once.Do_K (Once_Inc'Access);   --  main awaits f
      Assert (Once_Counter = 1, "main's Do waited for the running f");
      Scheduler.Shutdown;
   end Test_Main_Task_Waits;

end Sync_Suite;
