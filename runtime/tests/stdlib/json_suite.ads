--  AUnit suite for `Gada.Std.Json` (Go `encoding/json` scalar core,
--  Phase 7 wave 3 item 2a).
--
--  Covers: RFC 8259 string escape/unescape (short escapes, \u00xx
--  control chars, \uXXXX to UTF-8, bad escapes), the reflect-driven
--  Encode_Value over Gada.Reflect.Values, scalar Marshal/Unmarshal
--  round-trips for int / float / bool / string, null semantics, kind
--  mismatches, and malformed-input errors.

with AUnit;
with AUnit.Test_Cases;

package Json_Suite is

   type Json_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Json_Test);
   overriding function  Name (T : Json_Test) return AUnit.Message_String;

   procedure Test_Escape (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unescape (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Encode_Value (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Marshal_Scalars (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unmarshal_Scalars (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Unmarshal_Errors (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Float_Image (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Parse_Object (T : in out
      AUnit.Test_Cases.Test_Case'Class);

end Json_Suite;
