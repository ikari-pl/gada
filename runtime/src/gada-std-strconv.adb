--  Body of Gada.Std.Strconv — see spec for the Go-semantics contract.
--
--  Ada 2022 idioms used: expression functions for the one-liners,
--  conditional expressions, `for C of S` array iteration, numeric
--  literals with underscores.
--
--  Float formatting does not use Ada.*_Text_IO's Put (its string form is
--  not available for Long_Float): every finite binary64 is an exact
--  finite decimal (m × 2^e), so we compute the exact decimal digits with
--  a small bignum (digit array) and round half-to-even ourselves. That
--  gives Go-exact output, including shortest round-trip ('g', prec < 0)
--  and denormals.

with Ada.Characters.Handling;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with Interfaces;
with Gada.Std.Errors;

package body Gada.Std.Strconv is

   package Errors renames Gada.Std.Errors;

   use type Errors.Error_Access;

   --  IEEE-754 binary64 special values, built from their bit patterns
   --  (the portable spelling — Ada has no standard NaN/Inf literals).
   type U64 is new Interfaces.Unsigned_64;
   function To_Float is new Ada.Unchecked_Conversion (U64, Long_Float);

   Inf_Float : constant Long_Float := To_Float (16#7FF0_0000_0000_0000#);
   NaN_Float : constant Long_Float := To_Float (16#7FF8_0000_0000_0000#);

   Hex_Digits : constant String := "0123456789abcdef";

   --  Named constants for the delimiter characters (the four-apostrophe
   --  character literal is spelled by code point).
   DQUOTE : constant Character := Character'Val (34);
   SQUOTE : constant Character := Character'Val (39);
   BSLASH : constant Character := Character'Val (92);

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
         when BSLASH => Append (Value, BSLASH);          I := I + 2;
         when DQUOTE => Append (Value, DQUOTE);          I := I + 2;
         when SQUOTE => Append (Value, SQUOTE);          I := I + 2;
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

   ---------------------------------------------------------------
   --  Exact decimal representation of a finite Long_Float
   ---------------------------------------------------------------

   --  M × 5^1126 has at most ~803 decimal digits; leave headroom.
   Max_Big : constant := 1100;

   --  Decimal digits, least significant first.
   type Big_Num is array (1 .. Max_Big) of Natural range 0 .. 9;

   procedure Mul_Small (B : in out Big_Num; Len : in out Natural;
                        M : Natural) is
      Carry : Natural := 0;
   begin
      for I in 1 .. Len loop
         declare
            V : constant Natural := B (I) * M + Carry;
         begin
            B (I) := V mod 10;
            Carry := V / 10;
         end;
      end loop;
      while Carry > 0 loop
         Len := Len + 1;
         B (Len) := Carry mod 10;
         Carry := Carry / 10;
      end loop;
   end Mul_Small;

   --  Exact decimal digits of |F|: B (1..Len) LSB-first, and DP with
   --  |F| = (digits) × 10^(DP - Len).  F must be finite and nonzero.
   procedure Exact_Digits (F : Long_Float; B : out Big_Num;
                           Len : out Natural; DP : out Integer) is
      M : Long_Long_Integer :=
        Long_Long_Integer (Long_Float'Fraction (F) * 2.0**53);
      E : constant Integer := Long_Float'Exponent (F) - 53;
   begin
      if M = 0 then
         B (1) := 0;
         Len := 1;
         DP := 1;
         return;
      end if;
      Len := 0;
      while M > 0 loop
         Len := Len + 1;
         B (Len) := Natural (M mod 10);
         M := M / 10;
      end loop;
      if E >= 0 then
         for I in 1 .. E loop
            Mul_Small (B, Len, 2);
         end loop;
         DP := Len;
      else
         for I in 1 .. (-E) loop
            Mul_Small (B, Len, 5);
         end loop;
         DP := Len + E;
      end if;
   end Exact_Digits;

   --  Rounds the exact digits to N significant digits (round half to
   --  even on the exact remainder). R is LSB-first, value =
   --  (R digits) × 10^(RDP - RN).
   procedure Round_To (B : Big_Num; Len : Natural; DP : Integer;
                       N : Natural; R : out Big_Num; RN : out Natural;
                       RDP : out Integer) is
   begin
      if Len <= N then
         RN := Len;
         R (1 .. Len) := B (1 .. Len);
         RDP := DP;
         return;
      end if;
      RN := N;
      for I in 1 .. N loop
         R (I) := B (Len - N + I);
      end loop;
      RDP := DP;
      declare
         Top    : constant Natural := B (Len - N);
         Lower  : Boolean := False;
      begin
         for I in 1 .. Len - N - 1 loop
            if B (I) /= 0 then
               Lower := True;
            end if;
         end loop;
         --  Round up if the dropped part exceeds half, or is exactly
         --  half and the kept LSB is odd (round half to even).
         --  R is LSB-first, so the least significant *kept* digit is
         --  R (1); round half to even tests that one, not the MSB.
         if Top > 5
           or else (Top = 5 and then (Lower or else R (1) mod 2 = 1))
         then
            declare
               Carry : Natural := 1;
            begin
               for I in 1 .. RN loop
                  declare
                     V : constant Natural := R (I) + Carry;
                  begin
                     R (I) := V mod 10;
                     Carry := V / 10;
                  end;
                  exit when Carry = 0;
               end loop;
               if Carry > 0 then
                  --  999…9 rounds up to 1000…0: R is LSB-first, so the
                  --  carry out becomes a new most significant digit.
                  R (RN + 1) := Carry;
                  RN := RN + 1;
                  RDP := RDP + 1;
               end if;
            end;
         end if;
      end;
   end Round_To;

   --  Rounds the exact digits at the 10^-Aft position ('f' with an
   --  explicit precision): keeps DP + Aft digits when that is >= 1,
   --  otherwise the result is 0 or 10^-Aft (round half to even).
   procedure Round_At (B : Big_Num; Len : Natural; DP : Integer;
                       Aft : Natural; R : out Big_Num; RN : out Natural;
                       RDP : out Integer) is
   begin
      if DP + Aft >= 1 then
         Round_To (B, Len, DP, DP + Aft, R, RN, RDP);
         return;
      end if;
      RDP := 1 - Aft;
      RN  := 1;
      declare
         Lower : Boolean := False;
      begin
         for I in 1 .. Len - 1 loop
            if B (I) /= 0 then
               Lower := True;
            end if;
         end loop;
         --  B (Len) is the MSB at place 10^(DP-1); it is the first
         --  dropped digit only when DP + Aft = 0. When DP + Aft < 0
         --  the digit at 10^-Aft is an implicit 0 and the value is
         --  below half a unit: always round down.
         if DP + Aft = 0
           and then (B (Len) > 5 or else (B (Len) = 5 and then Lower))
         then
            R (1) := 1;  --  round up to 10^-Aft (kept 0 is even: ties down)
         else
            R (1) := 0;
         end if;
      end;
   end Round_At;

   procedure Append_Digit (S : in out Unbounded_String; D : Natural) is
   begin
      Append (S, Character'Val (Character'Pos ('0') + D));
   end Append_Digit;

   --  Scientific form d.ddde±dd of rounded digits R (LSB-first, value =
   --  digits × 10^(RDP-RN)), with exactly Aft digits after the point.
   function Fmt_E (Neg : Boolean; R : Big_Num; RN : Natural;
                   RDP : Integer; Aft : Natural; Upper : Boolean)
      return String is
      S   : Unbounded_String;
      Exp : constant Integer := RDP - 1;
   begin
      if Neg then
         Append (S, '-');
      end if;
      Append_Digit (S, R (RN));           --  leading digit
      if Aft > 0 then
         Append (S, '.');
         for K in 1 .. Aft loop
            if RN - K >= 1 then
               Append_Digit (S, R (RN - K));
            else
               Append (S, '0');
            end if;
         end loop;
      end if;
      Append (S, (if Upper then 'E' else 'e'));
      if Exp < 0 then
         Append (S, '-');
      else
         Append (S, '+');
      end if;
      declare
         A : constant Natural := (if Exp < 0 then -Exp else Exp);
      begin
         if A < 10 then
            Append (S, '0');
         end if;
         Append (S, Ada.Strings.Fixed.Trim (Integer'Image (A),
                                            Ada.Strings.Left));
      end;
      return To_String (S);
   end Fmt_E;

   --  Fixed form of rounded digits R with exactly Aft digits after the
   --  point (padded with zeros; never truncated — callers round first).
   function Fmt_F (Neg : Boolean; R : Big_Num; RN : Natural;
                   RDP : Integer; Aft : Natural) return String is
      S : Unbounded_String;
   begin
      if Neg then
         Append (S, '-');
      end if;
      if RDP <= 0 then
         Append (S, "0.");
         for K in 1 .. (-RDP) loop
            Append (S, '0');
         end loop;
         for I in reverse 1 .. RN loop
            Append_Digit (S, R (I));
         end loop;
         for K in 1 .. Aft - RN + RDP loop  --  may be a null range
            Append (S, '0');
         end loop;
      elsif RDP >= RN then
         for I in reverse 1 .. RN loop
            Append_Digit (S, R (I));
         end loop;
         for K in 1 .. (RDP - RN) loop
            Append (S, '0');
         end loop;
         if Aft > 0 then
            Append (S, '.');
            for K in 1 .. Aft loop
               Append (S, '0');
            end loop;
         end if;
      else
         --  Integer part: digits R (RN) .. R (RN - RDP + 1), MSB first;
         --  fraction: R (RN - RDP) .. R (1), MSB first.
         for I in reverse (RN - RDP + 1) .. RN loop
            Append_Digit (S, R (I));
         end loop;
         Append (S, '.');
         for I in reverse 1 .. (RN - RDP) loop
            Append_Digit (S, R (I));
         end loop;
         for K in 1 .. Aft - (RN - RDP) loop
            Append (S, '0');
         end loop;
      end if;
      return To_String (S);
   end Fmt_F;

   --  Smallest number of significant digits (1..17) whose decimal
   --  representation round-trips to F — Go's shortest for prec < 0.
   function Shortest_K (Neg : Boolean; F : Long_Float; B : Big_Num;
                        Len : Natural; DP : Integer) return Natural is
      R   : Big_Num;
      RN  : Natural;
      RDP : Integer;
   begin
      for K in 1 .. 17 loop
         Round_To (B, Len, DP, K, R, RN, RDP);
         if Long_Float'Value (Fmt_E (Neg, R, RN, RDP, K - 1, True)) = F then
            return K;
         end if;
      end loop;
      return 17;
   end Shortest_K;

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
      Base : Errors.Error;
   begin
      Errors.Make_Base (Base, "", Err);
      return new Num_Error'(Base with
                            Func_Name => To_Unbounded_String (Func),
                            Num_Text  => To_Unbounded_String (Num),
                            Err_Value => Err);
   end New_Num_Error;

   function Func (E : Num_Error) return String is
     (To_String (E.Func_Name));

   function Num (E : Num_Error) return String is
     (To_String (E.Num_Text));

   function Err (E : Num_Error) return Errors.Error_Access is
     (E.Err_Value);

   --  True for negative zero (sign bit set, value zero).
   function Is_Neg_Zero (F : Long_Float) return Boolean is
      function To_U64 is new Ada.Unchecked_Conversion (Long_Float, U64);
   begin
      return F = 0.0
        and then (To_U64 (F) and 16#8000_0000_0000_0000#) /= 0;
   end Is_Neg_Zero;

   function Itoa (I : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (I), Ada.Strings.Left));

   procedure Atoi (S : String; Value : out Integer;
                   Err : out Errors.Error_Access) is
      I        : Integer := S'First;
      Neg      : Boolean := False;
      Acc      : Long_Integer := 0;
      N_Dig    : Natural := 0;
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
         N_Dig := N_Dig + 1;
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
      if N_Dig = 0 or else I <= S'Last then
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
      Neg : Boolean := F < 0.0;
      B   : Big_Num;
      Len : Natural;
      DP  : Integer;
      R   : Big_Num;
      RN  : Natural;
      RDP : Integer;
   begin
      if F /= F then
         return "NaN";
      elsif F > Long_Float'Last then
         return "+Inf";
      elsif F < Long_Float'First then
         return "-Inf";
      end if;
      if F = 0.0 and then Is_Neg_Zero (F) then
         Neg := True;
      end if;
      Exact_Digits (F, B, Len, DP);
      case Fmt is
         when 'f' | 'F' =>
            if Prec < 0 then
               declare
                  K : constant Natural :=
                    Shortest_K (Neg, F, B, Len, DP);
               begin
                  Round_To (B, Len, DP, K, R, RN, RDP);
                  return Fmt_F (Neg, R, RN, RDP,
                                Natural'Max (0, K - RDP));
               end;
            end if;
            Round_At (B, Len, DP, Prec, R, RN, RDP);
            return Fmt_F (Neg, R, RN, RDP, Prec);
         when 'e' | 'E' =>
            declare
               K : constant Natural :=
                 (if Prec < 0 then Shortest_K (Neg, F, B, Len, DP)
                  else Natural'Max (1, Prec + 1));
            begin
               Round_To (B, Len, DP, K, R, RN, RDP);
               return Fmt_E (Neg, R, RN, RDP, K - 1, Fmt = 'E');
            end;
         when others =>  --  'g'/'G' (and anything else, like Go's default)
            declare
               Shortest : constant Boolean := Prec < 0;
               K        : constant Natural :=
                 (if Shortest then Shortest_K (Neg, F, B, Len, DP)
                  elsif Prec = 0 then 1
                  else Prec);
               Exp10    : Integer;
               Eprec    : Natural;
               Nd       : Natural;
            begin
               Round_To (B, Len, DP, K, R, RN, RDP);
               Exp10 := RDP - 1;
               --  Significant digits, trailing zeros stripped (R is
               --  LSB-first, so trailing zeros sit at low indices).
               Nd := RN;
               while Nd > 1 and then R (RN - Nd + 1) = 0 loop
                  Nd := Nd - 1;
               end loop;
               Eprec := K;
               if Shortest then
                  Eprec := 6;
               elsif Eprec > Nd and then Nd >= Exp10 + 1 then
                  Eprec := Nd;
               end if;
               if Exp10 < -4 or else Exp10 >= Eprec then
                  return Fmt_E (Neg, R, RN, RDP,
                                Natural'Min (K, Nd) - 1, Fmt = 'G');
               end if;
               begin
                  --  'g' strips trailing zeros; R is LSB-first, so they
                  --  sit at low indices. Compact to Nd significant digits
                  --  (Fmt_F pads back up to the requested Aft).
                  if Nd < RN then
                     for I in 1 .. Nd loop
                        R (I) := R (RN - Nd + I);
                     end loop;
                     RN := Nd;
                  end if;
                  return Fmt_F (Neg, R, RN, RDP,
                                Natural'Max (0, Nd - 1 - Exp10));
               end;
            end;
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
         Core : constant String :=
           (if S (S'First) = '+' or else S (S'First) = '-'
            then S (S'First + 1 .. S'Last)
            else S);
         Neg  : constant Boolean := S (S'First) = '-';
      begin
         --  Go accepts only unsigned "nan"; the sign is allowed for
         --  inf/infinity alone.
         if S (S'First) /= '+' and then S (S'First) /= '-'
           and then Equal_Ignore_Case (Core, "nan")
         then
            Value := NaN_Float;
            return;
         end if;
         if Equal_Ignore_Case (Core, "inf")
           or else Equal_Ignore_Case (Core, "infinity")
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

   --  Shared core: quotes S with the given delimiter, escaping the
   --  delimiter itself, the backslash, and control chars (Go's Quote
   --  and QuoteRune differ only in the delimiter).
   function Quote_Core (S : String; Delim : Character) return String is
      B : Unbounded_String;
   begin
      Append (B, Delim);
      for C of S loop
         case C is
            when BSLASH =>
               Append (B, BSLASH & BSLASH);     --  \\
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
               if C = Delim then
                  Append (B, BSLASH & Delim);
               elsif C < ' ' or else C = Character'Val (127) then
                  Append (B, "\x" & Hex2 (C));
               else
                  Append (B, C);
               end if;
         end case;
      end loop;
      Append (B, Delim);
      return To_String (B);
   end Quote_Core;

   function Quote (S : String) return String is
     (Quote_Core (S, DQUOTE));

   function Quote_Rune (C : Character) return String is
     (Quote_Core (String'(1 => C), Character'Val (39)));

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
      if S (S'First) = SQUOTE then
         --  Char literal: exactly one character or one escape sequence.
         if S (S'Last) /= SQUOTE then
            Syntax;
            return;
         end if;
         declare
            Inner : constant String := S (S'First + 1 .. S'Last - 1);
            I     : Integer := Inner'First;
         begin
            if Inner'Length = 1 then
               Value := To_Unbounded_String (Inner);
            elsif Inner'Length >= 2 and then Inner (Inner'First) = BSLASH
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
      if S (S'First) /= DQUOTE or else S (S'Last) /= DQUOTE then
         Syntax;
         return;
      end if;
      declare
         Inner : constant String := S (S'First + 1 .. S'Last - 1);
         I     : Integer := Inner'First;
      begin
         while I <= Inner'Last loop
            if Inner (I) = BSLASH then
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
   begin
      --  Regular body (not an expression function): gcov/lcov record
      --  expression-function bodies inconsistently ("function hit but no
      --  contained lines"), which breaks the coverage gate.
      return "strconv." & To_String (E.Func_Name) & ": parsing "
        & Quote (To_String (E.Num_Text)) & ": "
        & (if E.Err_Value = null then ""
           else Errors.Message (E.Err_Value.all));
   end Message;

begin
   --  Go: var ErrSyntax = errors.New("invalid syntax"), etc.
   Err_Syntax := Errors.New_K ("invalid syntax");
   Err_Range  := Errors.New_K ("value out of range");
end Gada.Std.Strconv;
