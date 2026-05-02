--  Defer_Suite body — see spec for test rationale.
--
--  Each test installs a defer that mutates a package-level counter
--  / sequence buffer, then asserts the post-condition after the
--  declaring block exits. Because `Defer_Block` is Limited_Controlled,
--  the compiler emits Finalize calls automatically at block exit —
--  no harness gymnastics needed.

with AUnit.Assertions; use AUnit.Assertions;

with System.Storage_Elements;

with Gada.Core.Defer;
with Gada.Core.Memory;

package body Defer_Suite is

   use type System.Storage_Elements.Storage_Count;

   --  Mutable state observed by deferred calls.
   --
   --  We use package-level globals rather than nested closures
   --  because the runtime spec (and the compiler-emit contract) is
   --  for library-level / nested-via-Access procedures, not for
   --  Ada-2022 lambdas. Each test resets the slots it touches.
   Counter   : Natural := 0;
   Sequence  : array (1 .. 8) of Natural := (others => 0);
   Sequence_Index : Natural := 0;

   ---------------------------------------------------------------
   --  Deferred operations
   ---------------------------------------------------------------

   procedure Bump_Counter is
   begin
      Counter := Counter + 1;
   end Bump_Counter;

   procedure Append_1 is
   begin
      Sequence_Index := Sequence_Index + 1;
      Sequence (Sequence_Index) := 1;
   end Append_1;

   procedure Append_2 is
   begin
      Sequence_Index := Sequence_Index + 1;
      Sequence (Sequence_Index) := 2;
   end Append_2;

   procedure Append_3 is
   begin
      Sequence_Index := Sequence_Index + 1;
      Sequence (Sequence_Index) := 3;
   end Append_3;

   ---------------------------------------------------------------
   --  AUnit boilerplate
   ---------------------------------------------------------------

   overriding function Name (T : Defer_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Core.Defer suite"));

   overriding procedure Register_Tests (T : in out Defer_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Single_Defer_Fires'Access,
         "Single Defer_Block fires at scope exit");
      Register_Routine
        (T, Test_Multiple_Defers_LIFO'Access,
         "Sibling Defer_Blocks fire in LIFO order");
      Register_Routine
        (T, Test_Defer_Fires_Under_Exception'Access,
         "Defer_Block fires when block exits via exception");
      Register_Routine
        (T, Test_Defer_Is_Zero_Alloc'Access,
         "Defer_Block declaration + finalisation does not allocate");
   end Register_Tests;

   ---------------------------------------------------------------
   --  Tests
   ---------------------------------------------------------------

   procedure Test_Single_Defer_Fires
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Counter := 0;
      declare
         D : Gada.Core.Defer.Defer_Block (Op => Bump_Counter'Access);
         pragma Unreferenced (D);
      begin
         Assert (Counter = 0,
                 "Counter should still be 0 inside the block");
      end;
      Assert (Counter = 1,
              "Counter should be 1 after the block exited");
   end Test_Single_Defer_Fires;

   procedure Test_Multiple_Defers_LIFO
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Sequence_Index := 0;
      Sequence := (others => 0);
      declare
         D1 : Gada.Core.Defer.Defer_Block (Op => Append_1'Access);
         D2 : Gada.Core.Defer.Defer_Block (Op => Append_2'Access);
         D3 : Gada.Core.Defer.Defer_Block (Op => Append_3'Access);
         pragma Unreferenced (D1, D2, D3);
      begin
         null;
      end;
      --  Ada finalises in reverse declaration order, so:
      --    Append_3 fires first → Sequence (1) = 3
      --    Append_2 fires next  → Sequence (2) = 2
      --    Append_1 fires last  → Sequence (3) = 1
      Assert (Sequence_Index = 3,
              "All three defers should have fired");
      Assert (Sequence (1) = 3,
              "First fire should be Append_3 (LIFO)");
      Assert (Sequence (2) = 2,
              "Second fire should be Append_2");
      Assert (Sequence (3) = 1,
              "Third fire should be Append_1 (LIFO bottom)");
   end Test_Multiple_Defers_LIFO;

   procedure Test_Defer_Fires_Under_Exception
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caught : Boolean := False;
   begin
      Counter := 0;
      begin
         declare
            D : Gada.Core.Defer.Defer_Block
              (Op => Bump_Counter'Access);
            pragma Unreferenced (D);
         begin
            raise Constraint_Error with "synthetic unwind";
         end;
      exception
         when Constraint_Error =>
            Caught := True;
      end;
      Assert (Caught,
              "Exception should propagate past the block");
      Assert (Counter = 1,
              "Defer should have fired during exception unwind");
   end Test_Defer_Fires_Under_Exception;

   procedure Test_Defer_Is_Zero_Alloc
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use System.Storage_Elements;
      Pre_Bytes  : Storage_Count;
      Post_Bytes : Storage_Count;
   begin
      Gada.Core.Memory.Initialize;
      Pre_Bytes := Gada.Core.Memory.Total_Bytes_Allocated;
      declare
         D : Gada.Core.Defer.Defer_Block (Op => Bump_Counter'Access);
         pragma Unreferenced (D);
      begin
         null;
      end;
      Post_Bytes := Gada.Core.Memory.Total_Bytes_Allocated;
      Assert (Post_Bytes = Pre_Bytes,
              "Defer_Block declaration + finalisation must be"
              & " zero-alloc — Total_Bytes_Allocated must not move");
   end Test_Defer_Is_Zero_Alloc;

end Defer_Suite;
