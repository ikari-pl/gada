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
   Once_Raised    : Boolean := False;
   Cond_Flag      : Boolean := False;
   Cond_Flags     : array (1 .. 2) of Boolean := (others => False);
   Cond_Obj       : Cond_Access;

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
      Register_Routine (T, Test_Cond_Signal'Access, "Cond Signal wakes one");
      Register_Routine
        (T, Test_Cond_Broadcast'Access, "Cond Broadcast wakes all");
   end Register_Tests;

   --  Goroutine body: bump Shared_Counter under the mutex, spinning
   --  on Try_Lock (non-blocking) so a single worker cannot deadlock.
   procedure Bump_Body is
      Ok : Boolean;
   begin
      loop
         Try_Lock (Shared_Mutex, Ok);
         exit when Ok;
         Scheduler.Yield;
      end loop;
      Shared_Counter := Shared_Counter + 1;
      Unlock (Shared_Mutex);
      Done (Shared_WG);
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
      Do (Once_Inc'Access);
   end Once_Body;

   procedure Waiter_Body is
   begin
      Lock (Cond_Obj.L.all);
      Wait (Cond_Obj.all);
      --  Wait reacquired the lock on return.
      Cond_Flag := True;
      Unlock (Cond_Obj.L.all);
      Done (Shared_WG);
   end Waiter_Body;

   procedure Waiter_Body_1 is
   begin
      Lock (Cond_Obj.L.all);
      Wait (Cond_Obj.all);
      Cond_Flags (1) := True;
      Unlock (Cond_Obj.L.all);
      Done (Shared_WG);
   end Waiter_Body_1;

   procedure Waiter_Body_2 is
   begin
      Lock (Cond_Obj.L.all);
      Wait (Cond_Obj.all);
      Cond_Flags (2) := True;
      Unlock (Cond_Obj.L.all);
      Done (Shared_WG);
   end Waiter_Body_2;

   procedure Test_Mutex_Basic (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      M  : aliased Mutex;
      Ok : Boolean;
   begin
      Assert (not Is_Locked (M), "fresh mutex is unlocked");
      Try_Lock (M, Ok);
      Assert (Ok and Is_Locked (M), "TryLock on free mutex succeeds");
      Try_Lock (M, Ok);
      Assert (not Ok, "TryLock on held mutex fails");
      Unlock (M);
      Assert (not Is_Locked (M), "Unlock releases");
      Lock (M);
      Assert (Is_Locked (M), "entry Lock acquires");
      Unlock (M);
      --  Go panics on unlock of an unlocked mutex; we raise.
      begin
         Unlock (M);
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
      Add (Shared_WG, 4);
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      for I in 1 .. 4 loop
         Unused_G := Scheduler.Spawn (Bump_Body'Access);
      end loop;
      Wait (Shared_WG);
      Scheduler.Shutdown;
      Assert (Shared_Counter = 4, "4 goroutines each bumped once, got"
              & Integer'Image (Shared_Counter));
   end Test_Mutex_Mutual_Exclusion;

   procedure Test_RWMutex (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Rw : aliased RW_Mutex;
      Ok : Boolean;
   begin
      Lock (Rw);  --  write lock
      Try_R_Lock (Rw, Ok);
      Assert (not Ok, "no read lock while writer holds it");
      Try_Lock (Rw, Ok);
      Assert (not Ok, "no second write lock");
      Unlock (Rw);
      Try_R_Lock (Rw, Ok);
      Assert (Ok, "read lock after write unlock");
      Try_R_Lock (Rw, Ok);
      Assert (Ok, "second reader ok");
      Try_Lock (Rw, Ok);
      Assert (not Ok, "writer blocked by readers");
      R_Unlock (Rw);
      R_Unlock (Rw);
      Try_Lock (Rw, Ok);
      Assert (Ok, "writer ok after all readers released");
      Unlock (Rw);
      --  Go panics on Unlock with no write lock / RUnlock with none.
      begin
         Unlock (Rw);
         Assert (False, "Unlock without write lock must raise");
      exception
         when Constraint_Error =>
            null;
      end;
      begin
         R_Unlock (Rw);
         Assert (False, "RUnlock without read lock must raise");
      exception
         when Constraint_Error =>
            null;
      end;
   end Test_RWMutex;

   procedure Test_WaitGroup (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Add (Shared_WG, 2);
      Assert (Value (Shared_WG) = 2, "counter is 2");
      Done (Shared_WG);
      Done (Shared_WG);
      Assert (Value (Shared_WG) = 0, "counter is 0");
      Wait (Shared_WG);  --  returns immediately at zero
      --  Go panics on counter underflow.
      begin
         Done (Shared_WG);
         Assert (False, "Done at zero must raise");
      exception
         when Constraint_Error =>
            null;
      end;
      begin
         Add (Shared_WG, -1);
         Assert (False, "Add(-1) at zero must raise");
      exception
         when Constraint_Error =>
            null;
      end;
      Add (Shared_WG, 5);
      Add (Shared_WG, -3);
      Assert (Value (Shared_WG) = 2, "Add(-3) down to 2 ok");
      Add (Shared_WG, -2);
      Wait (Shared_WG);
   end Test_WaitGroup;

   procedure Test_Once (T : in out AUnit.Test_Cases.Test_Case'Class) is
      O        : aliased Once;
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Once_Counter := 0;
      Do (O, Once_Inc'Access);
      Do (O, Once_Inc'Access);
      Assert (Once_Counter = 1, "Do runs f once, got"
              & Integer'Image (Once_Counter));
      --  From a goroutine too: still exactly once overall.
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Once_Body'Access);
      Scheduler.Shutdown;
      Do (O, Once_Inc'Access);
      Assert (Once_Counter = 2, "once per Once object, got"
              & Integer'Image (Once_Counter));
      --  Go marks done even when f panics.
      declare
         O2 : aliased Once;
      begin
         Once_Raised := False;
         begin
            Do (O2, Once_Raise'Access);
            Assert (False, "raising f must propagate");
         exception
            when Constraint_Error =>
               null;
         end;
         Assert (Once_Raised, "f ran before raising");
         Once_Counter := 0;
         Do (O2, Once_Inc'Access);
         Assert (Once_Counter = 0, "done stays set after panic");
      end;
   end Test_Once;

   procedure Test_Cond_Signal (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      M        : aliased Mutex;
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Cond_Flag := False;
      Cond_Obj := New_Cond (M'Access);
      Add (Shared_WG, 1);
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Waiter_Body'Access);
      --  Wait until the waiter is parked, then wake it.
      while Value (Cond_Obj.Waiters) = 0 loop
         Scheduler.Yield;
      end loop;
      Signal (Cond_Obj.all);
      Wait (Shared_WG);
      Scheduler.Shutdown;
      Assert (Cond_Flag, "Signal woke the waiter");
   end Test_Cond_Signal;

   procedure Test_Cond_Broadcast (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      M        : aliased Mutex;
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Cond_Flags := (others => False);
      Cond_Obj := New_Cond (M'Access);
      Add (Shared_WG, 2);
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Waiter_Body_1'Access);
      Unused_G := Scheduler.Spawn (Waiter_Body_2'Access);
      while Value (Cond_Obj.Waiters) < 2 loop
         Scheduler.Yield;
      end loop;
      Broadcast (Cond_Obj.all);
      Wait (Shared_WG);
      Scheduler.Shutdown;
      Assert (Cond_Flags (1) and Cond_Flags (2),
              "Broadcast woke both waiters");
   end Test_Cond_Broadcast;

end Sync_Suite;
