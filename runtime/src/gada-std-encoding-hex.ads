--  Gada.Std.Encoding.Hex — the Go `encoding/hex` package, ported
--  (Phase 8 wave 4, item 5). Lowercase hex, two chars per byte.
--
--  Go: hex.EncodeToString(data) / hex.DecodeString(s). Decode_String
--  raises CONSTRAINT_ERROR on an odd-length string or an illegal
--  character (Go's error half).

with Gada.Std.Bytes;

package Gada.Std.Encoding.Hex is

   function Encode_To_String (Data : Gada.Std.Bytes.Byte_Slice) return String;

   function Decode_String (S : String) return Gada.Std.Bytes.Byte_Slice;

   --  Go: hex.EncodedLen / DecodedLen.
   function Encoded_Len (N : Natural) return Natural;
   function Decoded_Len (N : Natural) return Natural;

end Gada.Std.Encoding.Hex;
