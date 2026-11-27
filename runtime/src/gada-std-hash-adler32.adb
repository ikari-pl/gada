--  Gada.Std.Hash.Adler32 body — see spec.

with Gada.Std.Bytes; use Gada.Std.Bytes;

package body Gada.Std.Hash.Adler32 is

   Modulus : constant Unsigned_32 := 65521;
   --  Largest n such that 255*n*(n+1)/2 + (n+1)*(Modulus-1) <= 2^32-1
   --  (RFC 1950's NMAX).
   NMAX : constant Natural := 5552;

   function Checksum (Data : Byte_Slice) return Unsigned_32 is
      S1 : Unsigned_32 := 1;
      S2 : Unsigned_32 := 0;
      Remaining : Natural := Natural (Byte_Vectors.Length (Data));
      Pos : Positive := 1;
   begin
      while Remaining > 0 loop
         declare
            N : constant Natural :=
              (if Remaining > NMAX then NMAX else Remaining);
         begin
            for K in 0 .. N - 1 loop
               S1 := S1 + Unsigned_32 (Byte_Vectors.Element (Data, Pos + K));
               S2 := S2 + S1;
            end loop;
            S1 := S1 mod Modulus;
            S2 := S2 mod Modulus;
            Pos := Pos + N;
            Remaining := Remaining - N;
         end;
      end loop;
      return S2 * 65536 + S1;
   end Checksum;

end Gada.Std.Hash.Adler32;
