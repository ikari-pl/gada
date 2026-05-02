--  Body of Slices_Suite — see spec for test rationale.
--
--  Suppress GNAT 15's `-gnatw_a` warning on AUnit's `new …_Test`
--  registration pattern (file-scope), same trade-off as
--  `tests/test_runner.adb` (tracked in `docs/imperfections.md`).
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Core.Slices;

package body Slices_Suite is

   --  Instantiation 1 — Element_Is_Atomic => True. Exercises the
   --  Allocate_Atomic branch in Allocate_Backing.
   package Int_Slices is new Gada.Core.Slices
     (Element_Type      => Integer,
      Element_Is_Atomic => True);

   --  Instantiation 2 — Element_Is_Atomic => False. Exercises the
   --  traced Allocate branch.
   package Traced_Int_Slices is new Gada.Core.Slices
     (Element_Type      => Integer,
      Element_Is_Atomic => False);

   ---------------------------------------------------------------
   --  AUnit boilerplate
   ---------------------------------------------------------------

   overriding function Name
     (T : Slices_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Core.Slices suite"));

   overriding procedure Register_Tests (T : in out Slices_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Make_And_Inspect'Access,
         "Make_Slice (N) gives Length = Cap = N");
      Register_Routine
        (T, Test_Make_With_Capacity'Access,
         "Make_Slice (N, Cap) gives Length = N, Cap = Cap");
      Register_Routine
        (T, Test_Element_Roundtrip'Access,
         "Set_Element + Element round-trips through backing");
      Register_Routine
        (T, Test_Append_In_Place'Access,
         "Append uses spare capacity in place");
      Register_Routine
        (T, Test_Append_Grow'Access,
         "Append at capacity allocates fresh backing");
      Register_Routine
        (T, Test_Append_From_Empty'Access,
         "Append onto Empty allocates fresh backing");
      Register_Routine
        (T, Test_Slice_Of_Shares_Backing'Access,
         "Slice_Of returns a view sharing backing storage");
      Register_Routine
        (T, Test_Slice_Of_Empty'Access,
         "Slice_Of on Empty returns Empty");
      Register_Routine
        (T, Test_Empty_Constant'Access,
         "Empty constant has Length = Cap = 0");
      Register_Routine
        (T, Test_Make_Zero'Access,
         "Make_Slice (0) yields a zero-cap slice (no allocation)");
      Register_Routine
        (T, Test_Growth_Policy'Access,
         "Compute_Next_Capacity matches Go growslice policy");
      Register_Routine
        (T, Test_Traced_Allocator_Path'Access,
         "Element_Is_Atomic = False allocates via traced path");
      Register_Routine
        (T, Test_From_Array_Round_Trip'Access,
         "From_Array round-trips element values");
      Register_Routine
        (T, Test_From_Array_Empty'Access,
         "From_Array on empty array yields zero-cap slice");
      Register_Routine
        (T, Test_From_Array_Independent_Of_Source'Access,
         "From_Array does not retain caller's array by reference");
   end Register_Tests;

   ---------------------------------------------------------------
   --  Tests
   ---------------------------------------------------------------

   procedure Test_Make_And_Inspect
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : constant Int_Slices.Slice := Int_Slices.Make_Slice (5);
   begin
      Assert (Int_Slices.Len (S) = 5, "Length should be 5");
      Assert (Int_Slices.Cap (S) = 5, "Capacity should be 5");
   end Test_Make_And_Inspect;

   procedure Test_Make_With_Capacity
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : constant Int_Slices.Slice :=
        Int_Slices.Make_Slice (Length => 3, Capacity => 10);
   begin
      Assert (Int_Slices.Len (S) = 3, "Length should be 3");
      Assert (Int_Slices.Cap (S) = 10, "Capacity should be 10");
   end Test_Make_With_Capacity;

   procedure Test_Element_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : constant Int_Slices.Slice := Int_Slices.Make_Slice (4);
   begin
      Int_Slices.Set_Element (S, 1, 10);
      Int_Slices.Set_Element (S, 2, 20);
      Int_Slices.Set_Element (S, 3, 30);
      Int_Slices.Set_Element (S, 4, 40);
      Assert (Int_Slices.Element (S, 1) = 10, "S[1] should be 10");
      Assert (Int_Slices.Element (S, 2) = 20, "S[2] should be 20");
      Assert (Int_Slices.Element (S, 3) = 30, "S[3] should be 30");
      Assert (Int_Slices.Element (S, 4) = 40, "S[4] should be 40");
   end Test_Element_Roundtrip;

   procedure Test_Append_In_Place
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : Int_Slices.Slice :=
        Int_Slices.Make_Slice (Length => 0, Capacity => 4);
   begin
      S := Int_Slices.Append (S, 1);
      S := Int_Slices.Append (S, 2);
      S := Int_Slices.Append (S, 3);
      Assert (Int_Slices.Len (S) = 3, "Length should grow to 3");
      Assert (Int_Slices.Cap (S) = 4,
              "Capacity should remain 4 (in-place path)");
      Assert (Int_Slices.Element (S, 3) = 3,
              "Last element should be 3");
   end Test_Append_In_Place;

   procedure Test_Append_Grow
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : Int_Slices.Slice := Int_Slices.Make_Slice (4);
   begin
      Int_Slices.Set_Element (S, 1, 100);
      Int_Slices.Set_Element (S, 2, 200);
      Int_Slices.Set_Element (S, 3, 300);
      Int_Slices.Set_Element (S, 4, 400);
      --  Cap = 4, Len = 4 → next Append must grow.
      S := Int_Slices.Append (S, 500);
      Assert (Int_Slices.Len (S) = 5, "Length should be 5");
      Assert (Int_Slices.Cap (S) >= 5,
              "Capacity should grow to >= 5");
      --  Old elements survived the memmove?
      Assert (Int_Slices.Element (S, 1) = 100,
              "Element 1 should survive grow");
      Assert (Int_Slices.Element (S, 4) = 400,
              "Element 4 should survive grow");
      Assert (Int_Slices.Element (S, 5) = 500,
              "New element should be appended");
   end Test_Append_Grow;

   procedure Test_Append_From_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : Int_Slices.Slice := Int_Slices.Empty;
   begin
      S := Int_Slices.Append (S, 42);
      Assert (Int_Slices.Len (S) = 1, "Length should be 1");
      Assert (Int_Slices.Cap (S) >= 1, "Capacity should be >= 1");
      Assert (Int_Slices.Element (S, 1) = 42,
              "Element should be 42");
   end Test_Append_From_Empty;

   procedure Test_Slice_Of_Shares_Backing
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : constant Int_Slices.Slice := Int_Slices.Make_Slice (5);
      V : Int_Slices.Slice;
   begin
      Int_Slices.Set_Element (S, 1, 10);
      Int_Slices.Set_Element (S, 2, 20);
      Int_Slices.Set_Element (S, 3, 30);
      Int_Slices.Set_Element (S, 4, 40);
      Int_Slices.Set_Element (S, 5, 50);
      --  s[2:5] in Go terms; 1-based here = (2, 5) → indices 2..4.
      V := Int_Slices.Slice_Of (S, Low => 2, High => 5);
      Assert (Int_Slices.Len (V) = 3,
              "Slice_Of (2, 5) should have length 3");
      Assert (Int_Slices.Cap (V) = 4,
              "Slice_Of preserves tail capacity (5 - 1 = 4)");
      Assert (Int_Slices.Element (V, 1) = 20,
              "V[1] should be S[2] = 20");
      Assert (Int_Slices.Element (V, 2) = 30,
              "V[2] should be S[3] = 30");
      Assert (Int_Slices.Element (V, 3) = 40,
              "V[3] should be S[4] = 40");
      --  Sharing: write through view, read through original.
      Int_Slices.Set_Element (V, 1, 999);
      Assert (Int_Slices.Element (S, 2) = 999,
              "Mutation through view should be visible via S");
   end Test_Slice_Of_Shares_Backing;

   procedure Test_Slice_Of_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      E : constant Int_Slices.Slice :=
        Int_Slices.Slice_Of (Int_Slices.Empty, Low => 1, High => 1);
   begin
      Assert (Int_Slices.Len (E) = 0,
              "Slice_Of (Empty, 1, 1) should be empty");
      Assert (Int_Slices.Cap (E) = 0,
              "Slice_Of (Empty, 1, 1) should have zero cap");
   end Test_Slice_Of_Empty;

   procedure Test_Empty_Constant
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Int_Slices.Len (Int_Slices.Empty) = 0,
              "Empty.Length should be 0");
      Assert (Int_Slices.Cap (Int_Slices.Empty) = 0,
              "Empty.Capacity should be 0");
   end Test_Empty_Constant;

   procedure Test_Make_Zero
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Exercises the Capacity = 0 short-circuit in Allocate_Backing
      --  — important so the runtime/ 100% coverage gate covers all
      --  three branches of the allocator helper.
      S : constant Int_Slices.Slice := Int_Slices.Make_Slice (0);
   begin
      Assert (Int_Slices.Len (S) = 0, "Length should be 0");
      Assert (Int_Slices.Cap (S) = 0, "Capacity should be 0");
   end Test_Make_Zero;

   procedure Test_Growth_Policy
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Min_Cap = 0 short-circuit.
      Assert (Int_Slices.Compute_Next_Capacity (0, 0) = 0,
              "(0, 0) → 0");
      --  Old_Cap = 0, jump to Min_Cap.
      Assert (Int_Slices.Compute_Next_Capacity (0, 5) = 5,
              "(0, 5) → 5");
      --  Doubling: 4 * 2 = 8.
      Assert (Int_Slices.Compute_Next_Capacity (4, 5) = 8,
              "(4, 5) → 8 (doubling phase)");
      --  Doubling-still-too-small bounce: 1 * 2 = 2 < Min_Cap=10.
      Assert (Int_Slices.Compute_Next_Capacity (1, 10) = 10,
              "(1, 10) → 10 (doubling bounce)");
      --  1.25x phase. (300, 350): 300 + (300+768)/4 = 300+267 = 567.
      Assert (Int_Slices.Compute_Next_Capacity (300, 350) = 567,
              "(300, 350) → 567 (1.25x phase smoothed)");
      --  1.25x phase iterating: (300, 2000) needs multiple steps.
      Assert (Int_Slices.Compute_Next_Capacity (300, 2000) >= 2000,
              "(300, 2000) >= 2000");
   end Test_Growth_Policy;

   procedure Test_Traced_Allocator_Path
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : Traced_Int_Slices.Slice :=
        Traced_Int_Slices.Make_Slice (Length => 0, Capacity => 2);
   begin
      --  Goal of this test: exercise the `not Element_Is_Atomic`
      --  branch in Allocate_Backing so coverage is 100%. Functional
      --  correctness is the same as the atomic instantiation.
      S := Traced_Int_Slices.Append (S, 11);
      S := Traced_Int_Slices.Append (S, 22);
      S := Traced_Int_Slices.Append (S, 33);  -- triggers grow
      Assert (Traced_Int_Slices.Len (S) = 3,
              "Length should be 3");
      Assert (Traced_Int_Slices.Element (S, 1) = 11,
              "S[1] should be 11");
      Assert (Traced_Int_Slices.Element (S, 3) = 33,
              "S[3] should be 33");
   end Test_Traced_Allocator_Path;

   procedure Test_From_Array_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Items : constant Int_Slices.Element_Array := [10, 20, 30, 40];
      S     : constant Int_Slices.Slice := Int_Slices.From_Array (Items);
   begin
      Assert (Int_Slices.Len (S) = 4, "Length should be 4");
      Assert (Int_Slices.Cap (S) = 4, "Capacity should be 4");
      Assert (Int_Slices.Element (S, 1) = 10, "S[1] should be 10");
      Assert (Int_Slices.Element (S, 2) = 20, "S[2] should be 20");
      Assert (Int_Slices.Element (S, 3) = 30, "S[3] should be 30");
      Assert (Int_Slices.Element (S, 4) = 40, "S[4] should be 40");
   end Test_From_Array_Round_Trip;

   procedure Test_From_Array_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Items : constant Int_Slices.Element_Array (1 .. 0) := [others => 0];
      S     : constant Int_Slices.Slice := Int_Slices.From_Array (Items);
   begin
      Assert (Int_Slices.Len (S) = 0, "Empty From_Array → Length 0");
      Assert (Int_Slices.Cap (S) = 0, "Empty From_Array → Cap 0");
   end Test_From_Array_Empty;

   procedure Test_From_Array_Independent_Of_Source
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Items : Int_Slices.Element_Array := [1, 2, 3];
      S     : constant Int_Slices.Slice := Int_Slices.From_Array (Items);
   begin
      --  Mutate the caller's array; the slice must keep its own copy.
      Items (1) := 99;
      Items (2) := 99;
      Items (3) := 99;
      Assert (Int_Slices.Element (S, 1) = 1,
              "S[1] should retain the original value, not follow Items");
      Assert (Int_Slices.Element (S, 3) = 3,
              "S[3] should retain the original value, not follow Items");
   end Test_From_Array_Independent_Of_Source;

end Slices_Suite;
