--  AUnit test suite for `Gada.Core.Memory`.
--
--  Three tests:
--    1. Allocate returns a non-null address.
--    2. Allocate_Atomic returns a non-null address.
--    3. Stress: 1M allocations of 64 bytes each, then force Collect;
--       Heap_Size at the end is bounded (libgc retains capacity but
--       does not blow past the working-set ceiling).
--
--  Test #3 satisfies the parent roadmap item's Done-when clause
--  ("1M allocs, RSS bounded") and exercises Initialize, Allocate,
--  Allocate_Atomic, Collect, and Heap_Size — every public subprogram
--  the runtime/ 100% coverage gate measures.

with AUnit;
with AUnit.Test_Cases;

package Memory_Suite is

   type Memory_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Memory_Test);
   overriding function  Name (T : Memory_Test) return AUnit.Message_String;

   procedure Test_Allocate_Returns_Nonnull
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Allocate_Atomic_Returns_Nonnull
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Stress_1M_Allocs
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Total_Bytes_Allocated_Monotonic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Memory_Suite;
