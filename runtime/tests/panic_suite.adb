--  Panic_Suite body — see spec for test rationale.

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Core.Defer;
with Gada.Core.Panic;

package body Panic_Suite is

   --  Single instantiation — Integer payload, Default = 0 — used
   --  across the suite. Compiler-emit will instantiate the
   --  generic once per transpiled program with that program's
   --  panic-value type.
   package Int_Panic is new Gada.Core.Panic
     (Payload_Type => Integer, Default => 0);

   ---------------------------------------------------------------
   --  Mutable state captured by deferred Recover-procedures.
   ---------------------------------------------------------------

   Recovered_Value : Integer := 0;

   procedure Capture_Recovered;
   --  Forward decl — `-gnatys` requires every body to follow a
   --  visible spec, even within a package body.

   procedure Capture_Recovered is
   begin
      Recovered_Value := Int_Panic.Recover;
   end Capture_Recovered;

   ---------------------------------------------------------------
   --  AUnit boilerplate
   ---------------------------------------------------------------

   overriding function Name
     (T : Panic_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Core.Panic suite"));

   overriding procedure Register_Tests (T : in out Panic_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Panic_And_Recover'Access,
         "Do_Panic + Recover round-trips the payload");
      Register_Routine
        (T, Test_Recover_When_Not_Panicking'Access,
         "Recover with no panic in flight returns Default");
      Register_Routine
        (T, Test_Nested_Panics_LIFO'Access,
         "Nested panics surface in LIFO order");
      Register_Routine
        (T, Test_Pending_Stack_Overflow'Access,
         "Pending-stack overflow raises Constraint_Error");
      Register_Routine
        (T, Test_Defer_Recovers_Panic'Access,
         "Defer_Block + Recover catches in-flight panic");
   end Register_Tests;

   ---------------------------------------------------------------
   --  Tests
   ---------------------------------------------------------------

   procedure Test_Panic_And_Recover
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Got    : Integer := -1;
      Caught : Boolean := False;
   begin
      begin
         Int_Panic.Do_Panic (123);
      exception
         when Int_Panic.Panicking =>
            Caught := True;
            Got := Int_Panic.Recover;
      end;
      Assert (Caught, "Panicking exception should be raised");
      Assert (Got = 123, "Recover should return the panic payload");
      Assert (not Int_Panic.Is_Panicking,
              "Panic state should be cleared after Recover");
   end Test_Panic_And_Recover;

   procedure Test_Recover_When_Not_Panicking
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Int_Panic.Recover = 0,
              "Recover with no panic in flight should return Default");
      Assert (not Int_Panic.Is_Panicking,
              "Is_Panicking should be False after a no-op Recover");
   end Test_Recover_When_Not_Panicking;

   procedure Test_Nested_Panics_LIFO
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Outer_Got : Integer := -1;
      Inner_Got : Integer := -1;
   begin
      begin
         Int_Panic.Do_Panic (10);  -- outer panic
      exception
         when Int_Panic.Panicking =>
            --  We are mid-unwind on the outer panic. Trigger an
            --  inner panic; recover it; then recover the outer.
            begin
               Int_Panic.Do_Panic (20);  -- inner panic
            exception
               when Int_Panic.Panicking =>
                  Inner_Got := Int_Panic.Recover;
            end;
            Outer_Got := Int_Panic.Recover;
      end;
      Assert (Inner_Got = 20,
              "Inner Recover should return inner payload (20)");
      Assert (Outer_Got = 10,
              "Outer Recover should return outer payload (10)");
      Assert (not Int_Panic.Is_Panicking,
              "All panics should be cleared after both Recovers");
   end Test_Nested_Panics_LIFO;

   procedure Test_Pending_Stack_Overflow
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Caught_Overflow : Boolean := False;

      --  Recursive helper that panics N times deep without
      --  recovering, to drive Pending_Count past the cap.
      --  Each frame pushes one panic and re-raises Panicking
      --  upward (because the inner Do_Panic raises Panicking,
      --  which we don't catch here — the recursive caller does).
      procedure Push_N (N : Natural);

      procedure Push_N (N : Natural) is
      begin
         if N = 0 then
            return;
         end if;
         begin
            Int_Panic.Do_Panic (N);
         exception
            when Int_Panic.Panicking =>
               Push_N (N - 1);
         end;
      end Push_N;

   begin
      --  Cap = 16; pushing 17 must hit the overflow guard.
      begin
         Push_N (17);
      exception
         when Constraint_Error =>
            Caught_Overflow := True;
      end;
      Assert (Caught_Overflow,
              "17th nested panic should raise Constraint_Error"
              & " (pending-stack capped at 16)");
      --  Drain the stack so subsequent tests start clean.
      while Int_Panic.Is_Panicking loop
         declare
            Discard : constant Integer := Int_Panic.Recover;
            pragma Unreferenced (Discard);
         begin
            null;
         end;
      end loop;
   end Test_Pending_Stack_Overflow;

   procedure Test_Defer_Recovers_Panic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  This is the end-to-end shape compiler-emit produces for
      --  Go's `defer func() { recover() }(); panic(...)` idiom.
      Recovered_Value := 0;
      begin
         declare
            D : Gada.Core.Defer.Defer_Block
              (Op => Capture_Recovered'Access);
            pragma Unreferenced (D);
         begin
            Int_Panic.Do_Panic (777);
         end;
         --  Defer_Block's Finalize ran during unwind and called
         --  Recover via Capture_Recovered, which captured 777
         --  and cleared the panic state. Ada's exception
         --  machinery still has the in-flight Panicking
         --  exception, though — see ADR-0006 / spec for why
         --  the wrapper-around-function pattern is needed at the
         --  compiler-emit layer to fully match Go's semantics.
      exception
         when Int_Panic.Panicking =>
            null;  -- compiler-emit's per-function catch-all
      end;
      Assert (Recovered_Value = 777,
              "Defer-installed Recover should have captured the"
              & " panic payload during unwind");
      Assert (not Int_Panic.Is_Panicking,
              "Panic state should be cleared by the deferred Recover");
   end Test_Defer_Recovers_Panic;

end Panic_Suite;
