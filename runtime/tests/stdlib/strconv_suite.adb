--  Body of Strconv_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded;
with Gada.Std.Errors;
with Gada.Std.Strconv; use Gada.Std.Strconv;

use type Gada.Std.Errors.Error_Access;

package body Strconv_Suite is

   package Errors renames Gada.Std.Errors;

   HT : constant Character := Character'Val (9);
   LF : constant Character := Character'Val (10);

   overriding function Name
     (T : Strconv_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Strconv suite"));

   overriding procedure Register_Tests (T : in out Strconv_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Itoa'Access, "Itoa");
      Register_Routine (T, Test_Atoi_Ok'Access, "Atoi ok/sign/zeros");
      Register_Routine (T, Test_Atoi_Syntax'Access, "Atoi syntax errors");
      Register_Routine (T, Test_Atoi_Range'Access, "Atoi clamp + ErrRange");
      Register_Routine (T, Test_Format_Float_G'Access, "FormatFloat g/-1");
      Register_Routine (T, Test_Format_Float_F_E'Access, "FormatFloat f/e/E");
      Register_Routine (T, Test_Parse_Float_Ok'Access,
                        "ParseFloat ok/specials");
      Register_Routine (T, Test_Parse_Float_Errors'Access, "ParseFloat errors");
      Register_Routine (T, Test_Quote'Access, "Quote escapes");
      Register_Routine (T, Test_Unquote'Access, "Unquote quoted/raw/char");
      Register_Routine (T, Test_Unquote_Errors'Access, "Unquote errors");
      Register_Routine (T, Test_Num_Error_Is_As'Access,
                        "NumError Is/As/Message");
      Register_Routine (T, Test_Edges'Access, "escapes/UTF-8/rounding edges");
   end Register_Tests;

   procedure Test_Itoa (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Itoa (0) = "0", "Itoa 0");
      Assert (Itoa (42) = "42", "Itoa 42");
      Assert (Itoa (-7) = "-7", "Itoa -7");
      Assert (Itoa (Integer'Last) = "2147483647", "Itoa Integer'Last");
      Assert (Itoa (Integer'First) = "-2147483648", "Itoa Integer'First");
   end Test_Itoa;

   procedure Test_Atoi_Ok (T : in out AUnit.Test_Cases.Test_Case'Class) is
      V : Integer;
      E : Errors.Error_Access;
   begin
      Atoi ("42", V, E);
      Assert (V = 42 and E = Errors.No_Error, "Atoi 42");
      Atoi ("-7", V, E);
      Assert (V = -7 and E = Errors.No_Error, "Atoi -7");
      Atoi ("+13", V, E);
      Assert (V = 13 and E = Errors.No_Error, "Atoi +13");
      Atoi ("007", V, E);
      Assert (V = 7 and E = Errors.No_Error, "Atoi 007 = 7");
      Atoi ("2147483647", V, E);
      Assert (V = Integer'Last and E = Errors.No_Error, "Atoi max ok");
      Atoi ("-2147483648", V, E);
      Assert (V = Integer'First and E = Errors.No_Error, "Atoi min ok");
   end Test_Atoi_Ok;

   procedure Test_Atoi_Syntax (T : in out AUnit.Test_Cases.Test_Case'Class) is
      V : Integer;
      E : Errors.Error_Access;
   begin
      Atoi ("", V, E);
      Assert (V = 0 and E /= Errors.No_Error, "Atoi empty errors");
      Assert (Errors.Is_K (E, Err_Syntax), "empty: Is Err_Syntax");
      Assert (not Errors.Is_K (E, Err_Range), "empty: not Err_Range");
      Atoi ("abc", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "abc: Is Err_Syntax");
      Atoi ("+", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "sign only: syntax");
      Atoi ("1x", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "trailing junk: syntax");
      Atoi (" 1", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "leading space: syntax");
      Atoi ("1 ", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "trailing space: syntax");
   end Test_Atoi_Syntax;

   procedure Test_Atoi_Range (T : in out AUnit.Test_Cases.Test_Case'Class) is
      V : Integer;
      E : Errors.Error_Access;
   begin
      Atoi ("99999999999999999999", V, E);
      Assert (V = Integer'Last, "overflow clamps to max");
      Assert (Errors.Is_K (E, Err_Range), "overflow: Is Err_Range");
      Atoi ("-99999999999999999999", V, E);
      Assert (V = Integer'First, "underflow clamps to min");
      Assert (Errors.Is_K (E, Err_Range), "underflow: Is Err_Range");
      Atoi ("2147483648", V, E);
      Assert (V = Integer'Last and Errors.Is_K (E, Err_Range),
              "max+1 clamps with Err_Range");
   end Test_Atoi_Range;

   procedure Test_Format_Float_G (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Nan, PInf, NInf, Denorm : Long_Float;
      E : Errors.Error_Access;
   begin
      Assert (Format_Float (3.14) = "3.14", "g 3.14");
      Assert (Format_Float (0.0) = "0", "g 0");
      Assert (Format_Float (-0.0) = "-0", "g -0");
      Assert (Format_Float (100000.0) = "100000", "g 100000 stays fixed");
      Assert (Format_Float (1000000.0) = "1e+06", "g 1e6 switches to e");
      Assert (Format_Float (1.0e21) = "1e+21", "g 1e21");
      Assert (Format_Float (123456789.0) = "1.23456789e+08", "g 9 digits");
      Assert (Format_Float (0.0001) = "0.0001", "g 1e-4 stays fixed");
      Assert (Format_Float (0.00001) = "1e-05", "g 1e-5 switches to e");
      --  Specials via Parse_Float (Go's exact spellings).
      Parse_Float ("nan", Nan, E);
      Assert (E = Errors.No_Error and Nan /= Nan, "parse nan");
      Assert (Format_Float (Nan) = "NaN", "format NaN");
      Parse_Float ("+Inf", PInf, E);
      Parse_Float ("-Inf", NInf, E);
      Assert (PInf > Long_Float'Last, "+Inf parsed");
      Assert (NInf < Long_Float'First, "-Inf parsed");
      Assert (Format_Float (PInf) = "+Inf", "format +Inf");
      Assert (Format_Float (NInf) = "-Inf", "format -Inf");
      --  Denormal minimum: shortest form is "5e-324".
      Parse_Float ("5e-324", Denorm, E);
      Assert (E = Errors.No_Error and Denorm > 0.0, "parse denormal");
      Assert (Format_Float (Denorm) = "5e-324", "format denormal 5e-324");
   end Test_Format_Float_G;

   procedure Test_Format_Float_F_E (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Format_Float (3.14159, 'f', 2) = "3.14", "f prec 2");
      Assert (Format_Float (3.14159, 'f', 4) = "3.1416", "f prec 4 rounds");
      Assert (Format_Float (0.4, 'f', 0) = "0", "f prec 0 of 0.4");
      Assert (Format_Float (2.5, 'f', 0) = "2", "f prec 0 half-even");
      Assert (Format_Float (1.0e21, 'f', -1) = "1000000000000000000000",
              "f shortest of 1e21 has no exponent");
      Assert (Format_Float (31415.9, 'e', 3) = "3.142e+04", "e prec 3");
      Assert (Format_Float (31415.9, 'E', 3) = "3.142E+04", "E prec 3");
      Assert (Format_Float (0.0, 'e', 2) = "0.00e+00", "e of zero");
   end Test_Format_Float_F_E;

   procedure Test_Parse_Float_Ok (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      V : Long_Float;
      E : Errors.Error_Access;
   begin
      Parse_Float ("3.14", V, E);
      Assert (V = 3.14 and E = Errors.No_Error, "parse 3.14");
      Parse_Float ("-2.5e-3", V, E);
      Assert (V = -0.0025 and E = Errors.No_Error, "parse -2.5e-3");
      Parse_Float (".5", V, E);
      Assert (V = 0.5 and E = Errors.No_Error, "parse .5");
      Parse_Float ("5.", V, E);
      Assert (V = 5.0 and E = Errors.No_Error, "parse 5.");
      Parse_Float ("+1e2", V, E);
      Assert (V = 100.0 and E = Errors.No_Error, "parse +1e2");
      Parse_Float ("NAN", V, E);
      Assert (V /= V and E = Errors.No_Error, "parse NAN any case");
      Parse_Float ("-INFINITY", V, E);
      Assert (V < Long_Float'First and E = Errors.No_Error,
              "parse -INFINITY any case");
   end Test_Parse_Float_Ok;

   procedure Test_Parse_Float_Errors (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      V : Long_Float;
      E : Errors.Error_Access;
   begin
      Parse_Float ("", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "empty: syntax");
      Parse_Float ("abc", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "abc: syntax");
      Parse_Float ("1.5.2", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "two dots: syntax");
      Parse_Float ("1e", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "bare exponent: syntax");
      Parse_Float ("--1", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "double sign: syntax");
      Parse_Float ("1_000", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "underscores rejected in v1");
      Parse_Float ("1e999", V, E);
      Assert (V > Long_Float'Last and Errors.Is_K (E, Err_Range),
              "overflow: +Inf + Err_Range");
      Parse_Float ("-1e999", V, E);
      Assert (V < Long_Float'First and Errors.Is_K (E, Err_Range),
              "overflow: -Inf + Err_Range");
   end Test_Parse_Float_Errors;

   procedure Test_Quote (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Quote ("hello") = """hello""", "Quote hello");
      Assert (Quote ("") = """""", "Quote empty");
      Assert (Quote ("a" & '"' & "b") = """a\""b""", "Quote escapes quote");
      Assert (Quote ("a\b") = """a\\b""", "Quote escapes backslash");
      Assert (Quote ((1 => HT)) = '"' & "\t" & '"', "Quote tab");
      Assert (Quote ((1 => LF)) = '"' & "\n" & '"', "Quote LF");
      Assert (Quote ((1 => Character'Val (1))) = '"' & "\x01" & '"',
              "Quote control byte as \xNN");
      Assert (Quote ((1 => Character'Val (127))) = '"' & "\x7f" & '"',
              "Quote DEL as \xNN");
   end Test_Quote;

   procedure Test_Unquote (T : in out AUnit.Test_Cases.Test_Case'Class) is
      V : Ada.Strings.Unbounded.Unbounded_String;
      E : Errors.Error_Access;
      S : constant String :=
        "a" & '"' & '\' & HT & LF & Character'Val (1) & "xy";
   begin
      Unquote ("""hello""", V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V) = "hello",
              "Unquote plain");
      --  Round-trip through Quote, including control chars.
      Unquote (Quote (S), V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V) = S,
              "Unquote(Quote(S)) = S");
      --  Raw string literal: backslash is not an escape there.
      Unquote ("`a\nb`", V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V) = "a\nb",
              "Unquote raw keeps backslash literal");
      --  Char literals.
      Unquote ("'a'", V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V) = "a",
              "Unquote char literal");
      Unquote ("'\n'", V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V) = (1 => LF),
              "Unquote escaped char literal");
      --  \u escape encodes UTF-8 (U+00E9 → 0xC3 0xA9).
      Unquote ("""\u00e9""", V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V)
                = (Character'Val (16#C3#), Character'Val (16#A9#)),
              "Unquote \u00e9 gives UTF-8 bytes");
      --  Octal escape.
      Unquote ("""\101""", V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V) = "A",
              "Unquote octal \101 = A");
   end Test_Unquote;

   procedure Test_Unquote_Errors (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      V : Ada.Strings.Unbounded.Unbounded_String;
      E : Errors.Error_Access;
   begin
      Unquote ("abc", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "no quotes: syntax");
      Unquote ("""a", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "unterminated: syntax");
      Unquote ("""\x4""", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "short \x: syntax");
      Unquote ("""\777""", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "octal > 255: syntax");
      Unquote ("""\q""", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "unknown escape: syntax");
      Unquote ("'ab'", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "two-char literal: syntax");
   end Test_Unquote_Errors;

   procedure Test_Num_Error_Is_As (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      V : Integer;
      E : Errors.Error_Access;
      Tgt : aliased Num_Error;
      TA  : constant access Errors.Error'Class := Tgt'Access;
   begin
      Atoi ("x", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "NumError Is Err_Syntax");
      Assert (not Errors.Is_K (E, Err_Range), "NumError not Err_Range");
      Assert (Errors.As (E, TA), "As extracts Num_Error");
      Assert (Func (Tgt) = "Atoi", "Num_Error.Func");
      Assert (Num (Tgt) = "x", "Num_Error.Num");
      Assert (Err (Tgt) = Err_Syntax, "Num_Error.Err is the sentinel");
      Assert (Errors.Message (E.all)
                = "strconv.Atoi: parsing ""x"": invalid syntax",
              "Num_Error.Message format, got: "
                & Errors.Message (E.all));
      Assert (Errors.Unwrap (E) = Err_Syntax, "NumError Unwrap = sentinel");
   end Test_Num_Error_Is_As;

   procedure Test_Edges (T : in out AUnit.Test_Cases.Test_Case'Class) is
      V : Ada.Strings.Unbounded.Unbounded_String;
      E : Errors.Error_Access;
   begin
      --  All simple escapes.
      Unquote ('"' & "\a\b\f\r\v\'" & '"', V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V)
                = (Character'Val (7), Character'Val (8),
                   Character'Val (12), Character'Val (13),
                   Character'Val (11), Character'Val (39)),
              "simple escapes a b f r v '");
      --  Hex escape, incl. A-F digits.
      Unquote ('"' & "\xAB" & '"', V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V)
                = (1 => Character'Val (16#AB#)),
              "\xAB");
      Unquote ('"' & "\xZZ" & '"', V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "\xZZ invalid");
      --  Unicode escapes: 1/3/4-byte UTF-8, surrogate rejection.
      Unquote ('"' & "\u0041" & '"', V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V) = "A", "\u0041");
      Unquote ('"' & "\u0800" & '"', V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V)
                = (Character'Val (16#E0#), Character'Val (16#A0#),
                   Character'Val (16#80#)),
              "\u0800 is 3-byte UTF-8");
      Unquote ('"' & "\U0001F600" & '"', V, E);
      Assert (E = Errors.No_Error
              and Ada.Strings.Unbounded.To_String (V)
                = (Character'Val (16#F0#), Character'Val (16#9F#),
                   Character'Val (16#98#), Character'Val (16#80#)),
              "\U0001F600 is 4-byte UTF-8");
      Unquote ('"' & "\uD800" & '"', V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "surrogate rejected");
      --  Rounding carry: 9.999 to 3 significant digits overflows to 10.
      Assert (Format_Float (9.999, 'e', 2) = "1.00e+01", "carry 9.999");
      --  'f' prec 0 rounds at the units digit.
      Assert (Format_Float (0.6, 'f', 0) = "1", "0.6 rounds to 1");
      Assert (Format_Float (0.4, 'f', 0) = "0", "0.4 rounds to 0");
      --  17-significant-digit shortest (0.1 + 0.2).
      Assert (Format_Float (0.1 + 0.2) = "0.30000000000000004",
              "17-digit shortest");
   end Test_Edges;

end Strconv_Suite;
