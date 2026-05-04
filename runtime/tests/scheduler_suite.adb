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
with AUnit.Assertions; use AUnit.Assertions;

with Gada.Async.Scheduler; use Gada.Async.Scheduler;

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

   procedure Increment_Once is
   begin
      Counter := Counter + 1;
   end Increment_Once;

   procedure Yield_Then_Mark is
   begin
      for Iteration in 1 .. Yield_Iterations loop
         Yields_Run := Yields_Run + 1;
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
            Len := Len + 1;
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
                  Count := Count + 1;
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
            Last := Last + 1;
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

end Scheduler_Suite;
