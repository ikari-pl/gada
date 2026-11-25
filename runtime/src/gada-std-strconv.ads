--  Gada.Std.Strconv — the Go `strconv` package, ported (Phase 5 wave 1).
--
--  Go `int` maps to Ada Integer and Go `float64` to Long_Float (the
--  compiler's fixed mapping), so Itoa/Atoi use Integer and the float
--  functions use Long_Float (IEEE-754 binary64 on the GNAT targets we
--  build for). Special float values follow Go's exact spellings:
--  "NaN", "+Inf", "-Inf".
--
--  Errors follow Go's *NumError shape: a tagged type deriving from
--  Gada.Std.Errors.Error whose Unwrap returns the sentinel Err_Syntax /
--  Err_Range, so errors.Is(err, strconv.ErrSyntax) works exactly like
--  Go. Go name mapping (compiler's goNameToAdaMember): ErrSyntax →
--  Err_Syntax, NumError → Num_Error, FormatFloat → Format_Float, …
--
--  v1 limitations (docs/imperfections.md): strings are byte strings, so
--  Quote/Unquote treat bytes >= 16#80# as printable and pass them
--  through (no UTF-8 validation); Unquote's \u/\U escapes still encode
--  proper UTF-8. Parse_Float rejects Go's underscore digit separators
--  and hex float literals. Format_Float supports 'f'/'F', 'e'/'E' and
--  'g'/'G' ('g' with prec < 0 gives Go's shortest round-trip digits,
--  choosing 'e' when the exponent is < -4 or >= 6, exactly like Go).

with Ada.Strings.Unbounded;
with Gada.Std.Errors;

package Gada.Std.Strconv is

   --  Go: var ErrSyntax = errors.New("invalid syntax")
   --      var ErrRange  = errors.New("value out of range")
   --  Package-level variables (not constants) so access identity —
   --  what errors.Is compares — is stable, matching Go's sentinels.
   Err_Syntax : Gada.Std.Errors.Error_Access;
   Err_Range  : Gada.Std.Errors.Error_Access;

   --  Go: type NumError struct { Func, Num string; Err error }
   type Num_Error is new Gada.Std.Errors.Error with private;

   --  Builds a Num_Error (returned as the class-wide Error_Access).
   function New_Num_Error
     (Func, Num : String; Err : Gada.Std.Errors.Error_Access)
      return Gada.Std.Errors.Error_Access;

   --  NumError field accessors (Go's e.Func / e.Num / e.Err).
   function Func (E : Num_Error) return String;
   function Num  (E : Num_Error) return String;
   function Err  (E : Num_Error) return Gada.Std.Errors.Error_Access;

   --  Go: func (e *NumError) Error() string —
   --  "strconv." + Func + ": parsing " + Quote(Num) + ": " + Err.Error()
   overriding function Message (E : Num_Error) return String;

   --  Go: func (e *NumError) Unwrap() error { return e.Err }
   overriding function Unwrap (E : Gada.Std.Errors.Error_Access)
      return Gada.Std.Errors.Error_Access;

   --  Go: func Itoa(i int) string
   function Itoa (I : Integer) return String;

   --  Go: func Atoi(s string) (int, error) — base 10, optional sign,
   --  no whitespace/underscores. Range errors clamp to Integer'First /
   --  Integer'Last and report Err_Range (Go's behavior).
   procedure Atoi (S : String; Value : out Integer;
                   Err : out Gada.Std.Errors.Error_Access);

   --  Go: func FormatFloat(f float64, fmt byte, prec, bitSize int) string
   --  v1 drops bitSize (always 64) and supports fmt 'f'/'F', 'e'/'E',
   --  'g'/'G'. prec < 0 = shortest digit count that round-trips.
   function Format_Float (F : Long_Float; Fmt : Character := 'g';
                          Prec : Integer := -1) return String;

   --  Go: func ParseFloat(s string) (float64, error) — accepts "NaN",
   --  "Inf"/"Infinity" (any case, optional sign) and decimal floats with
   --  exponent. Overflow yields ±Inf with Err_Range (Go semantics).
   procedure Parse_Float (S : String; Value : out Long_Float;
                          Err : out Gada.Std.Errors.Error_Access);

   --  Go: func Quote(s string) string — double-quoted Go literal with
   --  \a \b \f \n \r \t \v \\ \" and \xNN for other control bytes.
   function Quote (S : String) return String;

   --  Go: func Unquote(s string) (string, error) — accepts double-quoted
   --  (escapes processed), backquoted raw (no escapes) and single-quoted
   --  char literals. Value is Unbounded_String because the result length
   --  is not known statically (same reason []string uses vectors).
   procedure Unquote (S : String;
                      Value : out Ada.Strings.Unbounded.Unbounded_String;
                      Err : out Gada.Std.Errors.Error_Access);

private

   type Num_Error is new Gada.Std.Errors.Error with record
      Func_Name : Ada.Strings.Unbounded.Unbounded_String;
      Num_Text  : Ada.Strings.Unbounded.Unbounded_String;
      Err_Value : Gada.Std.Errors.Error_Access;
   end record;

end Gada.Std.Strconv;
