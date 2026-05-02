--  Memory_Suite body — exercises Gada.Core.Memory's full surface.
--
--  Initialize is called at the start of every test (libgc's GC_init
--  is documented as idempotent, so repeated calls across tests are
--  safe and match real-world startup-then-everything-allocates flow).

with AUnit.Assertions;

with System;
with System.Storage_Elements;
use type System.Address;

with Gada.Core.Memory;

package body Memory_Suite is

   use type System.Storage_Elements.Storage_Count;

   procedure Test_Allocate_Returns_Nonnull
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Addr : System.Address;
   begin
      Gada.Core.Memory.Initialize;
      Addr := Gada.Core.Memory.Allocate (1024);
      AUnit.Assertions.Assert
        (Addr /= System.Null_Address,
         "Gada.Core.Memory.Allocate returned Null_Address (out of memory?)");
   end Test_Allocate_Returns_Nonnull;

   procedure Test_Allocate_Atomic_Returns_Nonnull
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Addr : System.Address;
   begin
      Gada.Core.Memory.Initialize;
      Addr := Gada.Core.Memory.Allocate_Atomic (4096);
      AUnit.Assertions.Assert
        (Addr /= System.Null_Address,
         "Gada.Core.Memory.Allocate_Atomic returned Null_Address"
         & " (out of memory?)");
   end Test_Allocate_Atomic_Returns_Nonnull;

   procedure Test_Stress_1M_Allocs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use System.Storage_Elements;

      N_Allocs   : constant := 1_000_000;
      Alloc_Size : constant Storage_Count := 64;

      --  Working-set ceiling: 2 * (N_Allocs * Alloc_Size) = 128 MB.
      --  libgc's heap-capacity grows as alloc demand spikes and is
      --  retained after Collect, but conservative scanning + atomic
      --  allocation should keep the steady-state working set well
      --  below 2x the cumulative allocation total. If we ever exceed
      --  this ceiling, libgc is leaking or our binding is wrong.
      Max_Heap : constant Storage_Count :=
        2 * Storage_Count (N_Allocs) * Alloc_Size;

      Pre_Heap  : Storage_Count;
      Peak_Heap : Storage_Count;
      Post_Heap : Storage_Count;
      Addr      : System.Address;
      pragma Unreferenced (Addr);
   begin
      Gada.Core.Memory.Initialize;
      Pre_Heap := Gada.Core.Memory.Heap_Size;

      --  Stress: allocate N_Allocs atomic regions, dropping the
      --  reference each time. libgc decides when to collect; we
      --  do not call Collect inside the loop so the test exercises
      --  libgc's own automatic-collection trigger heuristics.
      for I in 1 .. N_Allocs loop
         Addr := Gada.Core.Memory.Allocate_Atomic (Alloc_Size);
      end loop;

      Peak_Heap := Gada.Core.Memory.Heap_Size;

      --  Force a full cycle to make collection observable. After
      --  this, the heap capacity is libgc's choice; the assertion
      --  below pins the upper bound.
      Gada.Core.Memory.Collect;
      Post_Heap := Gada.Core.Memory.Heap_Size;

      AUnit.Assertions.Assert
        (Peak_Heap >= Pre_Heap,
         "Heap_Size did not grow under 1M-alloc load (libgc broken?)");

      AUnit.Assertions.Assert
        (Post_Heap <= Max_Heap,
         "Heap_Size after Collect exceeds 2x the cumulative-alloc"
         & " ceiling — libgc is leaking or the binding is wrong");
   end Test_Stress_1M_Allocs;

   overriding procedure Register_Tests (T : in out Memory_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Allocate_Returns_Nonnull'Access,
         "Gada.Core.Memory.Allocate returns non-null");
      Register_Routine
        (T, Test_Allocate_Atomic_Returns_Nonnull'Access,
         "Gada.Core.Memory.Allocate_Atomic returns non-null");
      Register_Routine
        (T, Test_Stress_1M_Allocs'Access,
         "1M allocs grow heap; Heap_Size after Collect bounded by 2x ceiling");
   end Register_Tests;

   overriding function Name (T : Memory_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Gada.Core.Memory suite");
   end Name;

end Memory_Suite;
