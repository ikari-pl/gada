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

   function Encode_Rune (Rune : Integer) return String is
      --  Go's utf8.RuneError for anything that is not a scalar value.
      R : constant Natural :=
        (if Rune < 0 or else Rune > 16#10FFFF#
           or else Rune in 16#D800# .. 16#DFFF#
         then 16#FFFD# else Rune);
   begin
      if R < 16#80# then
         return (1 => Character'Val (R));
      elsif R < 16#800# then
         return (Character'Val (16#C0# + R / 16#40#),
                 Character'Val (16#80# + R mod 16#40#));
      elsif R < 16#10000# then
         return (Character'Val (16#E0# + R / 16#1000#),
                 Character'Val (16#80# + R / 16#40# mod 16#40#),
                 Character'Val (16#80# + R mod 16#40#));
      end if;
      return (Character'Val (16#F0# + R / 16#40000#),
              Character'Val (16#80# + R / 16#1000# mod 16#40#),
              Character'Val (16#80# + R / 16#40# mod 16#40#),
              Character'Val (16#80# + R mod 16#40#));
   end Encode_Rune;

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
               --  Go strings are UTF-8: \\u/\\U escapes encode it.
               Append (Value, Encode_Rune (V));
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

   --  Drops trailing (least significant) zero digits; the value
   --  digits x 10^(DP - Len) is unchanged because DP is absolute.
   procedure Trim (B : in out Big_Num; Len : in out Natural) is
      Z : Natural := 0;
   begin
      while Z < Len - 1 and then B (Z + 1) = 0 loop
         Z := Z + 1;
      end loop;
      if Z > 0 then
         B (1 .. Len - Z) := B (Z + 1 .. Len);
         Len := Len - Z;
      end if;
   end Trim;

   --  Exact decimal digits of M x 2^E (M > 0): B (1..Len) LSB-first,
   --  trailing zeros trimmed, with value = (digits) x 10^(DP - Len).
   --  Powers of 2 and 5 are applied in chunks (2^26 / 5^10) to keep the
   --  subnormal range (E down to -1076) cheap.
   procedure Exact_Mul (M : Long_Long_Integer; E : Integer;
                        B : out Big_Num; Len : out Natural;
                        DP : out Integer) is
      V : Long_Long_Integer := M;
      K : Natural := abs E;
   begin
      Len := 0;
      while V > 0 loop
         Len := Len + 1;
         B (Len) := Natural (V mod 10);
         V := V / 10;
      end loop;
      DP := Len;
      if E >= 0 then
         while K >= 26 loop
            Mul_Small (B, Len, 2**26);
            K := K - 26;
         end loop;
         Mul_Small (B, Len, 2**K);
         DP := Len;
      else
         --  M x 2^-K = M x 5^K x 10^-K.
         while K >= 10 loop
            Mul_Small (B, Len, 5**10);
            K := K - 10;
         end loop;
         Mul_Small (B, Len, 5**K);
         DP := Len + E;
      end if;
      Trim (B, Len);
   end Exact_Mul;

   --  Exact decimal digits of F (finite, >= 0): see Exact_Mul.
   procedure Exact_Digits (F : Long_Float; B : out Big_Num;
                           Len : out Natural; DP : out Integer) is
      M : Long_Long_Integer;
   begin
      M := Long_Long_Integer (Long_Float'Fraction (F) * 2.0**53);
      if M = 0 then
         B (1) := 0;
         Len := 1;
         DP := 1;
         return;
      end if;
      Exact_Mul (M, Long_Float'Exponent (F) - 53, B, Len, DP);
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

   --  IEEE-754 binary64 bit pattern of a Long_Float.
   function To_U64 is new Ada.Unchecked_Conversion (Long_Float, U64);

   --  Go's ftoa roundShortest: the shortest digit string that lies
   --  strictly inside (or, for an even mantissa, on the edge of) the
   --  rounding interval of F, computed exactly from the half-ulp
   --  neighbours' decimal expansions — no round trip through a parser.
   --  F >= 0 is finite; B/Len/DP are its exact (trimmed) digits. The
   --  result R/RN/RDP is trimmed, so RN is the shortest digit count.
   procedure Shortest (F : Long_Float; B : Big_Num; Len : Natural;
                       DP : Integer; R : out Big_Num; RN : out Natural;
                       RDP : out Integer) is
      Mant_Bits : constant := 52;
      Min_Exp   : constant := -1022;
      Bits      : constant U64 := To_U64 (F);
      Biased    : constant Integer :=
        Integer (Shift_Right (Bits, Mant_Bits) and 16#7FF#);
      Mant      : Long_Long_Integer :=
        Long_Long_Integer (Bits and (2**Mant_Bits - 1));
      Exp       : Integer := Biased - 1023;
      Up, Lo    : Big_Num;
      U_Len, L_Len : Natural;
      U_DP, L_DP   : Integer;
      Mant_Lo   : Long_Long_Integer;
      Exp_Lo    : Integer;
      Inclusive : Boolean;
      Upper_Delta : Natural := 0;
      UI        : Natural := 0;

      --  Go's d[i]: the I-th digit counted from the most significant.
      function Dig (X : Big_Num; N : Natural; I : Integer) return Natural is
        (X (N - I));

      procedure Keep_All is
      begin
         R (1 .. Len) := B (1 .. Len);
         RN := Len;
         RDP := DP;
      end Keep_All;

      --  Truncates to the N most significant digits, then adds one unit
      --  in the last kept place (Go's decimal RoundUp). In roundShortest
      --  that digit is never 9 — rounding up requires upper's digit to
      --  exceed d's there — so no carry chain can start; R (1) + 1 would
      --  raise if that ever failed. N = 0 means d sits just below a
      --  power of ten whose neighbourhood it owns (float64(1e23) =
      --  9.999999999999999e22 prints as "1e+23"): the result is that
      --  power.
      procedure Round_Up (N : Natural) is
      begin
         if N = 0 then
            R (1) := 1;
            RN := 1;
            RDP := DP + 1;
            return;
         end if;
         R (1 .. N) := B (Len - N + 1 .. Len);
         R (1) := R (1) + 1;
         RN := N;
         RDP := DP;
      end Round_Up;
   begin
      if Bits = 0 then
         Keep_All;
         return;
      end if;
      if Biased = 0 then
         Exp := Min_Exp;  --  subnormal
      else
         Mant := Mant + 2**Mant_Bits;
      end if;
      --  Go: the exact digits are already shortest when the decimal
      --  trailing zeros cover the ulp.
      if Exp > Min_Exp and then 332 * (DP - Len) >= 100 * (Exp - Mant_Bits)
      then
         Keep_All;
         return;
      end if;
      --  Upper and lower half-ulp neighbours. The lower gap halves when
      --  the mantissa is a power of two (except at the minimum exponent).
      Exact_Mul (2 * Mant + 1, Exp - Mant_Bits - 1, Up, U_Len, U_DP);
      if Mant > 2**Mant_Bits or else Exp = Min_Exp then
         Mant_Lo := Mant - 1;
         Exp_Lo := Exp;
      else
         Mant_Lo := 2 * Mant - 1;
         Exp_Lo := Exp - 1;
      end if;
      Exact_Mul (2 * Mant_Lo + 1, Exp_Lo - Mant_Bits - 1, Lo, L_Len, L_DP);
      --  Round half to even on parse: an even mantissa owns the edges.
      Inclusive := Mant mod 2 = 0;
      loop
         declare
            MI : constant Integer := UI - U_DP + DP;
            LI : constant Integer := UI - U_DP + L_DP;
            L, M, U : Natural := 0;
            Ok_Down, Ok_Up : Boolean;
         begin
            exit when MI >= Len;
            if LI >= 0 and then LI < L_Len then
               L := Dig (Lo, L_Len, LI);
            end if;
            if MI >= 0 then
               M := Dig (B, Len, MI);
            end if;
            if UI < U_Len then
               U := Dig (Up, U_Len, UI);
            end if;
            --  Rounding down is fine if lower differs from d here, or
            --  this is lower's last digit and the interval is closed.
            Ok_Down := L /= M or else (Inclusive and then LI + 1 = L_Len);
            --  Rounding up needs upper > d + 1 unit at this position.
            if Upper_Delta = 0 and then M + 1 < U then
               Upper_Delta := 2;
            elsif Upper_Delta = 0 and then M /= U then
               Upper_Delta := 1;
            elsif Upper_Delta = 1 and then (M /= 9 or else U /= 0) then
               Upper_Delta := 2;
            end if;
            Ok_Up := Upper_Delta > 0
              and then (Inclusive or else Upper_Delta > 1
                        or else UI + 1 < U_Len);
            if Ok_Down and then Ok_Up then
               Round_To (B, Len, DP, MI + 1, R, RN, RDP);  --  nearest
               Trim (R, RN);
               return;
            elsif Ok_Down then
               R (1 .. MI + 1) := B (Len - MI .. Len);  --  truncate
               RN := MI + 1;
               RDP := DP;
               Trim (R, RN);
               return;
            elsif Ok_Up then
               Round_Up (MI + 1);
               Trim (R, RN);
               return;
            end if;
         end;
         UI := UI + 1;
      end loop;
      Keep_All;
   end Shortest;

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
      --  Exact_Digits works on the magnitude (Long_Float'Fraction keeps
      --  the sign, which would leave the digit loop empty); Neg carries
      --  the sign into the formatters.
      Exact_Digits (abs F, B, Len, DP);
      case Fmt is
         when 'f' | 'F' =>
            if Prec < 0 then
               Shortest (abs F, B, Len, DP, R, RN, RDP);
               return Fmt_F (Neg, R, RN, RDP, Natural'Max (0, RN - RDP));
            end if;
            Round_At (B, Len, DP, Prec, R, RN, RDP);
            return Fmt_F (Neg, R, RN, RDP, Prec);
         when 'e' | 'E' =>
            if Prec < 0 then
               Shortest (abs F, B, Len, DP, R, RN, RDP);
               return Fmt_E (Neg, R, RN, RDP, RN - 1, Fmt = 'E');
            end if;
            Round_To (B, Len, DP, Natural'Max (1, Prec + 1), R, RN, RDP);
            return Fmt_E (Neg, R, RN, RDP, Natural'Max (1, Prec + 1) - 1,
                          Fmt = 'E');
         when others =>  --  'g'/'G' (and anything else, like Go's default)
            declare
               Short_Mode : constant Boolean := Prec < 0;
               K          : Natural := (if Prec <= 0 then 1 else Prec);
               Exp10      : Integer;
               Eprec      : Natural;
               Nd         : Natural;
            begin
               if Short_Mode then
                  Shortest (abs F, B, Len, DP, R, RN, RDP);
                  K := RN;
               else
                  Round_To (B, Len, DP, K, R, RN, RDP);
               end if;
               Exp10 := RDP - 1;
               --  Significant digits, trailing zeros stripped (R is
               --  LSB-first, so trailing zeros sit at low indices).
               Nd := RN;
               while Nd > 1 and then R (RN - Nd + 1) = 0 loop
                  Nd := Nd - 1;
               end loop;
               Eprec := K;
               if Short_Mode then
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

   --  Length of the valid UTF-8 sequence starting at S (I), or 0 when
   --  the bytes there are not valid UTF-8 (Go's utf8.DecodeRune rules:
   --  no overlongs, no surrogates, nothing above U+10FFFF).
   function Utf8_Len (S : String; I : Integer) return Natural is
      B0 : constant Natural := Character'Pos (S (I));
      N  : constant Natural :=
        (case B0 is
            when 16#C2# .. 16#DF# => 2,
            when 16#E0# .. 16#EF# => 3,
            when 16#F0# .. 16#F4# => 4,
            when others           => 0);
      --  Allowed range of the second byte (Go's acceptRanges).
      Lo : constant Natural :=
        (case B0 is
            when 16#E0# => 16#A0#,
            when 16#F0# => 16#90#,
            when others => 16#80#);
      Hi : constant Natural :=
        (case B0 is
            when 16#ED# => 16#9F#,
            when 16#F4# => 16#8F#,
            when others => 16#BF#);
   begin
      if N = 0 or else I + N - 1 > S'Last
        or else Character'Pos (S (I + 1)) not in Lo .. Hi
      then
         return 0;
      end if;
      for K in 2 .. N - 1 loop
         if Character'Pos (S (I + K)) not in 16#80# .. 16#BF# then
            return 0;
         end if;
      end loop;
      return N;
   end Utf8_Len;

   --  Shared core: quotes S with the given delimiter, escaping the
   --  delimiter itself, the backslash, and control chars (Go's Quote
   --  and QuoteRune differ only in the delimiter). Valid UTF-8 passes
   --  through, except the C1 controls U+0080..U+009F (\u00XX); every
   --  byte that is not part of valid UTF-8 becomes \xNN, like Go.
   function Quote_Core (S : String; Delim : Character) return String is
      B : Unbounded_String;
      I : Integer := S'First;
   begin
      Append (B, Delim);
      while I <= S'Last loop
         declare
            C : constant Character := S (I);
            N : Natural := 1;
         begin
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
               when Character'Val (16#80#) .. Character'Val (16#FF#) =>
                  N := Utf8_Len (S, I);
                  if N = 0 then
                     N := 1;
                     Append (B, "\x" & Hex2 (C));
                  elsif C = Character'Val (16#C2#)
                    and then S (I + 1) <= Character'Val (16#9F#)
                  then
                     Append (B, "\u00" & Hex2 (S (I + 1)));
                  else
                     Append (B, S (I .. I + N - 1));
                  end if;
               when others =>
                  if C = Delim then
                     Append (B, BSLASH & Delim);
                  elsif C < ' ' or else C = Character'Val (127) then
                     Append (B, "\x" & Hex2 (C));
                  else
                     Append (B, C);
                  end if;
            end case;
            I := I + N;
         end;
      end loop;
      Append (B, Delim);
      return To_String (B);
   end Quote_Core;

   function Quote (S : String) return String is
     (Quote_Core (S, DQUOTE));

   --  A Character is a code point here (Go's rune): bytes >= 16#80#
   --  quote as their UTF-8 encoding, e.g. Character'Val (16#E9#) is 'é'.
   function Quote_Rune (C : Character) return String is
     (Quote_Core (Encode_Rune (Character'Pos (C)), SQUOTE));

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
