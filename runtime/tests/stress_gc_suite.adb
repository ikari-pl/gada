--  Body of Stress_Gc_Suite — see spec for design notes.
--
--  Suppress GNAT 15's `-gnatw_a` warning on AUnit's `new …_Test`
--  registration pattern (file-scope), same trade-off as
--  `tests/test_runner.adb`.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with System;
with System.Storage_Elements;

with Gada.Core.Memory;

package body Stress_Gc_Suite is

   overriding function Name
     (T : Stress_Gc_Test) return AUnit.Message_String is
     (AUnit.Format ("GADA GC stress suite (PKG=stress.gc)"));

   overriding procedure Register_Tests (T : in out Stress_Gc_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Five_Million_Atomic_Allocs_Bounded_Heap'Access,
         "5M × 64-byte atomic allocs keep Heap_Size < 200 MB");
   end Register_Tests;

   procedure Test_Five_Million_Atomic_Allocs_Bounded_Heap
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use System.Storage_Elements;

      --  Five million × 64 bytes = 320 MB of cumulative atomic-alloc
      --  pressure. libgc with conservative collection should keep the
      --  retained heap well below 200 MB because every alloc is
      --  immediately dereferenced.
      N_Allocs      : constant := 5_000_000;
      Alloc_Size    : constant Storage_Count := 64;
      Collect_Every : constant := 100_000;

      --  RSS ceiling per the Phase 2 sub-item 10 contract. 200 MB =
      --  ~62.5% of the cumulative-allocation total — generous enough
      --  that variations in libgc's growth heuristic don't tip the
      --  test into a false-fail, tight enough that an actual leak
      --  (e.g. an Allocate that should be Allocate_Atomic) blows it
      --  immediately.
      Max_Heap : constant Storage_Count := 200 * 1024 * 1024;

      Addr : System.Address;
      pragma Unreferenced (Addr);
   begin
      Gada.Core.Memory.Initialize;

      for I in 1 .. N_Allocs loop
         Addr := Gada.Core.Memory.Allocate_Atomic (Alloc_Size);
         if I mod Collect_Every = 0 then
            Gada.Core.Memory.Collect;
            Assert
              (Gada.Core.Memory.Heap_Size <= Max_Heap,
               "Heap_Size exceeded 200 MB during stress run");
         end if;
      end loop;

      Gada.Core.Memory.Collect;
      Assert
        (Gada.Core.Memory.Heap_Size <= Max_Heap,
         "Final Heap_Size exceeded 200 MB after stress");
   end Test_Five_Million_Atomic_Allocs_Bounded_Heap;

end Stress_Gc_Suite;
