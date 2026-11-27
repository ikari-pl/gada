--  Body of Strconv_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with Interfaces;
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
      Register_Routine (T, Test_Format_Float_Negative'Access,
                        "FormatFloat negative values");
      Register_Routine (T, Test_Format_Float_Shortest_Exact'Access,
                        "FormatFloat shortest exact (subnormals)");
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
      --  'g' with explicit precision: 0 means 1; trailing zeros strip;
      --  Eprec shrinks to the significant digit count.
      Assert (Format_Float (3.14, 'g', 0) = "3", "g prec 0 acts as 1");
      Assert (Format_Float (1.5, 'g', 5) = "1.5", "g prec 5 strips zeros");
      Assert (Format_Float (123.456, 'g', 4) = "123.5", "g prec 4 rounds");
      Assert (Format_Float (123456.0, 'g', 8) = "123456", "g prec 8 Eprec");
      Assert (Format_Float (0.000123, 'g', 2) = "0.00012", "g small exp");
      --  'g' fixed form strips zeros even when the value has fewer
      --  significant digits than the exponent needs (Go-verified).
      Assert (Format_Float (1.0e6, 'g', 8) = "1000000", "g 1e6 prec 8");
      Assert (Format_Float (9.999, 'g', 3) = "10", "g 9.999 prec 3");
      Assert (Format_Float (100.0, 'g', 6) = "100", "g 100 prec 6");
      Assert (Format_Float (1.0e21, 'g', 25) =
                "1000000000000000000000", "g 1e21 prec 25");
      --  Shortest-mode tie-to-even must pick the even last digit.
      Assert (Format_Float (8.111033711064938e+13) =
                "8.111033711064938e+13", "g shortest tie-to-even");
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
      --  Carry propagation when rounding overflows the kept digits.
      Assert (Format_Float (9.99, 'f', 1) = "10.0", "carry 9.99 f");
      Assert (Format_Float (0.99, 'f', 1) = "1.0", "carry 0.99 f");
      Assert (Format_Float (999.9, 'e', 2) = "1.00e+03", "carry 999.9 e");
      --  Zero-case rounding at the 10^-Aft position (DP + Aft < 1).
      Assert (Format_Float (0.06, 'f', 1) = "0.1", "0.06 rounds up");
      Assert (Format_Float (0.04, 'f', 1) = "0.0", "0.04 rounds down");
      --  DP + Aft < 0: the digit at 10^-Aft is an implicit 0, so the
      --  value is below half a unit and must round DOWN (Go-verified).
      Assert (Format_Float (0.06, 'f', 0) = "0", "0.06 f 0 rounds down");
      Assert (Format_Float (0.05, 'f', 0) = "0", "0.05 f 0 tie down");
      Assert (Format_Float (0.006, 'f', 1) = "0.0", "0.006 f 1 rounds down");
      Assert (Format_Float (9.999e-05, 'f', 2) = "0.00", "9.999e-5 f 2");
      --  Half-to-even tests the least significant KEPT digit (R (1)),
      --  not the MSB (Go-verified).
      Assert (Format_Float (199.125, 'f', 2) = "199.12", "199.125 f 2 even");
      Assert (Format_Float (0.125, 'f', 2) = "0.12", "0.125 f 2 even");
      Assert (Format_Float (0.375, 'f', 2) = "0.38", "0.375 f 2 odd up");
      Assert (Format_Float (1.25, 'e', 1) = "1.2e+00", "1.25 e 1 even");
      --  Fmt_F zero-padding branches.
      Assert (Format_Float (0.0001, 'f', 6) = "0.000100", "f lead zeros");
      Assert (Format_Float (123.0, 'f', 3) = "123.000", "f int + pad");
      Assert (Format_Float (1.5, 'f', 5) = "1.50000", "f frac pad");
      Assert (Format_Float (0.5, 'f', 3) = "0.500", "f short digits pad");
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
      Parse_Float ("-nan", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "-nan: syntax (Go rejects)");
      Parse_Float ("+nan", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "+nan: syntax (Go rejects)");
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
      --  Named escapes for the remaining control chars.
      Assert (Quote ((1 => Character'Val (7))) = '"' & "\a" & '"',
              "Quote BEL as escape a");
      Assert (Quote ((1 => Character'Val (8))) = '"' & "\b" & '"',
              "Quote BS as escape b");
      Assert (Quote ((1 => Character'Val (11))) = '"' & "\v" & '"',
              "Quote VT as escape v");
      Assert (Quote ((1 => Character'Val (12))) = '"' & "\f" & '"',
              "Quote FF as escape f");
      Assert (Quote ((1 => Character'Val (13))) = '"' & "\r" & '"',
              "Quote CR as escape r");
      --  Apostrophe is printable: not escaped (Go contract).
      Assert (Quote ((1 => Character'Val (39))) = '"' & Character'Val (39)
                & '"', "Quote apostrophe raw");
      --  Bytes >= 16#80# (PR #45 review testing gap): valid UTF-8 passes
      --  through, invalid bytes are \xNN, C1 controls are \u00XX.
      --  Expected strings are Go's strconv.Quote output.
      declare
         E_Acute : constant String :=
           (Character'Val (16#C3#), Character'Val (16#A9#));
         Euro    : constant String :=
           (Character'Val (16#E2#), Character'Val (16#82#),
            Character'Val (16#AC#));
         Smiley  : constant String :=
           (Character'Val (16#F0#), Character'Val (16#9F#),
            Character'Val (16#98#), Character'Val (16#80#));
      begin
         Assert (Quote ("caf" & Character'Val (16#E9#))
                   = '"' & "caf\xe9" & '"', "Latin-1 byte is \xNN");
         Assert (Quote ("caf" & E_Acute) = '"' & "caf" & E_Acute & '"',
                 "valid 2-byte UTF-8 raw");
         Assert (Quote (Euro) = '"' & Euro & '"', "valid 3-byte raw");
         Assert (Quote (Smiley) = '"' & Smiley & '"', "valid 4-byte raw");
         Assert (Quote ((Character'Val (16#FF#), Character'Val (16#FE#)))
                   = '"' & "\xff\xfe" & '"', "invalid lead bytes");
         Assert (Quote ((Character'Val (16#C2#), Character'Val (16#85#)))
                   = '"' & "\u0085" & '"', "C1 control is \u00XX");
         Assert (Quote ((Character'Val (16#C0#), Character'Val (16#AF#)))
                   = '"' & "\xc0\xaf" & '"', "overlong rejected");
         Assert (Quote ((Character'Val (16#ED#), Character'Val (16#A0#),
                         Character'Val (16#80#)))
                   = '"' & "\xed\xa0\x80" & '"', "surrogate rejected");
         Assert (Quote ((Character'Val (16#F4#), Character'Val (16#90#),
                         Character'Val (16#80#), Character'Val (16#80#)))
                   = '"' & "\xf4\x90\x80\x80" & '"', "> U+10FFFF rejected");
         Assert (Quote ((Character'Val (16#E2#), Character'Val (16#82#)))
                   = '"' & "\xe2\x82" & '"', "truncated sequence");
         Assert (Quote ((1 => Character'Val (16#C2#)))
                   = '"' & "\xc2" & '"', "lead byte at end");
         Assert (Quote (Euro (1 .. 2) & "x")
                   = '"' & "\xe2\x82x" & '"', "bad continuation byte");
      end;
      --  Quote_Rune of the delimiters (Go: '\'' and '"').
      Assert (Quote_Rune (Character'Val (39)) = "'\''", "QuoteRune '");
      Assert (Quote_Rune ('"') = "'""'", "QuoteRune dquote unescaped");
      Assert (Quote_Rune (Character'Val (16#E9#))
                = "'" & Character'Val (16#C3#) & Character'Val (16#A9#) & "'",
              "QuoteRune U+00E9 is UTF-8");
      Assert (Quote_Rune (Character'Val (16#85#)) = "'\u0085'",
              "QuoteRune C1 control");
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
      Unquote ("", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "empty string: syntax");
      Unquote ("x", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "one char: syntax");
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
      --  Trailing backslash with nothing after it.
      Unquote ('"' & '\' & '"', V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "trailing backslash: syntax");
      --  Octal escape with fewer than 3 digits, and a non-octal digit.
      Unquote ('"' & "\1" & '"', V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "short octal: syntax");
      Unquote ('"' & "\189" & '"', V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "bad octal digit: syntax");
      --  Unterminated raw string; backquote inside a raw string.
      Unquote ("`abc", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "raw unterminated: syntax");
      Unquote ("`a`b`", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "raw inner backquote: syntax");
      --  Unterminated char literal; unterminated double quote.
      Unquote ("'a", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "char unterminated: syntax");
      Unquote ('"' & "a", V, E);
      Assert (Errors.Is_K (E, Err_Syntax), "dquote unterminated: syntax");
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
      Assert (Errors.Unwrap (E.all) = Err_Syntax,
              "NumError Unwrap = sentinel");
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
      --  17-significant-digit shortest: typed constants force a real
      --  float64 addition (the literal expression 0.1 + 0.2 is static
      --  and exact in Ada, like Go's constant folding — fl(0.3)).
      declare
         A : Long_Float := 0.1;
         B : Long_Float := 0.2;
      begin
         Assert (Format_Float (A + B) = "0.30000000000000004",
                 "17-digit shortest");
         Assert (Format_Float (0.1 + 0.2) = "0.3",
                 "static 0.1 + 0.2 folds to fl(0.3)");
      end;
   end Test_Edges;

   --  Regression (PR #45 review #1): Exact_Digits got the signed value,
   --  so every negative non-zero float raised ('g'/'e') or printed
   --  -0.0 ('f'). Expected strings are Go's FormatFloat output.
   procedure Test_Format_Float_Negative (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Format_Float (-1.5) = "-1.5", "-1.5 g/-1");
      Assert (Format_Float (-2.5, 'f', 1) = "-2.5", "-2.5 f/1");
      Assert (Format_Float (-3.5, 'f', 2) = "-3.50", "-3.5 f/2");
      Assert (Format_Float (-31415.9, 'e', 3) = "-3.142e+04", "-31415.9 e/3");
      Assert (Format_Float (-0.1) = "-0.1", "-0.1 g/-1");
      Assert (Format_Float (-1.0e21) = "-1e+21", "-1e21 g/-1");
      Assert (Format_Float (-0.000012) = "-1.2e-05", "-1.2e-05 g/-1");
   end Test_Format_Float_Negative;

   --  Regression (PR #45 review #9): shortest formatting chose its digit
   --  count by round-tripping through GNAT's Long_Float'Value, which
   --  misrounds subnormals — ~17% of random subnormals came out wrong.
   --  Shortest now runs Go's exact roundShortest on the half-ulp
   --  neighbours. Cases: 24 subnormals the old code got wrong (drawn
   --  from a 47k-value differential run against Go, seed 45: 3404
   --  mismatches before, 0 after) plus boundary values. Expected
   --  strings are Go's FormatFloat(f, 'g'/'e', -1, 64).
   procedure Test_Format_Float_Shortest_Exact (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      function To_F is new Ada.Unchecked_Conversion
        (Interfaces.Unsigned_64, Long_Float);
      procedure Check (Bits : Interfaces.Unsigned_64; G : String;
                       E : String := "") is
         X : constant Long_Float := To_F (Bits);
      begin
         Assert (Format_Float (X) = G,
                 "g: want " & G & ", got " & Format_Float (X));
         Assert (Format_Float (X, 'e', -1) = (if E = "" then G else E),
                 "e: want " & G & ", got " & Format_Float (X, 'e', -1));
      end Check;
   begin
      Check (16#000f_aba2_97e5_fde1#,
             "2.17924425250681e-308");
      Check (16#000c_bd92_5c6b_7f6a#,
             "1.7717866156888607e-308");
      Check (16#000c_72e3_fd94_d146#,
             "1.7312175140357073e-308");
      Check (16#0006_3461_91ab_70c9#,
             "8.62857745964021e-309");
      Check (16#000d_ffde_908e_91ae#,
             "1.9468686765757967e-308");
      Check (16#000a_0c37_091d_a790#,
             "1.3973067179669507e-308");
      Check (16#000f_0ea7_b345_035b#,
             "2.093967834536238e-308");
      Check (16#000f_3c47_c456_631a#,
             "2.1187528868510497e-308");
      Check (16#000e_dc63_c598_8d03#,
             "2.066662144605801e-308");
      Check (16#0009_a8bd_1055_fdc7#,
             "1.343268033001685e-308");
      Check (16#0005_28e1_2c24_cdff#,
             "7.1754263264568e-309");
      Check (16#000c_f375_6196_b416#,
             "1.8010595904694196e-308");
      Check (16#0001_b8bc_9bb5_c9da#,
             "2.394218317913137e-309");
      Check (16#000b_9e2e_116d_7b8f#,
             "1.61566651974178e-308");
      Check (16#0007_6889_db70_8496#,
             "1.0302583614032363e-308");
      Check (16#000b_224e_06bf_283e#,
             "1.5483737006837296e-308");
      Check (16#0003_3df6_6d2f_d64d#,
             "4.50861350761334e-309");
      Check (16#000f_a1c2_cc3c_95d8#,
             "2.1738802809814667e-308");
      Check (16#000e_1dfa_603a_af18#,
             "1.9632246195422233e-308");
      Check (16#000a_1ee7_c690_29fe#,
             "1.4074599161683463e-308");
      Check (16#000c_7b57_ba0b_f744#,
             "1.7358089531301407e-308");
      Check (16#000d_2c38_206f_1a2c#,
             "1.8318937712376907e-308");
      Check (16#000d_1bdb_b37a_3614#,
             "1.8230059497188073e-308");
      Check (16#0006_74f2_d4b8_acb0#,
             "8.979327701874767e-309");
      Check (16#0010_0000_0000_0000#,
             "2.2250738585072014e-308");
      Check (16#7fef_ffff_ffff_ffff#,
             "1.7976931348623157e+308");
      Check (16#0000_0000_0000_0001#,
             "5e-324");
      Check (16#4340_0000_0000_0000#,
             "9.007199254740992e+15");
      --  Upper_Delta 1 -> 2 transition (found by the differential run).
      Check (16#4351_6380_09c4_1fed#,
             "1.9577904699572148e+16");
      --  float64(1e23) is 9.999999999999999e22 but owns 1e23: shortest
      --  rounds up past the leading digit to the next power of ten.
      Check (16#44b5_2d02_c7e1_4af6#, "1e+23");
      Check (16#3fb9_9999_9999_999a#,
             "0.1", "1e-01");
   end Test_Format_Float_Shortest_Exact;

end Strconv_Suite;
