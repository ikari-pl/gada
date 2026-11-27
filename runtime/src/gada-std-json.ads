--  Gada.Std.Json — GADA's port of Go's `encoding/json` (Phase 7 wave 3,
--  item 2a: the scalar core).
--
--  Two layers:
--
--    * Text primitives — Escape / Unescape implement the RFC 8259
--      string escapes (short forms plus \u00XX for other control
--      chars; \uXXXX decodes to UTF-8, BMP only in v1).
--
--    * Value encoding — Encode_Value renders a Gada.Reflect.Values.Value
--      as JSON text, switching on the value's Kind (which Value_Of fixes
--      from the datum's Ada type): Bool / Int / Float / String encode,
--      anything else renders as null (Go marshals a nil pointer /
--      interface as null; composite *data* walking lands with item 2b).
--
--  The Go-facing surface mirrors the two-value out-call shape used by
--  net.Dial: `data, err := json.Marshal(x)` and
--  `err := json.Unmarshal(data, &v)`. The scalar overloads let the Ada
--  compiler select by the operand's static type, so the emitter needs
--  no type-id plumbing for the common case; the Value overloads are
--  the reflect-driven path.

with Ada.Strings.Unbounded;
with Gada.Reflect.Types;
with Gada.Reflect.Values;
with Gada.Std.Bytes;
with Gada.Std.Errors;

package Gada.Std.Json is

   ---------------------------------------------------------------
   --  String primitives
   ---------------------------------------------------------------

   --  Escape renders S as the *contents* of a JSON string literal
   --  (no surrounding quotes): '"' -> \", '\' -> \\, the short escapes
   --  \b \f \n \r \t, other control chars < 0x20 as \u00xx, everything
   --  else (including UTF-8 bytes >= 0x20) passes through unchanged.
   function Escape (S : String) return String;

   --  Unescape decodes the contents of a JSON string literal (no
   --  surrounding quotes). \uXXXX yields the UTF-8 encoding of the
   --  code point (BMP only; surrogate halves are rejected in v1).
   --  OK = False on a bad escape or a truncated \uXXXX.
   function Unescape (S : String; OK : out Boolean) return String;

   ---------------------------------------------------------------
   --  Reflect-driven value encoding
   ---------------------------------------------------------------

   --  Encode_Value renders a boxed scalar as JSON text. The kind comes
   --  from the Value's own tag (Value_Of sets it from the datum type);
   --  non-scalar kinds encode as null.
   function Encode_Value (V : Gada.Reflect.Values.Value)
                          return Ada.Strings.Unbounded.Unbounded_String;

   ---------------------------------------------------------------
   --  Marshal / Unmarshal (two-value out-call shape)
   ---------------------------------------------------------------

   procedure Marshal (X : Integer;
                      Data : out Gada.Std.Bytes.Byte_Slice;
                      Err  : out Gada.Std.Errors.Error_Access);
   procedure Marshal (X : Long_Float;
                      Data : out Gada.Std.Bytes.Byte_Slice;
                      Err  : out Gada.Std.Errors.Error_Access);
   procedure Marshal (X : Boolean;
                      Data : out Gada.Std.Bytes.Byte_Slice;
                      Err  : out Gada.Std.Errors.Error_Access);
   procedure Marshal (X : String;
                      Data : out Gada.Std.Bytes.Byte_Slice;
                      Err  : out Gada.Std.Errors.Error_Access);
   --  The reflect-driven path: encode a boxed Value.
   procedure Marshal (V : Gada.Reflect.Values.Value;
                      Data : out Gada.Std.Bytes.Byte_Slice;
                      Err  : out Gada.Std.Errors.Error_Access);

   --  Unmarshal parses Data as a single JSON scalar (surrounding
   --  whitespace allowed) into V. null leaves V unchanged with no
   --  error, matching Go; a kind mismatch is an error, as in Go.
   procedure Unmarshal (Data : Gada.Std.Bytes.Byte_Slice;
                        V    : in out Integer;
                        Err  : out Gada.Std.Errors.Error_Access);
   procedure Unmarshal (Data : Gada.Std.Bytes.Byte_Slice;
                        V    : in out Long_Float;
                        Err  : out Gada.Std.Errors.Error_Access);
   procedure Unmarshal (Data : Gada.Std.Bytes.Byte_Slice;
                        V    : in out Boolean;
                        Err  : out Gada.Std.Errors.Error_Access);
   procedure Unmarshal (Data : Gada.Std.Bytes.Byte_Slice;
                        V    : in out Ada.Strings.Unbounded.Unbounded_String;
                        Err  : out Gada.Std.Errors.Error_Access);

end Gada.Std.Json;
