--  Acc of Gada.Std.Fmt — see spec and docs/fmt_verb_support.md.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Unchecked_Conversion;
with Interfaces;
with Gada.Core.IO;
with Gada.Std.Errors;
with Gada.Std.Strconv;
with Gada.Std.Strings;

package body Gada.Std.Fmt is

   package Errors renames Gada.Std.Errors;
   package Strconv renames Gada.Std.Strconv;
   package Strings renames Gada.Std.Strings;

   use type Errors.Error_Access;

   type U64 is new Interfaces.Unsigned_64;
   function To_U64 is new Ada.Unchecked_Conversion (System.Address, U64);

   Hex_Lower : constant String := "0123456789abcdef";
   Hex_Upper : constant String := "0123456789ABCDEF";

   function A (I : Integer) return Arg is (Int_Arg, I);
   function A (F : Long_Float) return Arg is (Float_Arg, F);
   function A (S : String) return Arg is
     (Str_Arg, To_Unbounded_String (S));
   function A (B : Boolean) return Arg is (Bool_Arg, B);
   function A (C : Character) return Arg is (Char_Arg, C);
   function A (P : System.Address) return Arg is (Ptr_Arg, P);
   function A (E : Errors.Error_Access) return Arg is (Err_Arg, E);

   --  One parsed format specification: %[flags][width][.prec]verb
   type Spec is record
      Minus, Plus, Space, Hash, Zero : Boolean := False;
      Width : Natural := 0;
      Prec  : Integer := -1;  --  -1 = no precision given
      Verb  : Character := '%';
   end record;

   --  Parses a spec starting at F (I) = '%'; advances I past the verb.
   procedure Parse_Spec (F : String; I : in out Integer; Sp : out Spec) is
   begin
      Sp := (others => <>);
      I := I + 1;  --  skip '%'
      while I <= F'Last and then F (I) in '-' | '+' | ' ' | '#' | '0' loop
         case F (I) is
            when '-' => Sp.Minus := True;
            when '+' => Sp.Plus := True;
            when ' ' => Sp.Space := True;
            when '#' => Sp.Hash := True;
            when '0' => Sp.Zero := True;
            when others => null;
         end case;
         I := I + 1;
      end loop;
      while I <= F'Last and then F (I) in '0' .. '9' loop
         Sp.Width := Sp.Width * 10
           + Character'Pos (F (I)) - Character'Pos ('0');
         I := I + 1;
      end loop;
      if I <= F'Last and then F (I) = '.' then
         I := I + 1;
         Sp.Prec := 0;
         while I <= F'Last and then F (I) in '0' .. '9' loop
            Sp.Prec := Sp.Prec * 10
              + Character'Pos (F (I)) - Character'Pos ('0');
            I := I + 1;
         end loop;
      end if;
      if I <= F'Last then
         Sp.Verb := F (I);
         I := I + 1;
      end if;
   end Parse_Spec;

   function Int_Base (V : Long_Integer; Base : Natural;
                      Upper : Boolean) return String is
      Digs : constant String := (if Upper then Hex_Upper else Hex_Lower);
      B      : Unbounded_String;
      M      : Long_Integer := V;
   begin
      if M = 0 then
         return "0";
      end if;
      while M > 0 loop
         Append (B, Digs (1 + Natural (M mod Base)));
         M := M / Base;
      end loop;
      --  B is LSB-first; reverse it.
      declare
         S : constant String := To_String (B);
         R : String (S'Range);
      begin
         for I in S'Range loop
            R (S'Last - I + S'First) := S (I);
         end loop;
         return R;
      end;
   end Int_Base;

   function Hex_Addr (P : System.Address) return String is
      V : constant U64 := To_U64 (P);
   begin
      if V = 0 then
         return "0x0";
      end if;
      return "0x" & Int_Base (Long_Integer (V), 16, False);
   end Hex_Addr;

   function Bool_Text (B : Boolean) return String is
     (if B then "true" else "false");

   --  Pads Acc to Sp.Width (space or zero padding, sign-aware for
   --  Zero_Pad when Sign_Pos > 0).
   function Pad (Acc : String; Sp : Spec; Numeric : Boolean;
                 Sign_Pos : Natural := 0) return String is
      N : constant Natural := Sp.Width;
   begin
      if Acc'Length >= N then
         return Acc;
      end if;
      declare
         Fill : constant Natural := N - Acc'Length;
      begin
         if Sp.Minus then
            return Acc & (1 .. Fill => ' ');
         elsif Sp.Zero and then Numeric then
            --  Zero-pad after any sign/prefix.
            if Sign_Pos > 0 then
               return Acc (Acc'First .. Sign_Pos)
                 & (1 .. Fill => '0')
                 & Acc (Sign_Pos + 1 .. Acc'Last);
            end if;
            return (1 .. Fill => '0') & Acc;
         end if;
         return (1 .. Fill => ' ') & Acc;
      end;
   end Pad;

   --  Formats one argument per the spec; Bad is set for a verb that
   --  does not apply to the argument kind.
   function Format_Arg (X : Arg; Sp : Spec; Bad : out Boolean) return String
   is
      use Strconv;
   begin
      Bad := False;
      case X.K is
         when Int_Arg =>
            declare
               V    : constant Long_Integer := Long_Integer (X.I);
               Neg  : constant Boolean := V < 0;
               Mag  : constant Long_Integer := (if Neg then -V else V);
               Sign : constant String :=
                 (if Neg then "-"
                  elsif Sp.Plus then "+"
                  elsif Sp.Space then " "
                  else "");
               Acc : Unbounded_String;
            begin
               case Sp.Verb is
                  when 'd' | 'v' =>
                     Append (Acc, Int_Base (Mag, 10, False));
                  when 'b' =>
                     if Sp.Hash then Append (Acc, "0b"); end if;
                     Append (Acc, Int_Base (Mag, 2, False));
                  when 'o' =>
                     if Sp.Hash then Append (Acc, "0o"); end if;
                     Append (Acc, Int_Base (Mag, 8, False));
                  when 'x' =>
                     if Sp.Hash then Append (Acc, "0x"); end if;
                     Append (Acc, Int_Base (Mag, 16, False));
                  when 'X' =>
                     if Sp.Hash then Append (Acc, "0X"); end if;
                     Append (Acc, Int_Base (Mag, 16, True));
                  when 'c' =>
                     return Pad (String'(1 => Character'Val (X.I)),
                                 Sp, False);
                  when others =>
                     Bad := True;
                     return "%!" & Sp.Verb & "(BADVERB)";
               end case;
               declare
                  S    : constant String := Sign & To_String (Acc);
                  --  Zero padding goes after the sign and any base
                  --  prefix (Go: %#08x of 255 is 0x0000ff).
                  Plen : constant Natural :=
                    (if Sp.Hash and then Sp.Verb in 'b' | 'o' | 'x' | 'X'
                     then 2 else 0);
               begin
                  return Pad (S, Sp, True, Sign'Length + Plen);
               end;
            end;
         when Float_Arg =>
            declare
               Verb : Character := Sp.Verb;
               Prec : Integer := Sp.Prec;
            begin
               if Verb = 'v' then
                  Verb := 'g';
                  Prec := -1;
               end if;
               case Verb is
                  when 'f' | 'F' | 'e' | 'E' | 'g' | 'G' =>
                     if Prec < 0 and then Verb in 'f' | 'F' | 'e' | 'E' then
                        Prec := 6;  --  Go's default for fixed/exponent
                     end if;
                     return Pad
                       (Strconv.Format_Float (X.F, Verb, Prec), Sp, True);
                  when others =>
                     Bad := True;
                     return "%!" & Sp.Verb & "(BADVERB)";
               end case;
            end;
         when Str_Arg =>
            declare
               S : constant String := To_String (X.S);
            begin
               case Sp.Verb is
                  when 's' | 'v' =>
                     declare
                        T : constant String :=
                          (if Sp.Prec >= 0 and then Sp.Prec < S'Length
                           then S (S'First .. S'First + Sp.Prec - 1)
                           else S);
                     begin
                        return Pad (T, Sp, False);
                     end;
                  when 'q' =>
                     return Pad (Strings.Quote (S), Sp, False);
                  when others =>
                     Bad := True;
                     return "%!" & Sp.Verb & "(BADVERB)";
               end case;
            end;
         when Bool_Arg =>
            case Sp.Verb is
               when 't' | 'v' =>
                  return Pad (Bool_Text (X.B), Sp, False);
               when others =>
                  Bad := True;
                  return "%!" & Sp.Verb & "(BADVERB)";
            end case;
         when Char_Arg =>
            case Sp.Verb is
               when 'c' | 'v' =>
                  return Pad (String'(1 => X.C), Sp, False);
               when 'q' =>
                  return Pad (Strings.Quote (String'(1 => X.C)),
                              Sp, False);
               when others =>
                  Bad := True;
                  return "%!" & Sp.Verb & "(BADVERB)";
            end case;
         when Ptr_Arg =>
            case Sp.Verb is
               when 'p' | 'v' =>
                  return Pad (Hex_Addr (X.P), Sp, True);
               when others =>
                  Bad := True;
                  return "%!" & Sp.Verb & "(BADVERB)";
            end case;
         when Err_Arg =>
            case Sp.Verb is
               when 's' | 'v' | 'w' =>
                  return Pad
                    ((if X.E = null then "<nil>"
                      else Errors.Message (X.E.all)),
                     Sp, False);
               when others =>
                  Bad := True;
                  return "%!" & Sp.Verb & "(BADVERB)";
            end case;
      end case;
   end Format_Arg;

   function Sprintf (Format : String; Args : Arg_Array) return String is
      R   : Unbounded_String;
      AI  : Natural := Args'First;
      I   : Integer := Format'First;
      Bad : Boolean;
   begin
      while I <= Format'Last loop
         if Format (I) = '%' and then I < Format'Last then
            declare
               Sp : Spec;
            begin
               Parse_Spec (Format, I, Sp);
               if Sp.Verb = '%' then
                  Append (R, '%');
               elsif AI <= Args'Last then
                  Append (R, Format_Arg (Args (AI), Sp, Bad));
                  AI := AI + 1;
               else
                  Append (R, "%!(NOVERB)");
               end if;
            end;
         else
            Append (R, Format (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (R);
   end Sprintf;

   procedure Print (Args : Arg_Array) is
   begin
      for I in Args'Range loop
         if I > Args'First then
            Gada.Core.IO.Print (" ");
         end if;
         declare
            Bad : Boolean;
         begin
            Gada.Core.IO.Print (Format_Arg (Args (I), (Verb => 'v',
                                               others => <>), Bad));
         end;
      end loop;
   end Print;

   procedure Println (Args : Arg_Array) is
   begin
      Print (Args);
      Gada.Core.IO.New_Line;
   end Println;

   procedure Printf (Format : String; Args : Arg_Array) is
   begin
      Gada.Core.IO.Print (Sprintf (Format, Args));
   end Printf;

   function Errorf (Format : String; Args : Arg_Array)
      return Errors.Error_Access is
      --  %w wraps the error argument as the cause (Go 1.13).
      function Has_W return Boolean is
      begin
         return Format'Length > 0
           and then Strings.Contains (Format, "%w");
      end Has_W;
      Msg : constant String := Sprintf (Format, Args);
   begin
      if Has_W and then Args'Length = 1 and then Args (Args'First).K = Err_Arg
      then
         return Errors.With_Cause (Msg, Args (Args'First).E);
      end if;
      return Errors.New_K (Msg);
   end Errorf;

   --  Splits S into whitespace-separated tokens.
   function Next_Token (S : String; I : in out Integer)
      return String is
   begin
      while I <= S'Last and then S (I) = ' ' loop
         I := I + 1;
      end loop;
      declare
         First : constant Integer := I;
      begin
         while I <= S'Last and then S (I) /= ' ' loop
            I := I + 1;
         end loop;
         return S (First .. I - 1);
      end;
   end Next_Token;

   procedure Sscanf (S, Format : String; Args : in out Arg_Array;
                     N : out Natural;
                     Err : out Errors.Error_Access) is
      I  : Integer := S'First;
      FI : Integer := Format'First;
      AI : Natural := Args'First;
   begin
      N := 0;
      Err := Errors.No_Error;
      while FI <= Format'Last loop
         if Format (FI) = '%' and then FI < Format'Last then
            declare
               Sp : Spec;
            begin
               Parse_Spec (Format, FI, Sp);
               if Sp.Verb = '%' then
                  null;  --  literal %: no argument
               elsif AI > Args'Last then
                  Err := Errors.New_K ("fmt.Sscanf: not enough args");
                  return;
               else
                  declare
                     Tok : constant String := Next_Token (S, I);
                  begin
                     if Tok'Length = 0 then
                        Err := Errors.New_K ("fmt.Sscanf: unexpected EOF");
                        return;
                     end if;
                     case Sp.Verb is
                        when 'd' =>
                           if Args (AI).K /= Int_Arg then
                              Err := Errors.New_K
                                ("fmt.Sscanf: %d into wrong kind");
                              return;
                           end if;
                           begin
                              Args (AI).I := Integer'Value (Tok);
                           exception
                              when Constraint_Error =>
                                 Err := Errors.New_K
                                   ("fmt.Sscanf: bad integer");
                                 return;
                           end;
                        when 'f' | 'g' | 'e' | 'v' =>
                           if Args (AI).K /= Float_Arg then
                              Err := Errors.New_K
                                ("fmt.Sscanf: float verb into wrong kind");
                              return;
                           end if;
                           declare
                              V : Long_Float;
                              E : Errors.Error_Access;
                           begin
                              Strconv.Parse_Float (Tok, V, E);
                              if E /= Errors.No_Error then
                                 Err := E;
                                 return;
                              end if;
                              Args (AI).F := V;
                           end;
                        when 's' =>
                           if Args (AI).K /= Str_Arg then
                              Err := Errors.New_K
                                ("fmt.Sscanf: %s into wrong kind");
                              return;
                           end if;
                           Args (AI).S := To_Unbounded_String (Tok);
                        when 't' =>
                           if Args (AI).K /= Bool_Arg then
                              Err := Errors.New_K
                                ("fmt.Sscanf: %t into wrong kind");
                              return;
                           end if;
                           Args (AI).B := Tok = "true";
                        when 'c' =>
                           if Args (AI).K /= Char_Arg then
                              Err := Errors.New_K
                                ("fmt.Sscanf: %c into wrong kind");
                              return;
                           end if;
                           Args (AI).C := Tok (Tok'First);
                        when others =>
                           Err := Errors.New_K
                             ("fmt.Sscanf: unsupported verb");
                           return;
                     end case;
                     AI := AI + 1;
                     N := N + 1;
                  end;
               end if;
            end;
         else
            FI := FI + 1;
         end if;
      end loop;
   end Sscanf;

end Gada.Std.Fmt;
