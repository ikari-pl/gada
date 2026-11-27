--  Gada.Std.Fmt — the Go `fmt` package, ported (Phase 5 wave 1).
--
--  Go's variadic ...any becomes Arg_Array: a heterogeneous argument is
--  an Arg (a variant record over Integer / Long_Float / String /
--  Boolean / Character / pointer address / error), built with the A
--  constructor overloads. The supported verb/flag set is documented in
--  docs/fmt_verb_support.md.
--
--  Sprintf is the engine; Print/Println/Printf write to standard output
--  (via Gada.Core.IO), Errorf builds an error value (%w wraps it as the
--  cause, Go 1.13 semantics), Sscanf parses a string back into a
--  pre-sized Arg_Array whose kinds the caller fixes (matching the
--  format's verbs).

with Ada.Strings.Unbounded;
with System;
with Gada.Std.Errors;

package Gada.Std.Fmt is

   type Arg_Kind is
     (Int_Arg, Float_Arg, Str_Arg, Bool_Arg, Char_Arg, Ptr_Arg, Err_Arg);

   type Arg (K : Arg_Kind := Str_Arg) is record
      case K is
         when Int_Arg   => I : Integer;
         when Float_Arg => F : Long_Float;
         when Str_Arg   => S : Ada.Strings.Unbounded.Unbounded_String;
         when Bool_Arg  => B : Boolean;
         when Char_Arg  => C : Character;
         when Ptr_Arg   => P : System.Address;
         when Err_Arg   => E : Gada.Std.Errors.Error_Access;
      end case;
   end record;

   type Arg_Array is array (Positive range <>) of Arg;

   function A (I : Integer) return Arg;
   function A (F : Long_Float) return Arg;
   function A (S : String) return Arg;
   function A (B : Boolean) return Arg;
   function A (C : Character) return Arg;
   function A (P : System.Address) return Arg;
   function A (E : Gada.Std.Errors.Error_Access) return Arg;

   --  Go: func Sprintf(format string, a ...any) string
   function Sprintf (Format : String; Args : Arg_Array) return String;

   --  Go: Print / Println / Printf — to standard output.
   procedure Print (Args : Arg_Array);
   procedure Println (Args : Arg_Array);
   procedure Printf (Format : String; Args : Arg_Array);

   --  Go: func Errorf(format string, a ...any) error — %w wraps.
   function Errorf (Format : String; Args : Arg_Array)
      return Gada.Std.Errors.Error_Access;

   --  Go: func Sscanf(str, format string, a ...any) (n int, err error)
   --  v1: Args is pre-sized with the expected kinds; N is the number of
   --  items parsed; Err is No_Error on success.
   procedure Sscanf (S, Format : String; Args : in out Arg_Array;
                     N : out Natural;
                     Err : out Gada.Std.Errors.Error_Access);

end Gada.Std.Fmt;
