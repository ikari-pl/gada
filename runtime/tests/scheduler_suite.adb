--  Body of Scheduler_Suite — see spec for property list.
--
--  Globals (Counter, Done_Yields) are package-level rather than
--  test-procedure locals because the goroutine bodies passed to Spawn
--  are parameterless `access procedure` values: there is no closure
--  mechanism to thread per-test state through, so the bodies must
--  reach through file-scope state. Each test resets the globals it
--  reads before driving Spawn — order-of-registration is not
--  contractual under AUnit, defensive resets keep failures localised.
--
--  Worker count: every test except Test_Pool_Distributes_Across_Workers
--  passes Init (Workers => 1) explicitly. The shared Counter / Yields_Run
--  globals would otherwise race under the multi-worker default
--  (Number_Of_CPUs ≥ 2 on every CI runner), and the existing tests are
--  about scheduler-control properties (yields re-schedule, body runs
--  exactly once, etc.), not about multi-worker distribution.
--  Test_Pool_Distributes_Across_Workers drives Workers => 2 explicitly
--  and observes the distribution through a protected `Worker_Recorder`
--  rather than racy shared counters.
pragma Warnings (Off, "use of an anonymous access type allocator");

with Ada.Task_Identification;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;

with Gada.Async.Scheduler; use Gada.Async.Scheduler;
with Gada.Core.Panic;
with System; use type System.Address;

package body Scheduler_Suite is

   Counter        : Natural := 0;
   Yield_Iterations : constant := 100;
   Yields_Run     : Natural := 0;
   Yield_Done     : Boolean := False;

   procedure Increment_Once;
   procedure Yield_Then_Mark;
   procedure Record_Current_Worker;
   procedure Park_Body;
   procedure Self_Test_Unpark_Of_Never_Run;
   procedure Syscall_Body;
   procedure Body_That_Raises;
   procedure Panic_Isolation_Body;
   procedure Closure_Worker;

   procedure Increment_Once is
   begin
      Counter := @ + 1;
   end Increment_Once;

   procedure Yield_Then_Mark is
   begin
      for Iteration in 1 .. Yield_Iterations loop
         Yields_Run := @ + 1;
         Gada.Async.Scheduler.Yield;
      end loop;
      Yield_Done := True;
   end Yield_Then_Mark;

   --  ## Multi-worker observation surface
   --
   --  Worker_Recorder is a protected object the multi-worker test uses
   --  to observe which worker tasks actually ran goroutines. Each
   --  goroutine body calls Note (Current_Task) — Ada's Current_Task
   --  lookup goes through the OS thread, which under our goroutine-
   --  pinning rule is the same as the worker that picked up the
   --  goroutine. Distinct_Count then deduplicates the recorded
   --  Task_Ids; the test asserts >= 2.
   --
   --  Protected for thread-safety because N goroutines on N workers
   --  call Note concurrently. Distinct_Count is a function (read-
   --  only) but goes through the same lock for memory ordering.
   --  ("Note" rather than "Record" because the latter is an Ada
   --  reserved word.)
   Max_Recorded : constant := 256;
   type Tid_Slots is
     array (1 .. Max_Recorded) of Ada.Task_Identification.Task_Id;

   protected Worker_Recorder is
      procedure Note (Tid : Ada.Task_Identification.Task_Id);
      function  Distinct_Count return Natural;
      procedure Reset;
   private
      Tids : Tid_Slots := [others => Ada.Task_Identification.Null_Task_Id];
      Len  : Natural   := 0;
   end Worker_Recorder;

   protected body Worker_Recorder is

      procedure Note (Tid : Ada.Task_Identification.Task_Id) is
      begin
         if Len < Max_Recorded then
            Len := @ + 1;
            Tids (Len) := Tid;
         end if;
      end Note;

      function Distinct_Count return Natural is
         use type Ada.Task_Identification.Task_Id;
         Count : Natural := 0;
      begin
         for I in 1 .. Len loop
            declare
               Already_Seen : Boolean := False;
            begin
               for J in 1 .. I - 1 loop
                  if Tids (J) = Tids (I) then
                     Already_Seen := True;
                     exit;
                  end if;
               end loop;
               if not Already_Seen then
                  Count := @ + 1;
               end if;
            end;
         end loop;
         return Count;
      end Distinct_Count;

      procedure Reset is
      begin
         Len := 0;
         Tids := [others => Ada.Task_Identification.Null_Task_Id];
      end Reset;

   end Worker_Recorder;

   procedure Record_Current_Worker is
   begin
      Worker_Recorder.Note (Ada.Task_Identification.Current_Task);
   end Record_Current_Worker;

   --  ## Per-goroutine panic-storage observation surface
   --
   --  Int_Panic is the per-program panic instantiation (Integer
   --  payload, Default = 0). Phase 3 promotes Gada.Core.Panic's
   --  pending stack from a process-global to per-goroutine storage
   --  reached through the scheduler's opaque Local_Storage slot;
   --  Panic_Isolation_Body is the test that the promotion actually
   --  isolates concurrent panickers.
   --
   --  Each goroutine: dispense a unique Id, Do_Panic (Id) into its own
   --  state, Yield (so siblings on the same worker push their own Ids
   --  in between), then Recover and assert it got *its own* Id back. A
   --  process-global stack — or a pragma Thread_Local_Storage slot
   --  shared by every goroutine multiplexed onto one worker — would
   --  hand back a sibling's value here; per-goroutine storage cannot.
   --  Bodies are parameterless `access procedure` (no closure), so the
   --  Id is dispensed from the protected Panic_Ledger at body entry.
   Panic_Goroutines : constant := 100;
   type Result_Flags is array (1 .. Panic_Goroutines) of Boolean;

   package Int_Panic is new Gada.Core.Panic
     (Payload_Type => Integer, Default => 0);

   protected Panic_Ledger is
      procedure Reset;
      procedure Next_Id (Id : out Positive);
      procedure Mark (Id : Positive; Isolated : Boolean);
      function  Marked return Natural;
      function  All_Isolated return Boolean;
   private
      Dispensed : Natural := 0;
      Marks     : Natural := 0;
      Results   : Result_Flags := [others => False];
   end Panic_Ledger;

   protected body Panic_Ledger is

      procedure Reset is
      begin
         Dispensed := 0;
         Marks     := 0;
         Results   := [others => False];
      end Reset;

      procedure Next_Id (Id : out Positive) is
      begin
         Dispensed := @ + 1;
         Id        := Dispensed;
      end Next_Id;

      procedure Mark (Id : Positive; Isolated : Boolean) is
      begin
         Results (Id) := Isolated;
         Marks        := @ + 1;
      end Mark;

      function Marked return Natural is (Marks);

      function All_Isolated return Boolean is
        (for all R of Results => R);

   end Panic_Ledger;

   procedure Panic_Isolation_Body is
      My_Id : Positive;
      Got   : Integer;
   begin
      Panic_Ledger.Next_Id (My_Id);
      --  Push My_Id onto this goroutine's own pending-panic state.
      --  Catch Panicking locally so the trampoline sees a normal
      --  return (matches compiler-emit's per-function catch-all).
      begin
         Int_Panic.Do_Panic (My_Id);
      exception
         when Int_Panic.Panicking =>
            null;
      end;
      --  Hand the worker to a sibling, which will push *its* Id.
      Gada.Async.Scheduler.Yield;
      --  Resumed: our state must still hold My_Id, untouched by the
      --  siblings that ran on this worker while we were yielded.
      Got := Int_Panic.Recover;
      Panic_Ledger.Mark (My_Id, Got = My_Id);
   end Panic_Isolation_Body;

   --  ## Spawn-closure round-trip surface
   --
   --  Mirrors, by hand, exactly what the compiler emits for `go
   --  relay(x, y)`: a per-spawn heap record carrying the argument
   --  snapshot, passed through Spawn's opaque Closure parameter and
   --  read back inside the goroutine via Closure (Current). Each of the
   --  100 spawns gets a distinct (A, B) pair with the invariant
   --  B = A * 1000; the worker asserts its own pair still satisfies the
   --  invariant (so closures did not cross-contaminate) and records the
   --  result keyed by A. Bodies are parameterless `access procedure`,
   --  so the per-spawn data travels *only* through the closure pointer —
   --  which is the property under test.
   Closure_Goroutines : constant := 100;
   type Pair_Flags is array (1 .. Closure_Goroutines) of Boolean;

   type Arg_Pair is record
      A : Integer;
      B : Integer;
   end record;
   type Arg_Pair_Access is access Arg_Pair;

   function To_Arg_Pair is
     new Ada.Unchecked_Conversion (System.Address, Arg_Pair_Access);
   function To_Address is
     new Ada.Unchecked_Conversion (Arg_Pair_Access, System.Address);
   procedure Free_Arg_Pair is
     new Ada.Unchecked_Deallocation (Arg_Pair, Arg_Pair_Access);

   protected Closure_Ledger is
      procedure Reset;
      procedure Mark (Id : Positive; Correct : Boolean);
      function  Marked return Natural;
      function  All_Correct return Boolean;
   private
      Marks   : Natural    := 0;
      Results : Pair_Flags := [others => False];
   end Closure_Ledger;

   protected body Closure_Ledger is

      procedure Reset is
      begin
         Marks   := 0;
         Results := [others => False];
      end Reset;

      procedure Mark (Id : Positive; Correct : Boolean) is
      begin
         Results (Id) := Correct;
         Marks        := @ + 1;
      end Mark;

      function Marked return Natural is (Marks);

      function All_Correct return Boolean is (for all R of Results => R);

   end Closure_Ledger;

   procedure Closure_Worker is
      C : Arg_Pair_Access :=
        To_Arg_Pair (Gada.Async.Scheduler.Closure (Current));
      A : constant Integer := C.A;
      B : constant Integer := C.B;
   begin
      --  Record snapshot is copied into A/B above; the heap block is
      --  dead now, so free it (no per-spawn leak — same shape the
      --  generated Go_Worker uses).
      Free_Arg_Pair (C);
      Closure_Ledger.Mark (A, B = A * 1000);
   end Closure_Worker;

   --  ## Park_Tracker — sequence buffer for the Park/Unpark test
   --
   --  Park_Body marks "1" before parking and "2" after Unpark resumes
   --  it. The test asserts the final sequence is "12" — proves both
   --  the Park-suspends-before-mark-2 and the Unpark-resumes paths.
   --  Protected because the goroutine writes from a worker task while
   --  the main test task reads. Buffer is a fixed-size character
   --  array indexed by an internal counter; over-size is harmless.
   protected Park_Tracker is
      procedure Mark (Stage : Character);
      function  Sequence return String;
      procedure Reset;
   private
      Buf  : String (1 .. 16) := [others => ' '];
      Last : Natural          := 0;
   end Park_Tracker;

   protected body Park_Tracker is

      procedure Mark (Stage : Character) is
      begin
         if Last < Buf'Last then
            Last := @ + 1;
            Buf (Last) := Stage;
         end if;
      end Mark;

      function Sequence return String is (Buf (1 .. Last));

      procedure Reset is
      begin
         Last := 0;
         Buf := [others => ' '];
      end Reset;

   end Park_Tracker;

   The_Parked_Goroutine : Goroutine_Id;
   --  Captured at Spawn so the main test task can Unpark it.

   procedure Park_Body is
   begin
      Park_Tracker.Mark ('1');
      Park;
      Park_Tracker.Mark ('2');
   end Park_Body;

   procedure Self_Test_Unpark_Of_Never_Run is
      Other : Goroutine_Id;
   begin
      --  Goroutine body running on the only worker (Workers => 1).
      --  Spawn another goroutine — it goes to the shared Run_Queue
      --  but cannot be popped because the only worker is currently
      --  *us* and we have not yielded. Unpark on it must raise
      --  Program_Error because Bound_Worker is still Unbound.
      --
      --  This test deliberately constructs the precondition violation
      --  inside a goroutine body, where the single-worker invariant
      --  prevents the obvious race ("worker pops Other before main
      --  task can Unpark it").
      Other := Spawn (Increment_Once'Access);
      begin
         Unpark (Other);
         Park_Tracker.Mark ('-');  --  unexpected no-raise
      exception
         when Program_Error =>
            Park_Tracker.Mark ('R');  --  expected raise
      end;
   end Self_Test_Unpark_Of_Never_Run;

   --  ## Body_That_Raises — covers the Goroutine_Trampoline `when others`
   --
   --  A user body that raises is the only way to exercise the
   --  trampoline's exception arm: the trampoline catches and discards,
   --  then sets State => DONE so the worker reaps the cothread cleanly
   --  rather than hitting the unexpected-RUNNING-state Program_Error
   --  arm. Without that catch, a raising goroutine deadlocks Drain.
   --
   --  The arm is silent on purpose — propagating across the libco /
   --  C-convention boundary is undefined; Phase 4's panic-marshalling
   --  layer will surface the failure to the parent. For now, observing
   --  that Shutdown returns and the worker stays alive is the contract.
   procedure Body_That_Raises is
   begin
      raise Constraint_Error
        with "Goroutine body raise — exercises trampoline exception arm";
   end Body_That_Raises;

   --  ## Syscall_Body — sub-item 3e
   --
   --  Mirrors Park_Body's shape but uses Enter_Syscall and a distinct
   --  pair of marker characters ('1', '3' rather than '1', '2') so a
   --  test that runs both Park_Body and Syscall_Body in sequence can
   --  tell their sequences apart in the shared Park_Tracker.
   procedure Syscall_Body is
   begin
      Park_Tracker.Mark ('1');
      Enter_Syscall;
      Park_Tracker.Mark ('3');
   end Syscall_Body;

   overriding function Name
     (T : Scheduler_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Async.Scheduler suite (PKG=async.scheduler)"));

   overriding procedure Register_Tests (T : in out Scheduler_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Init_Shutdown_Empty'Access,
         "Init followed immediately by Shutdown drains a zero-"
         & "goroutine pool without raising");
      Register_Routine
        (T, Test_Shutdown_Without_Init_Is_Noop'Access,
         "Shutdown without a prior Init is the documented "
         & "idempotent no-op (matches Free on Context)");
      Register_Routine
        (T, Test_Single_Spawn_Runs_Body'Access,
         "Spawn (Body) actually runs Body — counter advances by "
         & "exactly one between Spawn and Shutdown return");
      Register_Routine
        (T, Test_Multiple_Spawns_All_Run'Access,
         "100 Spawns of Increment_Once leave Counter = 100 — "
         & "queue ordering doesn't drop or duplicate goroutines");
      Register_Routine
        (T, Test_Yield_Re_Schedules'Access,
         "A goroutine that calls Yield N times completes all N "
         & "iterations — the worker re-pushes YIELDED goroutines");
      Register_Routine
        (T, Test_Yield_From_Non_Goroutine_Is_Noop'Access,
         "Yield called from the main task (no current goroutine) "
         & "returns immediately and does not stall the test");
      Register_Routine
        (T, Test_Init_Twice_Raises'Access,
         "Init called twice without an intervening Shutdown raises "
         & "Program_Error — the precondition documented on Init");
      Register_Routine
        (T, Test_Spawn_Before_Init_Raises'Access,
         "Spawn called before Init raises Program_Error — the "
         & "precondition documented on Spawn");
      Register_Routine
        (T, Test_Pool_Distributes_Across_Workers'Access,
         "Init (Workers => 2) + Spawn N: goroutines actually land "
         & "on >= 2 distinct worker tasks (sub-item 3b)");
      Register_Routine
        (T, Test_Init_Default_Number_Of_CPUs'Access,
         "Init () with no args sizes the pool to Number_Of_CPUs "
         & "(exercises the Workers => 0 default branch)");
      Register_Routine
        (T, Test_Park_Unpark_Round_Trip'Access,
         "Park suspends the calling goroutine; Unpark from the main "
         & "task resumes it on its bound worker (sub-item 3d)");
      Register_Routine
        (T, Test_Park_From_Non_Goroutine_Is_Noop'Access,
         "Park from the main task (no current goroutine) returns "
         & "immediately and does not stall the test");
      Register_Routine
        (T, Test_Unpark_Of_No_Goroutine_Is_Noop'Access,
         "Unpark on No_Goroutine returns cleanly (documented no-op "
         & "for generated code that may carry a null handle)");
      Register_Routine
        (T, Test_Unpark_Of_Never_Run_Goroutine_Raises'Access,
         "Unpark on a goroutine that has never run raises "
         & "Program_Error — there is no correct routing target");
      Register_Routine
        (T, Test_Enter_Exit_Syscall_Round_Trip'Access,
         "Enter_Syscall suspends the calling goroutine; Exit_Syscall "
         & "from another task resumes it on its bound worker (sub-"
         & "item 3e — Park/Unpark equivalents under separate symbols)");
      Register_Routine
        (T, Test_Syscall_Doesnt_Stall_Siblings'Access,
         "While a goroutine is in Enter_Syscall on Workers => 2, the "
         & "scheduler still runs other goroutines to completion on "
         & "the free worker (sub-item 3e verify gate)");
      Register_Routine
        (T, Test_Goroutine_Body_That_Raises_Is_Reaped_Cleanly'Access,
         "A goroutine whose body raises is reaped without taking the "
         & "worker down — Shutdown returns and a follow-up goroutine "
         & "still runs (covers Goroutine_Trampoline's exception arm)");
      Register_Routine
        (T, Test_Panic_Isolation_Across_Goroutines'Access,
         "100 concurrent panicking goroutines on Workers => 4 each "
         & "Recover their own panic value — panic state is per-"
         & "goroutine, not a shared/global or TLS stack");
      Register_Routine
        (T, Test_Panic_Main_Fallback'Access,
         "Do_Panic / Recover from the main task (no current goroutine) "
         & "route via Main_Local_Storage — keeps the v1 single-"
         & "threaded panic path working post-promotion");
      Register_Routine
        (T, Test_Closure_Roundtrip_Across_Goroutines'Access,
         "100 spawns with distinct (A, B) closure payloads each read "
         & "back their own pair via Closure (Current) — Spawn's opaque "
         & "payload round-trips without cross-contamination");
      Register_Routine
        (T, Test_Closure_Of_No_Goroutine_Is_Null'Access,
         "Closure (No_Goroutine) returns Null_Address — generated "
         & "Go_Worker code can call Closure (Current) unconditionally");
   end Register_Tests;

   procedure Test_Init_Shutdown_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Defensive: a previous test that raised before its own Shutdown
      --  could leave the scheduler initialised. AUnit doesn't guarantee
      --  ordering, and Init-twice is a precondition violation; the
      --  shutdown-when-not-init contract is documented as no-op so
      --  this is always safe.
      Shutdown;
      Init (Workers => 1);
      Shutdown;
      --  Reached here without raising = success. The goroutine pool
      --  drained correctly with zero work in flight.
      Assert (True, "Init+Shutdown completed without raising");
   end Test_Init_Shutdown_Empty;

   procedure Test_Shutdown_Without_Init_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Documented contract: Shutdown without prior Init is a no-op.
      --  A regression that raised here would break clean teardown
      --  paths in higher layers (the user's main() may call Shutdown
      --  on every exit branch even when Init was guarded by a
      --  conditional that didn't fire).
      Shutdown;
      Assert (True, "Shutdown without Init returned cleanly");
   end Test_Shutdown_Without_Init_Is_Noop;

   procedure Test_Single_Spawn_Runs_Body
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Goroutine_Id;
   begin
      Counter := 0;
      Shutdown;  --  defensive: prior-test leftover wouldn't survive Init
      Init (Workers => 1);
      Unused_G := Spawn (Increment_Once'Access);
      Shutdown;
      Assert (Counter = 1,
              "Increment_Once body did not run; Counter ="
              & Counter'Image);
   end Test_Single_Spawn_Runs_Body;

   procedure Test_Multiple_Spawns_All_Run
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Goroutine_Id;
   begin
      Counter := 0;
      Shutdown;
      Init (Workers => 1);
      for Iteration in 1 .. 100 loop
         Unused_G := Spawn (Increment_Once'Access);
      end loop;
      Shutdown;
      Assert (Counter = 100,
              "Expected Counter = 100, got" & Counter'Image);
   end Test_Multiple_Spawns_All_Run;

   procedure Test_Yield_Re_Schedules
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Goroutine_Id;
   begin
      Yields_Run := 0;
      Yield_Done := False;
      Shutdown;
      Init (Workers => 1);
      Unused_G := Spawn (Yield_Then_Mark'Access);
      Shutdown;
      Assert (Yields_Run = Yield_Iterations,
              "Expected" & Yield_Iterations'Image
              & " yield iterations, got" & Yields_Run'Image);
      Assert (Yield_Done,
              "Yield_Then_Mark did not reach the post-loop marker");
   end Test_Yield_Re_Schedules;

   procedure Test_Yield_From_Non_Goroutine_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Init bumps the scheduler online but we never Spawn, so the
      --  main test task is not a goroutine context. Yield must early-
      --  exit. A regression that called Switch_To on a null
      --  Worker_Ctx would either raise or hang here.
      Shutdown;
      Init (Workers => 1);
      Gada.Async.Scheduler.Yield;
      Shutdown;
      Assert (True, "Yield from main task returned cleanly");
   end Test_Yield_From_Non_Goroutine_Is_Noop;

   procedure Test_Init_Twice_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Raised : Boolean := False;
   begin
      Shutdown;
      Init (Workers => 1);
      begin
         Init (Workers => 1);
      exception
         when Program_Error =>
            Raised := True;
      end;
      Shutdown;
      Assert (Raised,
              "Init called twice without Shutdown should raise "
              & "Program_Error");
   end Test_Init_Twice_Raises;

   procedure Test_Spawn_Before_Init_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Raised   : Boolean := False;
      Unused_G : Goroutine_Id;
   begin
      Shutdown;  --  ensure not initialised
      begin
         Unused_G := Spawn (Increment_Once'Access);
      exception
         when Program_Error =>
            Raised := True;
      end;
      Assert (Raised,
              "Spawn before Init should raise Program_Error");
   end Test_Spawn_Before_Init_Raises;

   procedure Test_Pool_Distributes_Across_Workers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Goroutine_Id;
      --  Sub-item 3b's verify gate: distribution observed across >= 2
      --  workers. With Workers => 2 and N_Spawns sufficiently large,
      --  Ada's protected-entry FIFO at Run_Queue.Pop fairly distributes
      --  fresh spawns: the first goroutine is popped by whichever
      --  worker was first in the entry queue, the second goroutine
      --  unblocks the next worker, and so on. Even if a fast worker
      --  occasionally races ahead and grabs two in a row before its
      --  sibling wakes, with N_Spawns = 100 the slow worker gets
      --  multiple chances to participate.
      --
      --  Distinct >= 2 is the property under test. The exact partition
      --  is non-deterministic by design — Go's scheduler is similarly
      --  permissive about which goroutine lands on which P.
      N_Spawns : constant := 100;
   begin
      Worker_Recorder.Reset;
      Shutdown;
      Init (Workers => 2);
      for Iteration in 1 .. N_Spawns loop
         Unused_G := Spawn (Record_Current_Worker'Access);
      end loop;
      Shutdown;
      Assert (Worker_Recorder.Distinct_Count >= 2,
              "Expected goroutines to run on >= 2 worker tasks; saw"
              & Worker_Recorder.Distinct_Count'Image
              & " distinct task ids across" & N_Spawns'Image
              & " spawns");
   end Test_Pool_Distributes_Across_Workers;

   procedure Test_Init_Default_Number_Of_CPUs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Init () with no args should size the worker pool to
      --  System.Multiprocessors.Number_Of_CPUs — that's the Workers => 0
      --  default branch in Init's body. Every other test passes Workers
      --  explicitly (1 for deterministic single-worker, 2 for the
      --  multi-worker distribution test), so without this test the
      --  Number_Of_CPUs branch is uncovered. We don't Spawn anything;
      --  the worker pool comes up, has nothing to do, and is torn down.
      --  The property under test is "Init + Shutdown with default
      --  Workers count completes without raising".
      Shutdown;
      Init;
      Shutdown;
      Assert (True, "Init+Shutdown with default Workers count completed");
   end Test_Init_Default_Number_Of_CPUs;

   procedure Test_Park_Unpark_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Park_Body marks '1', Parks, marks '2'. Worker observes
      --  PARKED state on Switch_To return, leaves G in limbo (does
      --  not re-enqueue). Main task waits for Park_Tracker = "1"
      --  (which proves the goroutine ran and parked), then Unparks
      --  via the saved Goroutine_Id. Worker's Pop on its own Inbox
      --  wakes (Inject_Local just landed), G resumes from Park's
      --  Switch_To, runs Mark ('2'), returns naturally, gets reaped.
      --
      --  After Shutdown, Park_Tracker.Sequence must be exactly "12".
      --  Workers => 1 because: (a) the test isn't about distribution,
      --  (b) Park_Tracker is shared state that single-worker
      --  serialises trivially.
      Park_Tracker.Reset;
      Shutdown;
      Init (Workers => 1);
      The_Parked_Goroutine := Spawn (Park_Body'Access);

      --  Wait for the goroutine to reach Park. We use a brief
      --  bounded delay loop rather than a fixed sleep — fast on
      --  warm caches, still bounded if the host is heavily loaded.
      --  The goroutine reaches Mark ('1') very quickly (sub-ms);
      --  100 × 1 ms gives 100 ms ceiling — orders of magnitude
      --  beyond what a healthy CI runner needs.
      for Attempt in 1 .. 100 loop
         exit when Park_Tracker.Sequence = "1";
         delay 0.001;
      end loop;
      Assert (Park_Tracker.Sequence = "1",
              "Park_Body did not reach Park before timeout; "
              & "Sequence = '" & Park_Tracker.Sequence & "'");

      Unpark (The_Parked_Goroutine);
      Shutdown;
      Assert (Park_Tracker.Sequence = "12",
              "Expected Park_Tracker = '12', got '"
              & Park_Tracker.Sequence & "'");
   end Test_Park_Unpark_Round_Trip;

   procedure Test_Park_From_Non_Goroutine_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Park called from the main test task (no current goroutine)
      --  must early-exit. A regression that called Switch_To on a
      --  null Worker_Ctx would either raise or hang.
      Shutdown;
      Init (Workers => 1);
      Gada.Async.Scheduler.Park;
      Shutdown;
      Assert (True, "Park from main task returned cleanly");
   end Test_Park_From_Non_Goroutine_Is_Noop;

   procedure Test_Unpark_Of_No_Goroutine_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Unpark on the No_Goroutine sentinel must early-exit. This
      --  matches the contract on Free for Gada.Async.Context.Null_Context
      --  and lets generated code call Unpark unconditionally on a
      --  handle field that may or may not have been Spawn'd.
      Shutdown;
      Init (Workers => 1);
      Unpark (No_Goroutine);
      Shutdown;
      Assert (True, "Unpark (No_Goroutine) returned cleanly");
   end Test_Unpark_Of_No_Goroutine_Is_Noop;

   procedure Test_Unpark_Of_Never_Run_Goroutine_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Goroutine_Id;
   begin
      --  Drives Self_Test_Unpark_Of_Never_Run inside a goroutine on
      --  the only worker — see that procedure's comment for why this
      --  shape avoids the obvious race ("worker pops Other before
      --  main task Unparks").
      Park_Tracker.Reset;
      Counter := 0;
      Shutdown;
      Init (Workers => 1);
      Unused_G := Spawn (Self_Test_Unpark_Of_Never_Run'Access);
      Shutdown;
      Assert (Park_Tracker.Sequence = "R",
              "Expected Park_Tracker = 'R' (Program_Error raised on "
              & "Unpark of never-run goroutine), got '"
              & Park_Tracker.Sequence & "'");
   end Test_Unpark_Of_Never_Run_Goroutine_Raises;

   procedure Test_Enter_Exit_Syscall_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Syscall_G : Goroutine_Id;
   begin
      --  Mirrors Test_Park_Unpark_Round_Trip but drives Enter_Syscall
      --  / Exit_Syscall instead of Park / Unpark. The goroutine marks
      --  '1', enters syscall (parks), and only marks '3' after the
      --  test main task has Exit_Syscall'd it. Final sequence "13"
      --  proves both halves of the round-trip.
      --
      --  Workers => 1 is sufficient: the test isn't about distribution.
      --  After the goroutine parks, the only worker is free; main
      --  task drives Exit_Syscall directly.
      Park_Tracker.Reset;
      Shutdown;
      Init (Workers => 1);
      Syscall_G := Spawn (Syscall_Body'Access);

      --  Wait for Mark ('1') — proves the goroutine reached
      --  Enter_Syscall and parked. Same bounded-poll shape as
      --  Test_Park_Unpark_Round_Trip.
      for Attempt in 1 .. 100 loop
         exit when Park_Tracker.Sequence = "1";
         delay 0.001;
      end loop;
      Assert (Park_Tracker.Sequence = "1",
              "Syscall_Body did not reach Enter_Syscall before "
              & "timeout; Sequence = '" & Park_Tracker.Sequence & "'");

      Exit_Syscall (Syscall_G);
      Shutdown;
      Assert (Park_Tracker.Sequence = "13",
              "Expected Park_Tracker = '13' (Enter_Syscall + Exit_"
              & "Syscall round-trip), got '" & Park_Tracker.Sequence
              & "'");
   end Test_Enter_Exit_Syscall_Round_Trip;

   procedure Test_Syscall_Doesnt_Stall_Siblings
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Syscall_G : Goroutine_Id;
      Unused_G  : Goroutine_Id;
      --  N_Siblings: how many sibling goroutines we expect to drain
      --  while Syscall_G is parked. Picked at 50 — large enough to
      --  visibly demonstrate sibling progress, small enough to
      --  drain in well under the 100 ms poll budget on every CI
      --  runner we contract for.
      N_Siblings : constant := 50;
   begin
      --  Verify gate for sub-item 3e: a goroutine that calls Enter_
      --  Syscall does not stall sibling workers. Because Enter_
      --  Syscall is currently a Park-equivalent, the property holds
      --  trivially under our libco-pinning model — once a goroutine
      --  parks, its worker is free to pick up other work, and any
      --  other workers are independently free anyway. The test still
      --  has value as:
      --
      --    (1) a regression guard — a future Enter_Syscall that
      --        accidentally held its worker (e.g. by busy-waiting
      --        on the helper thread) would surface here as a hung
      --        test or a sibling-counter that didn't advance.
      --    (2) a documented usage shape — the goroutine + helper-
      --        thread + Exit_Syscall sequence here is the same shape
      --        Phase 4's per-syscall I/O wrappers will emit.
      Park_Tracker.Reset;
      Counter := 0;
      Shutdown;
      Init (Workers => 2);

      Syscall_G := Spawn (Syscall_Body'Access);

      --  Wait for the goroutine to enter syscall (mark '1') before
      --  we start counting sibling progress. Without this barrier
      --  the assertion below would race the goroutine's first
      --  Switch_To.
      for Attempt in 1 .. 100 loop
         exit when Park_Tracker.Sequence = "1";
         delay 0.001;
      end loop;
      Assert (Park_Tracker.Sequence = "1",
              "Syscall_Body did not enter syscall before timeout; "
              & "Sequence = '" & Park_Tracker.Sequence & "'");

      --  Spawn N_Siblings simple-body goroutines. With Syscall_G
      --  parked and Workers => 2, both workers are eligible to run
      --  these. They must drain to completion within the poll
      --  budget.
      for Iteration in 1 .. N_Siblings loop
         Unused_G := Spawn (Increment_Once'Access);
      end loop;

      for Attempt in 1 .. 100 loop
         exit when Counter = N_Siblings;
         delay 0.001;
      end loop;
      Assert (Counter = N_Siblings,
              "Sibling goroutines did not drain while Syscall_G "
              & "was parked; Counter =" & Counter'Image
              & ", expected" & N_Siblings'Image);

      --  Wake the parked goroutine and reap.
      Exit_Syscall (Syscall_G);
      Shutdown;
      Assert (Park_Tracker.Sequence = "13",
              "Syscall_G did not complete its post-Exit_Syscall "
              & "marker; Sequence = '" & Park_Tracker.Sequence & "'");
   end Test_Syscall_Doesnt_Stall_Siblings;

   procedure Test_Goroutine_Body_That_Raises_Is_Reaped_Cleanly
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Goroutine_Id;
   begin
      --  The contract under test: Goroutine_Trampoline catches Ada
      --  exceptions raised from the user body so they don't propagate
      --  across the libco C-convention boundary, AND it still sets
      --  State => DONE so the worker reaps the cothread on the next
      --  case-arm. Two observable consequences:
      --
      --    (1) Shutdown returns rather than hanging on Drain (which
      --        would happen if the worker died at the unexpected-
      --        RUNNING-state Program_Error arm without a balancing
      --        Worker_Stopped).
      --    (2) A follow-up goroutine on the same Init still runs to
      --        completion — proves the worker is alive after the
      --        raising body, not just "didn't deadlock once."
      Counter := 0;
      Shutdown;
      Init (Workers => 1);
      Unused_G := Spawn (Body_That_Raises'Access);

      --  Wait for the raising body to actually fire and be reaped.
      --  Without a follow-up Spawn we'd race Shutdown against the
      --  trampoline's State := DONE write; with a counted follow-up
      --  we wait deterministically on Counter rather than on time.
      Unused_G := Spawn (Increment_Once'Access);
      Shutdown;
      Assert (Counter = 1,
              "Follow-up goroutine did not run after a raising body; "
              & "Counter =" & Counter'Image
              & " (expected 1) — trampoline likely killed the worker "
              & "rather than reaping the raised goroutine cleanly");
   end Test_Goroutine_Body_That_Raises_Is_Reaped_Cleanly;

   procedure Test_Panic_Isolation_Across_Goroutines
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Goroutine_Id;
   begin
      --  The promotion's headline property: panic state partitions by
      --  *goroutine*, not by OS thread or process. 100 goroutines on a
      --  4-worker pool each Do_Panic their own Id, Yield (interleaving
      --  sibling pushes on the shared worker), then Recover; every one
      --  must get its own Id back. A process-global stack, or a TLS
      --  slot shared across the goroutines multiplexed onto a worker,
      --  fails here — that is exactly the multiplexing hazard the
      --  promotion closes.
      Panic_Ledger.Reset;
      Shutdown;
      Init (Workers => 4);
      for K in 1 .. Panic_Goroutines loop
         Unused_G := Spawn (Panic_Isolation_Body'Access);
      end loop;
      Shutdown;
      Assert (Panic_Ledger.Marked = Panic_Goroutines,
              "Expected all" & Panic_Goroutines'Image
              & " panicking goroutines to run and record, got"
              & Panic_Ledger.Marked'Image);
      Assert (Panic_Ledger.All_Isolated,
              "Some goroutine's Recover returned another goroutine's "
              & "panic value — panic state is NOT per-goroutine "
              & "(shared/global or TLS stack regression)");
   end Test_Panic_Isolation_Across_Goroutines;

   procedure Test_Panic_Main_Fallback
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Got    : Integer := -1;
      Caught : Boolean := False;
   begin
      --  Outside any goroutine, Get/Set_Local_Storage route to the
      --  scheduler's Main_Local_Storage global, and Do_Panic / Recover
      --  must work there exactly as in the v1 single-threaded runtime
      --  (this is what keeps panic_suite green post-promotion).
      Assert (Current = No_Goroutine,
              "precondition: this test runs outside any goroutine");
      begin
         Int_Panic.Do_Panic (42);
      exception
         when Int_Panic.Panicking =>
            Caught := True;
            Got := Int_Panic.Recover;
      end;
      Assert (Caught, "Panicking should be raised from main context");
      Assert (Got = 42,
              "main-context Do_Panic/Recover must round-trip via "
              & "Main_Local_Storage, got" & Got'Image);
      Assert (not Int_Panic.Is_Panicking,
              "panic state must be cleared after main-context Recover");
      --  Do_Panic allocated the state behind the main fallback slot,
      --  so the slot the scheduler reports for main context is now set.
      Assert (Get_Local_Storage /= System.Null_Address,
              "main-context Do_Panic should have populated "
              & "Main_Local_Storage");
   end Test_Panic_Main_Fallback;

   procedure Test_Closure_Roundtrip_Across_Goroutines
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_G : Goroutine_Id;
   begin
      --  Spawn 100 goroutines, each carrying a distinct heap-allocated
      --  (A => K, B => K * 1000) closure. Every worker reads its own
      --  payload back through Closure (Current); the per-spawn pointer
      --  is the only channel for the data (bodies take no parameters).
      --  All_Correct holds iff no spawn observed another's payload.
      Closure_Ledger.Reset;
      Shutdown;
      Init (Workers => 4);
      for K in 1 .. Closure_Goroutines loop
         declare
            P : constant Arg_Pair_Access :=
              new Arg_Pair'(A => K, B => K * 1000);
         begin
            Unused_G := Spawn (Closure_Worker'Access, To_Address (P));
         end;
      end loop;
      Shutdown;
      Assert (Closure_Ledger.Marked = Closure_Goroutines,
              "Expected all" & Closure_Goroutines'Image
              & " closure-carrying goroutines to run, got"
              & Closure_Ledger.Marked'Image);
      Assert (Closure_Ledger.All_Correct,
              "A goroutine read a closure payload that was not its own — "
              & "Spawn's per-spawn closure pointer cross-contaminated");
   end Test_Closure_Roundtrip_Across_Goroutines;

   procedure Test_Closure_Of_No_Goroutine_Is_Null
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Closure (No_Goroutine) = System.Null_Address,
              "Closure (No_Goroutine) must be Null_Address so generated "
              & "Go_Worker code can call Closure (Current) blind");
   end Test_Closure_Of_No_Goroutine_Is_Null;

end Scheduler_Suite;
