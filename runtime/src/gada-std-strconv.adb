--  Body of Gada.Std.Strconv — see spec for the Go-semantics contract.
--
--  Ada 2022 idioms used: expression functions for the one-liners,
--  conditional expressions, `for C of S` array iteration, and numeric
--  literals with underscores.

with Ada.Characters.Handling;
with Ada.Long_Float_Text_IO;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with Interfaces;
with Gada.Std.Errors;

package body Gada.Std.Strconv is

   package Errors renames Gada.Std.Errors;

   --  IEEE-754 binary64 special values, built from their bit patterns
   --  (the portable spelling — Ada has no standard NaN/Inf literals).
   type U64 is new Interfaces.Unsigned_64;
   function To_Float is new Ada.Unchecked_Conversion (U64, Long_Float);

   Inf_Float : constant Long_Float := To_Float (16#7FF0_0000_0000_0000#);
   NaN_Float : constant Long_Float := To_Float (16#7FF8_0000_0000_0000#);

   Hex_Digits : constant String := "0123456789abcdef";

   function Hex2 (C : Character) return String is
     (String'(Hex_Digits (1 + Character'Pos (C) / 16),
               Hex_Digits (1 + Character'Pos (C) mod 16)));

   --  Value of a hex digit, or -1 if C is not a hex digit.
   function Hex_Val (C : Character) return Integer is
     (if C in '0' .. '9' then
        Character'Pos (C) - Character'Pos ('0')
      elsif C in 'a' .. 'f' then
        Character'Pos (C) - Character'Pos ('a') + 10
      elsif C in 'A' .. 'F' then
        Character'Pos (C) - Character'Pos ('A') + 10
      else
        -1);

   --  Reads N hex digits of S starting at I; returns their value, or
   --  -1 if any digit is invalid or the string is too short.
   function Hex_N (S : String; I, N : Integer) return Integer is
      V : Integer := 0;
   begin
      if I + N - 1 > S'Last then
         return -1;
      end if;
      for K in 0 .. N - 1 loop
         declare
            D : constant Integer := Hex_Val (S (I + K));
         begin
            if D < 0 then
               return -1;
            end if;
            V := V * 16 + D;
         end;
      end loop;
      return V;
   end Hex_N;

   --  Appends the UTF-8 encoding of Rune (Go strings are UTF-8, so
   --  \u/\U escapes in Unquote produce UTF-8 bytes).
   procedure Append_Utf8 (Rune : Natural; Value : in out Unbounded_String) is
   begin
      if Rune < 16#80# then
         Append (Value, Character'Val (Rune));
      elsif Rune < 16#800# then
         Append (Value, Character'Val (16#C0# + Rune / 16#40#));
         Append (Value, Character'Val (16#80# + Rune mod 16#40#));
      elsif Rune < 16#10000# then
         Append (Value, Character'Val (16#E0# + Rune / 16#1000#));
         Append (Value, Character'Val (16#80# + Rune / 16#40# mod 16#40#));
         Append (Value, Character'Val (16#80# + Rune mod 16#40#));
      else
         Append (Value, Character'Val (16#F0# + Rune / 16#40000#));
         Append (Value, Character'Val (16#80# + Rune / 16#1000# mod 16#40#));
         Append (Value, Character'Val (16#80# + Rune / 16#40# mod 16#40#));
         Append (Value, Character'Val (16#80# + Rune mod 16#40#));
      end if;
   end Append_Utf8;

   --  Decodes one escape sequence at S (I) (S (I) = '\'), appending the
   --  decoded bytes to Value and advancing I past the sequence. False
   --  on malformed input. Go's escape set: a b f n r t v \ " ' x u U
   --  and 3-digit octal.
   function Decode_Escape
     (S : String; I : in out Integer; Value : in out Unbounded_String)
      return Boolean is
   begin
      if I + 1 > S'Last then
         return False;
      end if;
      case S (I + 1) is
         when 'a' => Append (Value, Character'Val (7));  I := I + 2;
         when 'b' => Append (Value, Character'Val (8));  I := I + 2;
         when 'f' => Append (Value, Character'Val (12)); I := I + 2;
         when 'n' => Append (Value, Character'Val (10)); I := I + 2;
         when 'r' => Append (Value, Character'Val (13)); I := I + 2;
         when 't' => Append (Value, Character'Val (9));  I := I + 2;
         when 'v' => Append (Value, Character'Val (11)); I := I + 2;
         when '\' => Append (Value, '\');                I := I + 2;
         when '"' => Append (Value, '"');                I := I + 2;
         when '\'' => Append (Value, '\'');              I := I + 2;
         when 'x' =>
            declare
               V : constant Integer := Hex_N (S, I + 2, 2);
            begin
               if V < 0 then
                  return False;
               end if;
               Append (Value, Character'Val (V));
               I := I + 4;
            end;
         when 'u' | 'U' =>
            declare
               N : constant Integer := (if S (I + 1) = 'u' then 4 else 8);
               V : constant Integer := Hex_N (S, I + 2, N);
            begin
               --  Go rejects surrogates and out-of-range code points.
               if V < 0 or else V > 16#10FFFF#
                 or else (V >= 16#D800# and then V <= 16#DFFF#)
               then
                  return False;
               end if;
               Append_Utf8 (V, Value);
               I := I + 2 + N;
            end;
         when '0' .. '7' =>
            declare
               V : Integer := 0;
            begin
               if I + 3 > S'Last then
                  return False;
               end if;
               for K in 1 .. 3 loop
                  if S (I + K) not in '0' .. '7' then
                     return False;
                  end if;
                  V := V * 8
                    + Character'Pos (S (I + K)) - Character'Pos ('0');
               end loop;
               if V > 255 then
                  return False;  --  Go: octal escapes are <= \377
               end if;
               Append (Value, Character'Val (V));
               I := I + 4;
            end;
         when others =>
            return False;
      end case;
      return True;
   end Decode_Escape;

   function Equal_Ignore_Case (A, B : String) return Boolean is
      use Ada.Characters.Handling;
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for I in A'Range loop
         if To_Lower (A (I)) /= To_Lower (B (B'First + I - A'First)) then
            return False;
         end if;
      end loop;
      return True;
   end Equal_Ignore_Case;

   --  'e'-formatting of F with Aft digits after the point (GNAT emits an
   --  uppercase E; case-adjusted for Go's 'e' when Upper is False).
   function Format_Sci (F : Long_Float; Aft : Natural; Upper : Boolean)
      return String is
      Buf : String (1 .. 128);
   begin
      Ada.Long_Float_Text_IO.Put (Buf, F, Fore => 1, Aft => Aft, Exp => 2);
      declare
         S : constant String :=
           Ada.Strings.Fixed.Trim (Buf, Ada.Strings.Right);
         R : String (S'Range) := S;
      begin
         if not Upper then
            for I in R'Range loop
               if R (I) = 'E' then
                  R (I) := 'e';
               end if;
            end loop;
         end if;
         return R;
      end;
   end Format_Sci;

   --  Decimal exponent (power of ten of the leading digit) of an 'e'-
   --  formatted string, e.g. "3.14E+05" → 5.
   function Exp10_Of (Sci : String) return Integer is
   begin
      for I in Sci'Range loop
         if Sci (I) = 'E' or else Sci (I) = 'e' then
            return Integer'Value (Sci (I + 1 .. Sci'Last));
         end if;
      end loop;
      return 0;
   end Exp10_Of;

   --  Smallest number of significant digits (1 .. 18) whose 'e'-form
   --  round-trips to F — Go's shortest representation for prec < 0.
   function Shortest_Digits (F : Long_Float) return Natural is
      Buf : String (1 .. 128);
   begin
      for Aft in 0 .. 17 loop
         Ada.Long_Float_Text_IO.Put (Buf, F, Fore => 1, Aft => Aft, Exp => 2);
         declare
            S : constant String :=
              Ada.Strings.Fixed.Trim (Buf, Ada.Strings.Right);
         begin
            if Long_Float'Value (S) = F then
               return Aft + 1;
            end if;
         end;
      end loop;
      return 18;
   end Shortest_Digits;

   function Format_Fixed (F : Long_Float; Aft : Natural) return String is
      Buf : String (1 .. 1024);
   begin
      Ada.Long_Float_Text_IO.Put (Buf, F, Fore => 1, Aft => Aft, Exp => 0);
      return Ada.Strings.Fixed.Trim (Buf, Ada.Strings.Right);
   end Format_Fixed;

   --  Go's 'g'/'G': use 'e' when the decimal exponent is < -4 or >= the
   --  effective precision (6 for shortest, else prec), otherwise 'f'.
   function Format_General (F : Long_Float; Prec : Integer;
                            Upper : Boolean) return String is
      Shortest : constant Boolean := Prec < 0;
      K        : constant Natural :=
        (if Shortest then Shortest_Digits (F)
         elsif Prec = 0 then 1
         else Prec);
      Sci      : constant String := Format_Sci (F, K - 1, Upper);
      Exp10    : constant Integer := Exp10_Of (Sci);
      --  Significant digits of the mantissa, trailing zeros stripped
      --  (mantissa is "d.dddd…": one digit before the point, K - 1 after).
      Epos     : Integer := Sci'Last + 1;
      Tz       : Natural := 0;
      Nd       : Natural;
   begin
      for I in Sci'Range loop
         if Sci (I) = 'E' or else Sci (I) = 'e' then
            Epos := I;
            exit;
         end if;
      end loop;
      for I in reverse Sci'First + 2 .. Epos - 1 loop
         exit when Sci (I) /= '0';
         Tz := Tz + 1;
      end loop;
      Nd := Natural'Max (1, K - Tz);
      declare
         Eprec : Natural := K;
      begin
         if Shortest then
            Eprec := 6;
         elsif Eprec > Nd and then Nd >= Exp10 + 1 then
            Eprec := Nd;
         end if;
         if Exp10 < -4 or else Exp10 >= Eprec then
            --  'e' branch: Go trims to min(prec, ndigits) digits.
            return Format_Sci (F, Natural'Min (K, Nd) - 1, Upper);
         end if;
         declare
            Digits : constant Natural := (if Shortest then Nd else Eprec);
         begin
            return Format_Fixed (F, Natural'Max (0, Digits - 1 - Exp10));
         end;
      end;
   end Format_General;

   --  Go's syntax check for a decimal float (v1: no underscores, no
   --  hex floats): [sign] digits [. digits] [(e|E) [sign] digits],
   --  at least one mantissa digit.
   function Valid_Decimal (S : String) return Boolean is
      I           : Integer := S'First;
      Mant_Digits : Natural := 0;
      Exp_Digits  : Natural := 0;
   begin
      if I <= S'Last
        and then (S (I) = '+' or else S (I) = '-')
      then
         I := I + 1;
      end if;
      while I <= S'Last and then S (I) in '0' .. '9' loop
         Mant_Digits := Mant_Digits + 1;
         I := I + 1;
      end loop;
      if I <= S'Last and then S (I) = '.' then
         I := I + 1;
         while I <= S'Last and then S (I) in '0' .. '9' loop
            Mant_Digits := Mant_Digits + 1;
            I := I + 1;
         end loop;
      end if;
      if Mant_Digits = 0 then
         return False;
      end if;
      if I <= S'Last and then (S (I) = 'e' or else S (I) = 'E') then
         I := I + 1;
         if I <= S'Last
           and then (S (I) = '+' or else S (I) = '-')
         then
            I := I + 1;
         end if;
         while I <= S'Last and then S (I) in '0' .. '9' loop
            Exp_Digits := Exp_Digits + 1;
            I := I + 1;
         end loop;
         if Exp_Digits = 0 then
            return False;
         end if;
      end if;
      return I > S'Last;
   end Valid_Decimal;

   --  Ada's 'Value needs digits on both sides of the point; Go accepts
   --  ".5" and "5." — normalize to "0.5" / "5.0".
   function Normalize (S : String) return String is
      Dot : Integer := 0;
   begin
      for I in S'Range loop
         if S (I) = '.' then
            Dot := I;
            exit;
         end if;
      end loop;
      if Dot = 0 then
         return S;
      end if;
      if Dot = S'First
        or else (Dot = S'First + 1
                and then (S (S'First) = '+' or else S (S'First) = '-'))
      then
         return S (S'First .. Dot - 1) & "0" & S (Dot .. S'Last);
      elsif Dot = S'Last then
         return S & "0";
      end if;
      return S;
   end Normalize;

   function New_Num_Error
     (Func, Num : String; Err : Errors.Error_Access)
      return Errors.Error_Access is
     (new Num_Error'(Errors.Base_Error ("", Err) with
                     Func_Name => To_Unbounded_String (Func),
                     Num_Text  => To_Unbounded_String (Num),
                     Err_Value => Err));

   function Func (E : Num_Error) return String is
     (To_String (E.Func_Name));

   function Num (E : Num_Error) return String is
     (To_String (E.Num_Text));

   function Err (E : Num_Error) return Errors.Error_Access is
     (E.Err_Value);

   function Itoa (I : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (I), Ada.Strings.Left));

   procedure Atoi (S : String; Value : out Integer;
                   Err : out Errors.Error_Access) is
      I        : Integer := S'First;
      Neg      : Boolean := False;
      Acc      : Long_Integer := 0;
      Digits   : Natural := 0;
      Overflow : Boolean := False;
      Limit    : Long_Integer;
   begin
      Value := 0;
      Err := Errors.No_Error;
      if S'Length = 0 then
         Err := New_Num_Error ("Atoi", S, Err_Syntax);
         return;
      end if;
      if S (S'First) = '+' or else S (S'First) = '-' then
         Neg := S (S'First) = '-';
         I := S'First + 1;
      end if;
      if I > S'Last then
         Err := New_Num_Error ("Atoi", S, Err_Syntax);
         return;
      end if;
      Limit := (if Neg then -Long_Integer (Integer'First)
                else Long_Integer (Integer'Last));
      while I <= S'Last and then S (I) in '0' .. '9' loop
         Digits := Digits + 1;
         declare
            D : constant Long_Integer :=
              Long_Integer (Character'Pos (S (I)) - Character'Pos ('0'));
         begin
            if not Overflow then
               if Acc > (Limit - D) / 10 then
                  Overflow := True;
               else
                  Acc := Acc * 10 + D;
               end if;
            end if;
         end;
         I := I + 1;
      end loop;
      if Digits = 0 or else I <= S'Last then
         Err := New_Num_Error ("Atoi", S, Err_Syntax);
         return;
      end if;
      if Overflow then
         Value := (if Neg then Integer'First else Integer'Last);
         Err := New_Num_Error ("Atoi", S, Err_Range);
         return;
      end if;
      Value := Integer (if Neg then -Acc else Acc);
   end Atoi;

   function Format_Float (F : Long_Float; Fmt : Character := 'g';
                          Prec : Integer := -1) return String is
   begin
      if F /= F then
         return "NaN";
      elsif F > Long_Float'Last then
         return "+Inf";
      elsif F < Long_Float'First then
         return "-Inf";
      end if;
      case Fmt is
         when 'f' | 'F' =>
            if Prec < 0 then
               declare
                  K     : constant Natural := Shortest_Digits (F);
                  Exp10 : constant Integer :=
                    Exp10_Of (Format_Sci (F, K - 1, True));
               begin
                  return Format_Fixed (F, Natural'Max (0, K - 1 - Exp10));
               end;
            end if;
            return Format_Fixed (F, Prec);
         when 'e' =>
            return Format_Sci
              (F, (if Prec < 0 then Shortest_Digits (F) - 1 else Prec),
               False);
         when 'E' =>
            return Format_Sci
              (F, (if Prec < 0 then Shortest_Digits (F) - 1 else Prec),
               True);
         when others =>  --  'g'/'G' (and anything else, like Go's default)
            return Format_General (F, Prec, Fmt = 'G');
      end case;
   end Format_Float;

   procedure Parse_Float (S : String; Value : out Long_Float;
                          Err : out Errors.Error_Access) is
      procedure Syntax is
      begin
         Value := 0.0;
         Err := New_Num_Error ("ParseFloat", S, Err_Syntax);
      end Syntax;
      procedure Range_Err is
      begin
         Err := New_Num_Error ("ParseFloat", S, Err_Range);
      end Range_Err;
   begin
      Value := 0.0;
      Err := Errors.No_Error;
      if S'Length = 0 then
         Syntax;
         return;
      end if;
      --  Special values: "nan", "inf", "infinity", any case, with an
      --  optional sign (Go's contract).
      declare
         Body : constant String :=
           (if S (S'First) = '+' or else S (S'First) = '-'
            then S (S'First + 1 .. S'Last)
            else S);
         Neg  : constant Boolean := S (S'First) = '-';
      begin
         if Equal_Ignore_Case (Body, "nan") then
            Value := NaN_Float;
            return;
         end if;
         if Equal_Ignore_Case (Body, "inf")
           or else Equal_Ignore_Case (Body, "infinity")
         then
            Value := (if Neg then -Inf_Float else Inf_Float);
            return;
         end if;
      end;
      if not Valid_Decimal (S) then
         Syntax;
         return;
      end if;
      declare
         N : constant String := Normalize (S);
      begin
         begin
            Value := Long_Float'Value (N);
         exception
            when Constraint_Error =>
               --  Out of range: Go returns ±Inf and Err_Range.
               Value := (if N (N'First) = '-' then -Inf_Float
                         else Inf_Float);
               Range_Err;
               return;
         end;
         --  Some GNAT modes return ±Inf instead of raising on overflow.
         if Value > Long_Float'Last or else Value < Long_Float'First then
            if Value < 0.0 then
               Value := -Inf_Float;
            else
               Value := Inf_Float;
            end if;
            Range_Err;
         end if;
      end;
   end Parse_Float;

   function Quote (S : String) return String is
      B : Unbounded_String;
   begin
      Append (B, '"');
      for C of S loop
         case C is
            when '"' =>
               Append (B, "\""");
            when '\' =>
               Append (B, "\\");
            when Character'Val (7) =>
               Append (B, "\a");
            when Character'Val (8) =>
               Append (B, "\b");
            when Character'Val (9) =>
               Append (B, "\t");
            when Character'Val (10) =>
               Append (B, "\n");
            when Character'Val (11) =>
               Append (B, "\v");
            when Character'Val (12) =>
               Append (B, "\f");
            when Character'Val (13) =>
               Append (B, "\r");
            when others =>
               if C < ' ' or else C = Character'Val (127) then
                  Append (B, "\x" & Hex2 (C));
               else
                  Append (B, C);
               end if;
         end case;
      end loop;
      Append (B, '"');
      return To_String (B);
   end Quote;

   procedure Unquote (S : String; Value : out Unbounded_String;
                      Err : out Errors.Error_Access) is
      procedure Syntax is
      begin
         Value := Null_Unbounded_String;
         Err := New_Num_Error ("Unquote", S, Err_Syntax);
      end Syntax;
   begin
      Value := Null_Unbounded_String;
      Err := Errors.No_Error;
      if S'Length < 2 then
         Syntax;
         return;
      end if;
      if S (S'First) = '`' then
         --  Raw string literal: no escapes, cannot contain a backquote.
         if S (S'Last) /= '`' then
            Syntax;
            return;
         end if;
         declare
            Inner : constant String := S (S'First + 1 .. S'Last - 1);
         begin
            for I in Inner'Range loop
               if Inner (I) = '`' then
                  Syntax;
                  return;
               end if;
            end loop;
            Value := To_Unbounded_String (Inner);
         end;
         return;
      end if;
      if S (S'First) = '\'' then
         --  Char literal: exactly one character or one escape sequence.
         if S (S'Last) /= '\'' then
            Syntax;
            return;
         end if;
         declare
            Inner : constant String := S (S'First + 1 .. S'Last - 1);
            I     : Integer := Inner'First;
         begin
            if Inner'Length = 1 then
               Value := To_Unbounded_String (Inner);
            elsif Inner'Length >= 2 and then Inner (Inner'First) = '\'
              and then Decode_Escape (Inner, I, Value)
              and then I = Inner'Last + 1
            then
               null;  --  exactly one escape consumed
            else
               Syntax;
            end if;
         end;
         return;
      end if;
      if S (S'First) /= '"' or else S (S'Last) /= '"' then
         Syntax;
         return;
      end if;
      declare
         Inner : constant String := S (S'First + 1 .. S'Last - 1);
         I     : Integer := Inner'First;
      begin
         while I <= Inner'Last loop
            if Inner (I) = '\' then
               if not Decode_Escape (Inner, I, Value) then
                  Syntax;
                  return;
               end if;
            else
               Append (Value, Inner (I));
               I := I + 1;
            end if;
         end loop;
      end;
   end Unquote;

   overriding function Message (E : Num_Error) return String is
     ("strconv." & To_String (E.Func_Name) & ": parsing "
      & Quote (To_String (E.Num_Text)) & ": "
      & (if E.Err_Value = null then ""
         else Errors.Message (E.Err_Value.all)));

   overriding function Unwrap (E : Errors.Error_Access)
      return Errors.Error_Access is
     (Num_Error (E.all).Err_Value);

begin
   --  Go: var ErrSyntax = errors.New("invalid syntax"), etc.
   Err_Syntax := Errors.New_K ("invalid syntax");
   Err_Range  := Errors.New_K ("value out of range");
end Gada.Std.Strconv;
