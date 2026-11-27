--  Body of Json_Suite — see spec for test rationale.

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Gada.Reflect.Registry;
with Gada.Reflect.Types;
with Gada.Reflect.Values;
with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Errors;
with Gada.Std.Json; use Gada.Std.Json;

package body Json_Suite is

   package Errors renames Gada.Std.Errors;
   package Types renames Gada.Reflect.Types;
   package Values renames Gada.Reflect.Values;

   use type Errors.Error_Access;

   --  Type ids for the reflect-driven tests. The harness registers
   --  nothing under these ids, so they are free; high values keep
   --  clear of any per-program compiler-assigned range.
   Int_Id    : constant Types.Type_Id := 9001;
   Float_Id  : constant Types.Type_Id := 9002;
   Bool_Id   : constant Types.Type_Id := 9003;
   String_Id : constant Types.Type_Id := 9004;

   function Err_Text (Err : Errors.Error_Access) return String is
     (if Err = Errors.No_Error then "<nil>" else Err.all.Message);

   overriding procedure Register_Tests (T : in out Json_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Escape'Access, "Escape");
      Register_Routine (T, Test_Unescape'Access, "Unescape");
      Register_Routine (T, Test_Encode_Value'Access, "Encode_Value");
      Register_Routine (T, Test_Marshal_Scalars'Access,
                        "Marshal scalars");
      Register_Routine (T, Test_Unmarshal_Scalars'Access,
                        "Unmarshal scalars");
      Register_Routine (T, Test_Unmarshal_Errors'Access,
                        "Unmarshal errors");
      Register_Routine (T, Test_Float_Image'Access, "Float image");
      Register_Routine (T, Test_Parse_Object'Access, "Parse_Object");
   end Register_Tests;

   overriding function Name (T : Json_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Json suite (PKG=stdlib.encoding.json)"));

   procedure Test_Escape (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Check (In_S, Want : String) is
      begin
         Assert (Escape (In_S) = Want,
                 "escape '" & In_S & "' = '" & Escape (In_S)
                 & "' want '" & Want & "'");
      end Check;
   begin
      Check ("plain", "plain");
      Check ("say ""hi""", "say " & '\' & '"' & "hi" & '\' & '"');
      Check ("back\slash", "back" & '\' & '\' & "slash");
      Check ("tab" & Character'Val (9) & "here",
             "tab\there");
      Check ("nl" & Character'Val (10) & "cr" & Character'Val (13),
             "nl\ncr\r");
      Check ("bell" & Character'Val (8) & "form" & Character'Val (12),
             "bell\bform\f");
      Check ("ctl" & Character'Val (1) & "x", "ctl\u0001x");
      Check ("del" & Character'Val (31), "del\u001f");
      --  UTF-8 bytes >= 0x20 pass through unchanged.
      Check (Character'Val (16#C3#) & Character'Val (16#A9#),
             Character'Val (16#C3#) & Character'Val (16#A9#));
   end Test_Escape;

   procedure Test_Unescape (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Check (In_S, Want : String) is
         OK : Boolean;
         R  : constant String := Unescape (In_S, OK);
      begin
         Assert (OK, "unescape should accept '" & In_S & "'");
         Assert (R = Want, "unescape '" & In_S & "' = '" & R
                 & "' want '" & Want & "'");
      end Check;
      procedure Check_Bad (In_S : String) is
         OK : Boolean;
         R  : constant String := Unescape (In_S, OK);
      begin
         pragma Unreferenced (R);
         Assert (not OK, "unescape should reject '" & In_S & "'");
      end Check_Bad;
   begin
      Check ("plain", "plain");
      Check ("say \""hi\""", "say ""hi""");
      Check ("back\\slash", "back\slash");
      Check ("nl\ncr\rbt\ttbf\ff", "nl" & Character'Val (10)
              & "cr" & Character'Val (13) & "bt" & Character'Val (9)
              & "tbf" & Character'Val (12) & "f");
      Check ("\u0041", "A");       --  A
      Check ("Euro" & "\u20ac" & "x", "Euro" & Character'Val (16#E2#)
              & Character'Val (16#82#) & Character'Val (16#AC#) & "x");
      Check ("\u00e9", Character'Val (16#C3#) & Character'Val (16#A9#));
      Check ("\u07ff", Character'Val (16#DF#) & Character'Val (16#BF#));
      Check ("a\/b", "a/b");
      Check ("a\bb", "a" & Character'Val (8) & "b");
      Check ("ctl\u0001", "ctl" & Character'Val (1));
      Check_Bad ("bad\xescape");
      Check_Bad ("trunc\u12");
      Check_Bad ("nonhex\uZZZZ");
      Check_Bad ("surrogate\uD800");
      Check_Bad ("trailing\");
   end Test_Unescape;

   procedure Test_Encode_Value (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Register scalar descriptors so the ids are real registry
      --  citizens (Encode_Value itself switches on the Value's kind
      --  tag, which Value_Of fixes from the datum's Ada type).
      Gada.Reflect.Registry.Register_Type
        (Types.Make (Id => Int_Id, Name => "int",
                     Kind => Types.Int_Kind));
      Gada.Reflect.Registry.Register_Type
        (Types.Make (Id => Float_Id, Name => "float64",
                     Kind => Types.Float_Kind));
      Gada.Reflect.Registry.Register_Type
        (Types.Make (Id => Bool_Id, Name => "bool",
                     Kind => Types.Bool_Kind));
      Gada.Reflect.Registry.Register_Type
        (Types.Make (Id => String_Id, Name => "string",
                     Kind => Types.String_Kind));

      Assert (To_String (Encode_Value (Values.Value_Of (Int_Id, 42)))
              = "42", "int encode");
      Assert (To_String (Encode_Value (Values.Value_Of (Int_Id, -7)))
              = "-7", "negative int encode");
      Assert (To_String (Encode_Value (Values.Value_Of (Float_Id, 1.5)))
              = "1.5", "float encode");
      Assert (To_String (Encode_Value (Values.Value_Of (Bool_Id, True)))
              = "true", "bool encode");
      Assert (To_String (Encode_Value (Values.Value_Of (Bool_Id, False)))
              = "false", "bool encode false");
      Assert (To_String (Encode_Value
                (Values.Value_Of (String_Id, "a""b")))
              = """a\""b""", "string encode");
      --  Composite / invalid kinds encode as null.
      Assert (To_String (Encode_Value (Values.Value_Of (Types.Type_Id (0))))
              = "null", "invalid kind encodes as null");
   end Test_Encode_Value;

   procedure Test_Marshal_Scalars (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data : Byte_Slice;
      Err  : Errors.Error_Access;
   begin
      Marshal (42, Data, Err);
      Assert (Err = Errors.No_Error and then To_String (Data) = "42",
              "marshal 42: " & Err_Text (Err));
      Marshal (-7, Data, Err);
      Assert (To_String (Data) = "-7", "marshal -7");
      Marshal (True, Data, Err);
      Assert (To_String (Data) = "true", "marshal true");
      Marshal (False, Data, Err);
      Assert (To_String (Data) = "false", "marshal false");
      Marshal ("hi" & Character'Val (10), Data, Err);
      Assert (To_String (Data) = """hi\n""", "marshal string");
      Marshal (1.5, Data, Err);
      Assert (To_String (Data) = "1.5", "marshal 1.5");
      Marshal (2.0, Data, Err);
      Assert (To_String (Data) = "2", "marshal 2.0 -> 2");
      --  Reflect-driven path.
      Marshal (Values.Value_Of (Int_Id, 9), Data, Err);
      Assert (Err = Errors.No_Error and then To_String (Data) = "9",
              "marshal value: " & Err_Text (Err));
   end Test_Marshal_Scalars;

   procedure Test_Unmarshal_Scalars
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Err : Errors.Error_Access;
      I   : Integer := -1;
      F   : Long_Float := -1.0;
      B   : Boolean := False;
      S   : Unbounded_String := To_Unbounded_String ("x");
   begin
      Unmarshal (To_Bytes ("42"), I, Err);
      Assert (Err = Errors.No_Error and then I = 42,
              "unmarshal 42: " & Err_Text (Err));
      Unmarshal (To_Bytes ("  -13  "), I, Err);
      Assert (Err = Errors.No_Error and then I = -13,
              "unmarshal padded -13: " & Err_Text (Err));
      Unmarshal (To_Bytes ("4.5"), F, Err);
      Assert (Err = Errors.No_Error and then F = 4.5,
              "unmarshal 4.5: " & Err_Text (Err));
      --  An integer token unmarshals into a float (Go allows this).
      Unmarshal (To_Bytes ("7"), F, Err);
      Assert (Err = Errors.No_Error and then F = 7.0,
              "unmarshal int into float: " & Err_Text (Err));
      Unmarshal (To_Bytes ("true"), B, Err);
      Assert (Err = Errors.No_Error and then B, "unmarshal true");
      Unmarshal (To_Bytes ("false"), B, Err);
      Assert (Err = Errors.No_Error and then not B, "unmarshal false");
      Unmarshal (To_Bytes ("1.5e3"), F, Err);
      Assert (Err = Errors.No_Error and then F = 1500.0,
              "unmarshal 1.5e3: " & Err_Text (Err));
      Unmarshal (To_Bytes ("1E+2"), F, Err);
      Assert (Err = Errors.No_Error and then F = 100.0,
              "unmarshal 1E+2: " & Err_Text (Err));
      --  20 digits overflow int64: Go widens the token to float64.
      Unmarshal (To_Bytes ("99999999999999999999"), F, Err);
      Assert (Err = Errors.No_Error and then F = 1.0e20,
              "unmarshal big int into float: " & Err_Text (Err));
      Unmarshal (To_Bytes ("""a\u0041b\n"""), S, Err);
      Assert (Err = Errors.No_Error
              and then To_String (S) = "aAb" & Character'Val (10),
              "unmarshal string: " & Err_Text (Err));
      --  null leaves the target unchanged, no error (Go semantics).
      I := 5;
      Unmarshal (To_Bytes ("null"), I, Err);
      Assert (Err = Errors.No_Error and then I = 5, "null is a no-op");
      F := 2.5;
      Unmarshal (To_Bytes ("null"), F, Err);
      Assert (Err = Errors.No_Error and then F = 2.5, "null float no-op");
      B := True;
      Unmarshal (To_Bytes ("null"), B, Err);
      Assert (Err = Errors.No_Error and then B, "null bool no-op");
      S := To_Unbounded_String ("keep");
      Unmarshal (To_Bytes ("null"), S, Err);
      Assert (Err = Errors.No_Error and then To_String (S) = "keep",
              "null string no-op");
   end Test_Unmarshal_Scalars;

   procedure Test_Unmarshal_Errors
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Err : Errors.Error_Access;
      I   : Integer := 0;
      F   : Long_Float := 0.0;
      B   : Boolean := False;
      S   : Unbounded_String := Null_Unbounded_String;
   begin
      Unmarshal (To_Bytes (""), I, Err);
      Assert (Err /= Errors.No_Error, "empty input must error");
      Unmarshal (To_Bytes ("4.5"), I, Err);
      Assert (Err /= Errors.No_Error, "float into int must error");
      Unmarshal (To_Bytes ("""x"""), I, Err);
      Assert (Err /= Errors.No_Error, "string into int must error");
      Unmarshal (To_Bytes ("[1]"), I, Err);
      Assert (Err /= Errors.No_Error, "array into scalar must error");
      Unmarshal (To_Bytes ("42 x"), I, Err);
      Assert (Err /= Errors.No_Error, "trailing junk must error");
      Unmarshal (To_Bytes ("tru"), B, Err);
      Assert (Err /= Errors.No_Error, "truncated literal must error");
      Unmarshal (To_Bytes ("1.2.3"), I, Err);
      Assert (Err /= Errors.No_Error, "bad number must error");
      Unmarshal (To_Bytes ("42"), B, Err);
      Assert (Err /= Errors.No_Error, "int into bool must error");
      Unmarshal (To_Bytes ("7"), S, Err);
      Assert (Err /= Errors.No_Error, "int into string must error");
      Unmarshal (To_Bytes ("1e"), I, Err);
      Assert (Err /= Errors.No_Error, "truncated exponent must error");
      Unmarshal (To_Bytes ("1e+"), I, Err);
      Assert (Err /= Errors.No_Error, "sign without digits must error");
      --  Fits int64 but not 32-bit Integer: range error on the target.
      Unmarshal (To_Bytes ("3000000000"), I, Err);
      Assert (Err /= Errors.No_Error, "int range overflow must error");
      Unmarshal (To_Bytes (""), F, Err);
      Assert (Err /= Errors.No_Error, "empty into float must error");
      Unmarshal (To_Bytes ("""s"""), F, Err);
      Assert (Err /= Errors.No_Error, "string into float must error");
      Unmarshal (To_Bytes ("""abc"), S, Err);
      Assert (Err /= Errors.No_Error, "unterminated string must error");
      Unmarshal (To_Bytes ("""a\xb"""), S, Err);
      Assert (Err /= Errors.No_Error, "bad escape in string must error");
      Unmarshal (To_Bytes ("["), S, Err);
      Assert (Err /= Errors.No_Error, "array token into string must error");
   end Test_Unmarshal_Errors;

   procedure Test_Parse_Object (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M   : Member_Vectors.Vector;
      OK  : Boolean;
      procedure Check_Bad (Text : String) is
      begin
         Parse_Object (Text, M, OK);
         Assert (not OK, "object should be rejected: " & Text);
      end Check_Bad;
   begin
      Parse_Object ("{}", M, OK);
      Assert (OK and then Member_Vectors.Is_Empty (M), "empty object");

      Parse_Object ("  { \"x\" : 42, \"s\" : \"a\\nb\",
                      \"b\" : true, \"f\" : -1.5, \"n\" : null }  ",
                    M, OK);
      Assert (OK, "object parse failed");
      Assert (Integer (Member_Vectors.Length (M)) = 5,
              "member count: " & Integer'Image
                (Integer (Member_Vectors.Length (M))));
      declare
         M1 : constant Member := Member_Vectors.Element (M, 1);
         M2 : constant Member := Member_Vectors.Element (M, 2);
         M3 : constant Member := Member_Vectors.Element (M, 3);
         M4 : constant Member := Member_Vectors.Element (M, 4);
         M5 : constant Member := Member_Vectors.Element (M, 5);
      begin
         Assert (To_String (M1.Key) = "x" and then M1.Val.Kind = K_Int
                 and then M1.Val.I = 42, "member x");
         Assert (To_String (M2.Key) = "s" and then M2.Val.Kind = K_String
                 and then To_String (M2.Val.S) = "a" & Character'Val (10)
                 & "b", "member s");
         Assert (To_String (M3.Key) = "b" and then M3.Val.Kind = K_Bool
                 and then M3.Val.B, "member b");
         Assert (To_String (M4.Key) = "f" and then M4.Val.Kind = K_Float
                 and then M4.Val.F = -1.5, "member f");
         Assert (To_String (M5.Key) = "n" and then M5.Val.Kind = K_Null,
                 "member n");
      end;

      Check_Bad ("{");
      Check_Bad ("{]");
      Check_Bad ("{"k"}");
      Check_Bad ("{"k": }");
      Check_Bad ("{"k": 1");
      Check_Bad ("{"k": [1]}");
      Check_Bad ("{"k": {"a":1}}");
      Check_Bad ("{"k": 1,}");
      Check_Bad ("not an object");
      Check_Bad ("{"k": 1} x");
   end Test_Parse_Object;

   procedure Test_Float_Image (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data : Byte_Slice;
      Err  : Errors.Error_Access;
      procedure Check (X : Long_Float; Want : String) is
      begin
         Marshal (X, Data, Err);
         Assert (Err = Errors.No_Error and then To_String (Data) = Want,
                 "float image of " & Long_Float'Image (X) & " = '"
                 & To_String (Data) & "' want '" & Want & "'");
      end Check;
   begin
      Check (0.0, "0");
      Check (-0.5, "-0.5");
      Check (1.5, "1.5");
      Check (150.0, "150");
      Check (0.000001, "0.000001");
      Check (-2.5e3, "-2500");
      --  Go's encoder switches to 'e' format only outside [1e-6, 1e21).
      Check (1.0e20, "100000000000000000000");
      Check (1.0e21, "1e+21");
      Check (-1.0e21, "-1e+21");
      Check (1.5e-7, "1.5e-7");
   end Test_Float_Image;

end Json_Suite;
