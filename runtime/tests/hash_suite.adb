--  Body of Hash_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Interfaces; use Interfaces;

with Gada.Core.Hash;

package body Hash_Suite is

   overriding function Name
     (T : Hash_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Core.Hash suite"));

   overriding procedure Register_Tests (T : in out Hash_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Hash_Integer_Distinct'Access,
         "Hash_Integer maps distinct ints to distinct hashes");
      Register_Routine
        (T, Test_Hash_Integer_Stable'Access,
         "Hash_Integer is deterministic");
      Register_Routine
        (T, Test_Hash_Boolean_Distinct'Access,
         "Hash_Boolean (False) /= Hash_Boolean (True)");
      Register_Routine
        (T, Test_Hash_Long_Float_Distinct'Access,
         "Hash_Long_Float distinguishes 1.0 from 2.0");
      Register_Routine
        (T, Test_Fibonacci_Constant_Exposed'Access,
         "Fibonacci_Constant matches Knuth's golden-ratio multiplier");
   end Register_Tests;

   procedure Test_Hash_Integer_Distinct
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      H1 : constant Unsigned_64 := Gada.Core.Hash.Hash_Integer (1);
      H2 : constant Unsigned_64 := Gada.Core.Hash.Hash_Integer (2);
      H3 : constant Unsigned_64 := Gada.Core.Hash.Hash_Integer (1_000_000);
   begin
      Assert (H1 /= H2, "Hash_Integer (1) should differ from Hash_Integer (2)");
      Assert (H1 /= H3,
              "Hash_Integer (1) should differ from Hash_Integer (1_000_000)");
      Assert (H2 /= H3,
              "Hash_Integer (2) should differ from Hash_Integer (1_000_000)");
   end Test_Hash_Integer_Distinct;

   procedure Test_Hash_Integer_Stable
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Gada.Core.Hash.Hash_Integer (42)
              = Gada.Core.Hash.Hash_Integer (42),
              "Hash_Integer must be deterministic");
   end Test_Hash_Integer_Stable;

   procedure Test_Hash_Boolean_Distinct
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Gada.Core.Hash.Hash_Boolean (False)
              /= Gada.Core.Hash.Hash_Boolean (True),
              "Hash_Boolean must split False from True");
      Assert (Gada.Core.Hash.Hash_Boolean (False) = 0,
              "Hash_Boolean (False) is 0 * Fibonacci_Constant = 0");
      Assert (Gada.Core.Hash.Hash_Boolean (True)
              = Gada.Core.Hash.Fibonacci_Constant,
              "Hash_Boolean (True) is 1 * Fibonacci_Constant");
   end Test_Hash_Boolean_Distinct;

   procedure Test_Hash_Long_Float_Distinct
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      H1 : constant Unsigned_64 := Gada.Core.Hash.Hash_Long_Float (1.0);
      H2 : constant Unsigned_64 := Gada.Core.Hash.Hash_Long_Float (2.0);
   begin
      Assert (H1 /= H2,
              "Hash_Long_Float (1.0) should differ from Hash_Long_Float (2.0)");
   end Test_Hash_Long_Float_Distinct;

   procedure Test_Fibonacci_Constant_Exposed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Gada.Core.Hash.Fibonacci_Constant = 16#9E37_79B9_7F4A_7C15#,
         "Fibonacci_Constant must equal 2^64 / phi (Knuth)");
   end Test_Fibonacci_Constant_Exposed;

end Hash_Suite;
