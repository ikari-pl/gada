--  Reflect_Interfaces_Suite body — see spec.
--
--  The registry is process-wide, so each test uses high, otherwise-unused
--  Type_Ids (9201+) to stay independent of registration order and of the
--  sibling reflect suites.

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Reflect.Types;      use Gada.Reflect.Types;
with Gada.Reflect.Interfaces; use Gada.Reflect.Interfaces;

package body Reflect_Interfaces_Suite is

   procedure Test_Register_Then_Satisfies
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Register (Concrete => 9201, Iface => 9202);
      Assert (Satisfies (9201, 9202),
              "a registered (concrete, interface) pair satisfies");
   end Test_Register_Then_Satisfies;

   procedure Test_Unregistered_And_Asymmetric
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Never registered: Go's `_, ok := x.(I)` failing.
      Assert (not Satisfies (9210, 9211),
              "an unregistered pair does not satisfy");
      --  Order matters: C satisfies I does not make I satisfy C.
      Register (Concrete => 9212, Iface => 9213);
      Assert (Satisfies (9212, 9213), "the registered direction holds");
      Assert (not Satisfies (9213, 9212),
              "satisfaction is directional — the reverse pair is distinct");
   end Test_Unregistered_And_Asymmetric;

   procedure Test_Duplicate_Register_Idempotent
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Register (Concrete => 9220, Iface => 9221);
      Register (Concrete => 9220, Iface => 9221);
      Assert (Satisfies (9220, 9221),
              "registering the same pair twice is a no-op, still satisfies");
   end Test_Duplicate_Register_Idempotent;

   procedure Test_Register_No_Type_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Expect_Constraint_Error
        (Probe : not null access procedure; Label : String);
      procedure Expect_Constraint_Error
        (Probe : not null access procedure; Label : String)
      is
         Raised : Boolean := False;
      begin
         begin
            Probe.all;
         exception
            when Constraint_Error =>
               Raised := True;
         end;
         Assert (Raised, Label);
      end Expect_Constraint_Error;

      --  Both operands are guarded (the `or else`), so probe each side.
      procedure No_Concrete;
      procedure No_Concrete is
      begin
         Register (Concrete => No_Type, Iface => 9230);
      end No_Concrete;

      procedure No_Iface;
      procedure No_Iface is
      begin
         Register (Concrete => 9231, Iface => No_Type);
      end No_Iface;
   begin
      Expect_Constraint_Error
        (No_Concrete'Access, "a No_Type concrete is rejected");
      Expect_Constraint_Error
        (No_Iface'Access, "a No_Type interface is rejected");
   end Test_Register_No_Type_Raises;

   overriding procedure Register_Tests
     (T : in out Reflect_Interfaces_Test)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Register_Then_Satisfies'Access,
         "Register then Satisfies round-trips a satisfaction pair");
      Register_Routine
        (T, Test_Unregistered_And_Asymmetric'Access,
         "An unregistered pair does not satisfy, and satisfaction is "
         & "directional (reverse pair is distinct)");
      Register_Routine
        (T, Test_Duplicate_Register_Idempotent'Access,
         "Registering the same pair twice is idempotent");
      Register_Routine
        (T, Test_Register_No_Type_Raises'Access,
         "A No_Type operand on either side raises Constraint_Error");
   end Register_Tests;

   overriding function Name
     (T : Reflect_Interfaces_Test) return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Gada.Reflect.Interfaces suite");
   end Name;

end Reflect_Interfaces_Suite;
