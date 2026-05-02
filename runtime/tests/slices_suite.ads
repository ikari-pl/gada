--  AUnit test suite for `Gada.Core.Slices`.
--
--  Tests exercise the full public surface plus every branch of
--  Compute_Next_Capacity and Append (fast path / grow path /
--  empty-grow), targeting the runtime/ 100% coverage gate.
--
--  The suite instantiates the generic twice:
--    - Int_Slices  (Element_Type => Integer, Element_Is_Atomic => True)
--      — pointer-free element type, exercises the Allocate_Atomic
--        branch.
--    - Ptr_Slices  (Element_Type => Boxed_Int access, atomic = False)
--      — exercises the traced Allocate branch.
--  Both branches must compile and run for the gate to pass.

with AUnit;
with AUnit.Test_Cases;

package Slices_Suite is

   type Slices_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Slices_Test);
   overriding function  Name (T : Slices_Test) return AUnit.Message_String;

   procedure Test_Make_And_Inspect
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Make_With_Capacity
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Element_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Append_In_Place
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Append_Grow
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Append_From_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Slice_Of_Shares_Backing
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Slice_Of_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Empty_Constant
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Make_Zero
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Growth_Policy
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Traced_Allocator_Path
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Slices_Suite;
