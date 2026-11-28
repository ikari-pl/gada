--  Gada.Std.Encoding.Base64 — the Go `encoding/base64` package,
--  ported (Phase 8 wave 4, item 5). RFC 4648.
--
--  Go exposes four package-level encodings (StdEncoding, URLEncoding,
--  RawStdEncoding, RawURLEncoding) whose EncodeToString/DecodeString
--  methods are ported here as four function pairs. The std alphabet
--  uses '+' and '/', the URL-safe one '-' and '_'; Raw* omits the
--  '=' padding. Decode raises CONSTRAINT_ERROR on illegal characters
--  or malformed padding (Go's error half).

with Gada.Std.Bytes;

package Gada.Std.Encoding.Base64 is

   function Encode_Std (Data : Gada.Std.Bytes.Byte_Slice) return String;
   function Encode_URL (Data : Gada.Std.Bytes.Byte_Slice) return String;
   function Encode_Raw_Std (Data : Gada.Std.Bytes.Byte_Slice) return String;
   function Encode_Raw_URL (Data : Gada.Std.Bytes.Byte_Slice) return String;

   function Decode_Std (S : String) return Gada.Std.Bytes.Byte_Slice;
   function Decode_URL (S : String) return Gada.Std.Bytes.Byte_Slice;
   function Decode_Raw_Std (S : String) return Gada.Std.Bytes.Byte_Slice;
   function Decode_Raw_URL (S : String) return Gada.Std.Bytes.Byte_Slice;

end Gada.Std.Encoding.Base64;
