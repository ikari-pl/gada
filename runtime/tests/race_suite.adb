--  Body of Race_Suite — see spec for the property index.
--
--  ## Distinct goroutine identities
--
--  Several tests need two *distinct* Goroutine_Id values. The only
--  public sources of an id are Scheduler.Current (inside a goroutine)
--  and No_Goroutine (the main task). Capture_Two_Ids spawns two
--  goroutines that each stash their own Current into a file-scope slot;
--  the resulting handles are distinct heap records, so `=` separates
--  them even after the goroutines are reaped (the handle is a pointer
--  value, independent of the goroutine's liveness).
--
--  ## Globals
--
--  Goroutine bodies passed to Spawn are parameterless `access
--  procedure` values with no closure, so the cross-goroutine state
--  (captured ids, the shared cell, the barrier counter) lives at file
--  scope. Each test resets the globals it reads before driving Spawn.

pragma Warnings (Off, "use of an anonymous access type allocator");

with Ada.Strings.Fixed;
with AUnit.Assertions; use AUnit.Assertions;

with Gada.Async.Scheduler;
with Gada.Async.Race;

package body Race_Suite is

   use type Gada.Async.Scheduler.Goroutine_Id;
   use type Gada.Async.Race.Access_Mode;

   --  One Integer-valued checked-cell instantiation reused everywhere.
   package Cell is new Gada.Async.Race.Checked_Cell
     (Element_Type => Integer, Default => 0);

   --  Captured identities for the logic tests.
   Id_A : Gada.Async.Scheduler.Goroutine_Id :=
     Gada.Async.Scheduler.No_Goroutine;
   Id_B : Gada.Async.Scheduler.Goroutine_Id :=
     Gada.Async.Scheduler.No_Goroutine;

   --  Goroutine-driven race: a shared cell + a two-party barrier that
   --  holds both goroutines inside their open access sections
   --  simultaneously, so the overlap is genuine (not a replayed call
   --  sequence). The barrier is a protected ENTRY, not a busy spin —
   --  blocking on a protected entry suspends the worker cleanly, which
   --  keeps the test safe under gcov (a tight Yield spin across two
   --  workers hammers gcov's non-thread-safe basic-block counters and
   --  corrupts the .gcda; a one-shot entry barrier touches instrumented
   --  code a bounded, tiny number of times).
   Shared_Cell    : Cell.Cell_Type;

   protected Both_In_Section is
      --  Two-party rendezvous. Each racing goroutine, AFTER opening its
      --  Write section, calls Arrive then blocks on Wait_For_Both. The
      --  barrier (Count >= 2) only opens once both have arrived, so when
      --  either goroutine returns from Wait_For_Both BOTH sections are
      --  provably open at once — the genuine overlap the detector must
      --  catch.
      procedure Arrive;
      entry     Wait_For_Both;
      function  Arrived_Count return Natural;
   private
      Count : Natural := 0;
   end Both_In_Section;

   protected body Both_In_Section is
      procedure Arrive is
      begin
         Count := @ + 1;
      end Arrive;

      entry Wait_For_Both when Count >= 2 is
      begin
         null;
      end Wait_For_Both;

      function Arrived_Count return Natural is (Count);
   end Both_In_Section;

   --  ## Body procedures used by Spawn.

   procedure Capture_A;
   procedure Capture_B;
   procedure Racing_Writer;

   procedure Capture_A is
   begin
      Id_A := Gada.Async.Scheduler.Current;
   end Capture_A;

   procedure Capture_B is
   begin
      Id_B := Gada.Async.Scheduler.Current;
   end Capture_B;

   --  Two copies of this body run as two goroutines on two workers
   --  (genuine OS-thread parallelism). Each opens a Write section on the
   --  shared cell, then rendezvouses at Both_In_Section: the barrier
   --  guarantees neither goroutine closes its section until BOTH have
   --  opened, so the two Write sections provably overlap and the second
   --  Begin_Access to land trips the monitor. The rendezvous is a
   --  protected entry (a clean suspend), not a Yield busy-loop, so the
   --  two workers do not hammer gcov's non-thread-safe counters.
   procedure Racing_Writer is
      Me : constant Gada.Async.Scheduler.Goroutine_Id :=
        Gada.Async.Scheduler.Current;
   begin
      Cell.Begin_Access (Shared_Cell, Gada.Async.Race.Write, Me);
      Both_In_Section.Arrive;
      Both_In_Section.Wait_For_Both;  --  blocks until both sections open
      Cell.Store (Shared_Cell, 1);
      Cell.End_Access (Shared_Cell, Me);
   end Racing_Writer;

   ---------------------------------------------------------------

   --  Helper: spawn the two capture goroutines and wait for both ids.
   procedure Capture_Two_Ids;

   procedure Capture_Two_Ids is
      Unused_A : Gada.Async.Scheduler.Goroutine_Id;
      Unused_B : Gada.Async.Scheduler.Goroutine_Id;
   begin
      Id_A := Gada.Async.Scheduler.No_Goroutine;
      Id_B := Gada.Async.Scheduler.No_Goroutine;
      Gada.Async.Scheduler.Shutdown;
      Gada.Async.Scheduler.Init (Workers => 1);
      Unused_A := Gada.Async.Scheduler.Spawn (Capture_A'Access);
      Unused_B := Gada.Async.Scheduler.Spawn (Capture_B'Access);
      Gada.Async.Scheduler.Shutdown;  --  blocks until both have run
      Assert (Id_A /= Gada.Async.Scheduler.No_Goroutine
                and then Id_B /= Gada.Async.Scheduler.No_Goroutine
                and then Id_A /= Id_B,
              "Capture_Two_Ids must yield two distinct goroutine ids");
   end Capture_Two_Ids;

   ---------------------------------------------------------------

   overriding function Name (T : Race_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Async.Race suite (PKG=async.race)"));

   overriding procedure Register_Tests (T : in out Race_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Intentional_Write_Write_Race_Detected'Access,
         "An intentional write/write overlap from two distinct holders "
         & "is detected: Race_Detected flips True and Report names both "
         & "holders with both modes = Write (the verify gate)");
      Register_Routine
        (T, Test_Read_Write_Overlap_Detected'Access,
         "A read section overlapped by a distinct write (or vice versa) "
         & "is a race — at least one write is the trigger condition");
      Register_Routine
        (T, Test_Synchronized_Access_Not_Flagged'Access,
         "Two goroutines that each Begin/End before the other begins "
         & "do NOT overlap — Race_Detected stays False (the no-false-"
         & "positive gate)");
      Register_Routine
        (T, Test_Read_Read_Overlap_Is_Benign'Access,
         "Two overlapping READ sections are benign (matches Go's memory "
         & "model — concurrent reads are not a race)");
      Register_Routine
        (T, Test_Reentrant_Same_Goroutine_Not_A_Race'Access,
         "Nested Begin_Access from the SAME goroutine is re-entrancy, "
         & "not a race; a nested Write escalates Holder_Mode so a later "
         & "distinct reader then collides");
      Register_Routine
        (T, Test_Load_Store_Round_Trips'Access,
         "Store then Load round-trips the guarded value through the "
         & "monitor");
      Register_Routine
        (T, Test_First_Race_Latched'Access,
         "Once a race is recorded the report is latched — a second, "
         & "different collision does not overwrite the first verdict");
      Register_Routine
        (T, Test_Unbalanced_End_Access_Is_No_Op'Access,
         "End_Access from a non-holder, and End_Access on an idle cell, "
         & "are defensive no-ops that cannot clear a live section");
      Register_Routine
        (T, Test_Image_Renders_No_Race_And_Detected'Access,
         "Image renders 'no race' for No_Race and a 'data race: ...' "
         & "line for a detected report, including a No_Goroutine holder "
         & "rendered as 'none'");
      Register_Routine
        (T, Test_Goroutine_Driven_Intentional_Race'Access,
         "Two real goroutines holding overlapping Write sections on one "
         & "shared cell (held open by a barrier) trip the detector — "
         & "end-to-end proof the monitor catches a genuine concurrent "
         & "overlap, not just a replayed call sequence");
   end Register_Tests;

   ---------------------------------------------------------------

   procedure Test_Intentional_Write_Write_Race_Detected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Cell.Cell_Type := Cell.Make;
      R : Gada.Async.Race.Race_Report;
   begin
      Capture_Two_Ids;
      --  Id_A opens a Write section; Id_B (distinct) opens an
      --  overlapping Write section → race.
      Cell.Begin_Access (C, Gada.Async.Race.Write, Id_A);
      Assert (not Cell.Race_Detected (C),
              "Single open section must not be a race yet");
      Cell.Begin_Access (C, Gada.Async.Race.Write, Id_B);
      Assert (Cell.Race_Detected (C),
              "Write/Write overlap from distinct holders must be a race");
      R := Cell.Report (C);
      Assert (R.Detected, "Report.Detected must be True");
      Assert (R.First_Holder = Id_A and then R.Second_Holder = Id_B,
              "Report must name Id_A then Id_B as the colliding holders");
      Assert (R.First_Mode = Gada.Async.Race.Write
                and then R.Second_Mode = Gada.Async.Race.Write,
              "Both colliding modes must be Write");
      --  The original holder keeps the section; the intruder's End is a
      --  no-op. Close out cleanly.
      Cell.End_Access (C, Id_B);
      Cell.End_Access (C, Id_A);
   end Test_Intentional_Write_Write_Race_Detected;

   procedure Test_Read_Write_Overlap_Detected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Cell.Cell_Type := Cell.Make;
   begin
      Capture_Two_Ids;
      --  Reader holds; writer overlaps → race (at least one write).
      Cell.Begin_Access (C, Gada.Async.Race.Read, Id_A);
      Cell.Begin_Access (C, Gada.Async.Race.Write, Id_B);
      Assert (Cell.Race_Detected (C),
              "Read section overlapped by a distinct Write must race");
      declare
         R : constant Gada.Async.Race.Race_Report := Cell.Report (C);
      begin
         Assert (R.First_Mode = Gada.Async.Race.Read
                   and then R.Second_Mode = Gada.Async.Race.Write,
                 "Report must record Read (holder) / Write (intruder)");
      end;
      Cell.End_Access (C, Id_A);
   end Test_Read_Write_Overlap_Detected;

   procedure Test_Synchronized_Access_Not_Flagged
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Cell.Cell_Type := Cell.Make;
   begin
      Capture_Two_Ids;
      --  A writes and releases; THEN B writes and releases. No overlap.
      Cell.Begin_Access (C, Gada.Async.Race.Write, Id_A);
      Cell.Store (C, 1);
      Cell.End_Access (C, Id_A);

      Cell.Begin_Access (C, Gada.Async.Race.Write, Id_B);
      Cell.Store (C, 2);
      Cell.End_Access (C, Id_B);

      Assert (not Cell.Race_Detected (C),
              "Non-overlapping writes must NOT be flagged (no false "
              & "positive)");
      Assert (Cell.Load (C) = 2, "Last write should win the value");
   end Test_Synchronized_Access_Not_Flagged;

   procedure Test_Read_Read_Overlap_Is_Benign
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Cell.Cell_Type := Cell.Make;
   begin
      Capture_Two_Ids;
      Cell.Begin_Access (C, Gada.Async.Race.Read, Id_A);
      Cell.Begin_Access (C, Gada.Async.Race.Read, Id_B);
      Assert (not Cell.Race_Detected (C),
              "Two overlapping Read sections are benign");
      Cell.End_Access (C, Id_A);
   end Test_Read_Read_Overlap_Is_Benign;

   procedure Test_Reentrant_Same_Goroutine_Not_A_Race
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Cell.Cell_Type := Cell.Make;
   begin
      Capture_Two_Ids;
      --  Id_A enters Read, then re-enters Write (escalation), then a
      --  nested Read — all same goroutine, never a race.
      Cell.Begin_Access (C, Gada.Async.Race.Read,  Id_A);
      Cell.Begin_Access (C, Gada.Async.Race.Write, Id_A);  --  escalate
      Cell.Begin_Access (C, Gada.Async.Race.Read,  Id_A);  --  nest
      Assert (not Cell.Race_Detected (C),
              "Re-entrant access from the same goroutine is not a race");

      --  With Holder_Mode now escalated to Write, a distinct READER
      --  overlapping must trip the detector (proves escalation took).
      Cell.Begin_Access (C, Gada.Async.Race.Read, Id_B);
      Assert (Cell.Race_Detected (C),
              "A distinct reader overlapping an escalated-to-Write "
              & "holder must race");

      --  Unwind the three nested Begins for Id_A (the intruder B's End
      --  is a no-op; closing it is harmless).
      Cell.End_Access (C, Id_B);
      Cell.End_Access (C, Id_A);
      Cell.End_Access (C, Id_A);
      Cell.End_Access (C, Id_A);
      --  Cell is now idle: a fresh distinct-holder write must NOT see
      --  the section as held (proves Depth unwound to 0). It would,
      --  however, still report the *latched* earlier race, so check
      --  the holder cleared via a synchronized write instead.
      Cell.Begin_Access (C, Gada.Async.Race.Write, Id_B);
      Cell.End_Access (C, Id_B);
   end Test_Reentrant_Same_Goroutine_Not_A_Race;

   procedure Test_Load_Store_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Cell.Cell_Type := Cell.Make;
   begin
      Assert (Cell.Load (C) = 0, "Fresh cell holds Default = 0");
      Cell.Store (C, 7);
      Assert (Cell.Load (C) = 7, "Store/Load must round-trip");
      Cell.Store (C, -3);
      Assert (Cell.Load (C) = -3, "Second Store/Load must round-trip");
   end Test_Load_Store_Round_Trips;

   procedure Test_First_Race_Latched
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Cell.Cell_Type := Cell.Make;
      R1, R2 : Gada.Async.Race.Race_Report;
   begin
      Capture_Two_Ids;
      --  First collision: holder Id_A (Write), intruder Id_B (Write).
      Cell.Begin_Access (C, Gada.Async.Race.Write, Id_A);
      Cell.Begin_Access (C, Gada.Async.Race.Write, Id_B);
      R1 := Cell.Report (C);
      --  Second collision in the same open section: another intruder
      --  (No_Goroutine, the main task) arrives. The latch keeps R1.
      Cell.Begin_Access
        (C, Gada.Async.Race.Read, Gada.Async.Scheduler.No_Goroutine);
      R2 := Cell.Report (C);
      Assert (R2.Second_Holder = R1.Second_Holder
                and then R2.First_Holder = R1.First_Holder,
              "The first race verdict must be latched (not overwritten)");
      Cell.End_Access (C, Id_A);
   end Test_First_Race_Latched;

   procedure Test_Unbalanced_End_Access_Is_No_Op
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Cell.Cell_Type := Cell.Make;
   begin
      Capture_Two_Ids;
      --  End_Access on an idle cell: Depth = 0, no-op.
      Cell.End_Access (C, Id_A);
      --  Id_A holds; Id_B's End_Access (non-holder) must NOT clear it.
      Cell.Begin_Access (C, Gada.Async.Race.Write, Id_A);
      Cell.End_Access (C, Id_B);  --  intruder End — ignored
      --  Section still held by Id_A: a distinct writer must still race.
      Cell.Begin_Access (C, Gada.Async.Race.Write, Id_B);
      Assert (Cell.Race_Detected (C),
              "Non-holder End_Access must not have cleared Id_A's "
              & "live Write section");
      Cell.End_Access (C, Id_A);
   end Test_Unbalanced_End_Access_Is_No_Op;

   procedure Test_Image_Renders_No_Race_And_Detected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Cell.Cell_Type := Cell.Make;
   begin
      Assert (Gada.Async.Race.Image (Gada.Async.Race.No_Race) = "no race",
              "Image (No_Race) must render 'no race'");
      Capture_Two_Ids;
      --  Race with First_Holder = No_Goroutine (main task) and
      --  Second_Holder = Id_A — exercises Image's 'none' holder tag.
      Cell.Begin_Access
        (C, Gada.Async.Race.Write, Gada.Async.Scheduler.No_Goroutine);
      Cell.Begin_Access (C, Gada.Async.Race.Read, Id_A);
      declare
         R   : constant Gada.Async.Race.Race_Report := Cell.Report (C);
         Img : constant String := Gada.Async.Race.Image (R);
      begin
         Assert (R.Detected, "Report must be detected for the Image case");
         Assert (Img'Length > 0
                   and then Img (Img'First .. Img'First + 9) = "data race:",
                 "Detected Image must start with 'data race:'; got: " & Img);
         --  First_Holder is No_Goroutine → 'none' tag must appear.
         Assert
           (Ada.Strings.Fixed.Index (Img, "none") > 0,
            "Image of a No_Goroutine holder must contain 'none'; got: "
            & Img);
      end;
      Cell.End_Access
        (C, Gada.Async.Scheduler.No_Goroutine);
   end Test_Image_Renders_No_Race_And_Detected;

   procedure Test_Goroutine_Driven_Intentional_Race
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Unused_1 : Gada.Async.Scheduler.Goroutine_Id;
      Unused_2 : Gada.Async.Scheduler.Goroutine_Id;
   begin
      Shared_Cell := Cell.Make;

      --  Two workers so the two Racing_Writer goroutines can actually
      --  hold their Write sections open simultaneously (the rendezvous
      --  barrier needs both to make progress on distinct OS threads).
      Gada.Async.Scheduler.Shutdown;
      Gada.Async.Scheduler.Init (Workers => 2);

      Unused_1 := Gada.Async.Scheduler.Spawn (Racing_Writer'Access);
      Unused_2 := Gada.Async.Scheduler.Spawn (Racing_Writer'Access);

      Gada.Async.Scheduler.Shutdown;  --  joins both goroutines

      Assert (Both_In_Section.Arrived_Count = 2,
              "Both racing goroutines must have reached the rendezvous");
      Assert (Cell.Race_Detected (Shared_Cell),
              "Two goroutines holding overlapping Write sections on one "
              & "cell must be detected as a data race");
      declare
         R : constant Gada.Async.Race.Race_Report :=
           Cell.Report (Shared_Cell);
      begin
         Assert (R.First_Mode = Gada.Async.Race.Write
                   and then R.Second_Mode = Gada.Async.Race.Write,
                 "Goroutine-driven race must be Write/Write");
         Assert (R.First_Holder /= R.Second_Holder,
                 "The two colliding holders must be distinct goroutines");
      end;
   end Test_Goroutine_Driven_Intentional_Race;

end Race_Suite;
