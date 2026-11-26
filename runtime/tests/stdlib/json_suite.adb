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
      Check ("say \"hi\"", "say ""hi""");
      Check ("back\\slash", "back\slash");
      Check ("nl\ncr\rbt\btbf\ff", "nl" & Character'Val (10)
              & "cr" & Character'Val (13) & "bt" & Character'Val (9)
              & "tbf" & Character'Val (12) & "f");
      Check ("\u0041", "A");       --  A
      Check ("Euro" & "\u20ac" & "x", "Euro" & Character'Val (16#E2#)
              & Character'Val (16#82#) & Character'Val (16#AC#) & "x");
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
      Unmarshal (To_Bytes ("""a\u0041b\n"""), S, Err);
      Assert (Err = Errors.No_Error
              and then To_String (S) = "aAb" & Character'Val (10),
              "unmarshal string: " & Err_Text (Err));
      --  null leaves the target unchanged, no error (Go semantics).
      I := 5;
      Unmarshal (To_Bytes ("null"), I, Err);
      Assert (Err = Errors.No_Error and then I = 5, "null is a no-op");
   end Test_Unmarshal_Scalars;

   procedure Test_Unmarshal_Errors
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Err : Errors.Error_Access;
      I   : Integer := 0;
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
   end Test_Unmarshal_Errors;

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
      Check (1.5e-7, "1.5e-7");
   end Test_Float_Image;

end Json_Suite;
