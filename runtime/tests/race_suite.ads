--  AUnit suite for Gada.Async.Race — the best-effort cooperative
--  race detector (Phase 3 "Race detector integration").
--
--  Each test pins one contract of the checked-cell model:
--    * an INTENTIONAL unsynchronised write/write overlap from two
--      goroutines is detected and reported (the verify gate);
--    * a read/write overlap is detected;
--    * correctly-synchronised (non-overlapping) access is NOT flagged;
--    * read/read overlap is benign;
--    * re-entrancy from the same goroutine is not a race;
--    * the cell's value round-trips through Load/Store;
--    * Image renders both the no-race and detected-race shapes,
--      including a non-goroutine (No_Goroutine) holder.
--
--  Determinism: every test drives the monitor through an explicit
--  Begin/End call sequence rather than relying on the OS scheduler to
--  interleave two threads at a hazardous instant. The detector's
--  verdict is a pure function of that call order (see the body of
--  Gada.Async.Race), so the suite is flake-free and runs under the
--  default `make test`.

with AUnit;
with AUnit.Test_Cases;

package Race_Suite is

   type Race_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Race_Test);
   overriding function  Name (T : Race_Test) return AUnit.Message_String;

   procedure Test_Intentional_Write_Write_Race_Detected
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Read_Write_Overlap_Detected
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Synchronized_Access_Not_Flagged
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Read_Read_Overlap_Is_Benign
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Reentrant_Same_Goroutine_Not_A_Race
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Load_Store_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_First_Race_Latched
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unbalanced_End_Access_Is_No_Op
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Image_Renders_No_Race_And_Detected
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Goroutine_Driven_Intentional_Race
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Race_Suite;
