--  Gada.Core.Hash body — see spec for design notes.

with Ada.Unchecked_Conversion;

package body Gada.Core.Hash is

   use Interfaces;

   function Hash_Integer (K : Integer) return Unsigned_64 is
   begin
      return Unsigned_64 (K) * Fibonacci_Constant;
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
