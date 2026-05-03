--  Gada.Core.Hash body — see spec for design notes.
--
--  SPARK_Mode is enabled at the body level too (the spec aspect
--  alone gates only the spec). Per docs/adr/0008-spark-policy.md
--  the entire compilation unit is in scope for `tools/prove.sh`.

with Ada.Unchecked_Conversion;

package body Gada.Core.Hash with SPARK_Mode => On is

   use Interfaces;

   function Hash_Integer (K : Integer) return Unsigned_64 is
   begin
      --  `Unsigned_64'Mod (K)` — the Ada 2022 modular-reduction
      --  attribute — wraps negative K into 2**64 - |K|. The plain
      --  `Unsigned_64 (K)` value-conversion would raise
      --  Constraint_Error for negative K (GNAT does NOT automatically
      --  modular-reduce on conversion from signed integer to a
      --  modular type, despite RM 4.6's general rule). gnatprove
      --  caught this on the first SPARK run; the prior plain-Ada
      --  test suite never passed a negative key.
      return Unsigned_64'Mod (K) * Fibonacci_Constant;
   end Hash_Integer;

   function Hash_Boolean (K : Boolean) return Unsigned_64 is
   begin
      return Unsigned_64 (Boolean'Pos (K)) * Fibonacci_Constant;
   end Hash_Boolean;

   function Hash_Long_Float (K : Long_Float) return Unsigned_64 is
      function To_U64 is new
        Ada.Unchecked_Conversion (Long_Float, Unsigned_64);
   begin
      return To_U64 (K) * Fibonacci_Constant;
   end Hash_Long_Float;

end Gada.Core.Hash;
