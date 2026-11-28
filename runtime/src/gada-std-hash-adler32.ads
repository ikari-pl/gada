--  Gada.Std.Hash.Adler32 — the Go `hash/adler32` package, ported
--  (Phase 8). RFC 1950: s1 = 1 + sum(bytes) mod 65521,
--  s2 = sum of running s1 values mod 65521; result = s2*65536 + s1.
--
--  Go reduces mod 65521 at most every NMAX = 5552 bytes (the largest n
--  with 255n(n+1)/2 + (n+1)(65520) fitting in uint32); we do the same
--  batching so the arithmetic never overflows.

with Gada.Std.Bytes;
with Interfaces;

package Gada.Std.Hash.Adler32 is

   use Interfaces;

   --  Go: func Checksum(data []byte) uint32.
   function Checksum (Data : Gada.Std.Bytes.Byte_Slice) return Unsigned_32;

end Gada.Std.Hash.Adler32;
