--  AUnit suite for `Gada.Core.Hash`.
--
--  Each public hash function gets a smoke test (basic round-trip),
--  a distribution sanity check (different inputs → different outputs
--  for the small sets the maps' Swiss-table groups care about), and
--  the constant-input invariant (same input → same output).

with AUnit;
with AUnit.Test_Cases;

package Hash_Suite is

   type Hash_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Hash_Test);
   overriding function  Name (T : Hash_Test) return AUnit.Message_String;

   procedure Test_Hash_Integer_Distinct
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Hash_Integer_Stable
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Hash_Boolean_Distinct
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Hash_Long_Float_Distinct
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Fibonacci_Constant_Exposed
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Hash_Suite;
