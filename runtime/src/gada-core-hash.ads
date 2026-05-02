--  Gada.Core.Hash — primitive hash functions consumed by
--  `Gada.Core.Maps` instantiations.
--
--  Phase 2 only needs the integer hash (the compiler-emit layer
--  instantiates `Maps_Of_Integer_To_Integer is new Gada.Core.Maps
--  (..., Hash => Gada.Core.Hash.Hash_Integer, ...)`); the rest land
--  as their key types come into scope.
--
--    - Hash_Integer       : Fibonacci (golden-ratio multiplicative).
--                           Distributes well, single multiply.
--    - Hash_Boolean       : Boolean'Pos with the Fibonacci constant
--                           applied so two-bucket hash tables don't
--                           degenerate to linear-probe-everything.
--    - Hash_Long_Float    : reinterprets the 64-bit IEEE 754 image
--                           via Unchecked_Conversion, then Fibonaccis.
--
--  String / pointer / aggregate hashes arrive in their own phases —
--  string keys need SipHash-1-3 (Phase 4), pointer keys need a
--  per-allocator-page-aware hash (Phase 5), etc.
--
--  No global state and no I/O; safe to instantiate from any task
--  context. Cannot be `pragma Pure` because the parent
--  `Gada.Core` is not Pure (`pure unit cannot depend on non-pure
--  unit`); the per-function Pure_Function aspect is unavailable on
--  imported subprograms but the bodies here are stateless and
--  treat the inputs as pure mathematical functions in practice.

with Interfaces;

package Gada.Core.Hash is

   --  Knuth's golden-ratio multiplicative constant (= 2^64 / phi).
   --  Public so user-defined hashes that want the same distribution
   --  can reuse it without redefining the magic number.
   Fibonacci_Constant : constant Interfaces.Unsigned_64 :=
     16#9E37_79B9_7F4A_7C15#;

   function Hash_Integer (K : Integer) return Interfaces.Unsigned_64;

   function Hash_Boolean (K : Boolean) return Interfaces.Unsigned_64;

   function Hash_Long_Float (K : Long_Float) return Interfaces.Unsigned_64;

end Gada.Core.Hash;
