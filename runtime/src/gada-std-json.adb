--  Gada.Std.Json body — see the spec for the layer description.

with Ada.Strings.Fixed;

package body Gada.Std.Json is

   use Ada.Strings.Unbounded;
   use Gada.Std.Bytes;
   use Gada.Std.Errors;

   ---------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------

   Hex_Digits : constant String := "0123456789abcdef";

   function Hex2 (V : Natural) return String is
   begin
      return (1 => Hex_Digits (V / 16 + 1),
              2 => Hex_Digits (V mod 16 + 1));
   end Hex2;

   --  Hex_Val decodes one hex digit; OK = False on a non-hex char.
   function Hex_Val (C : Character; OK : out Boolean) return Natural is
   begin
      if C in '0' .. '9' then
         OK := True;
         return Character'Pos (C) - Character'Pos ('0');
      elsif C in 'a' .. 'f' then
         OK := True;
         return Character'Pos (C) - Character'Pos ('a') + 10;
      elsif C in 'A' .. 'F' then
         OK := True;
         return Character'Pos (C) - Character'Pos ('A') + 10;
      end if;
      OK := False;
      return 0;
   end Hex_Val;

   --  Append_Utf8 appends the UTF-8 encoding of a BMP code point.
   procedure Append_Utf8 (R : in out Unbounded_String; Code : Natural) is
   begin
      if Code < 16#80# then
         Append (R, Character'Val (Code));
      elsif Code < 16#800# then
         Append (R, Character'Val (16#C0# + Code / 16#40#));
         Append (R, Character'Val (16#80# + Code mod 16#40#));
      else
         Append (R, Character'Val (16#E0# + Code / 16#1000#));
         Append (R, Character'Val (16#80# + (Code / 16#40#) mod 16#40#));
         Append (R, Character'Val (16#80# + Code mod 16#40#));
      end if;
   end Append_Utf8;

   function Is_Ws (C : Character) return Boolean is
   begin
      return C = ' ' or else C = Character'Val (9)
        or else C = Character'Val (10) or else C = Character'Val (13);
   end Is_Ws;

   ---------------------------------------------------------------
   --  String primitives
   ---------------------------------------------------------------

   function Escape (S : String) return String is
      R : Unbounded_String;
   begin
      for C of S loop
         case C is
            when '"' =>
               Append (R, "\""");
            when '\' =>
               Append (R, "\\");
            when Character'Val (8) =>
               Append (R, "\b");
            when Character'Val (12) =>
               Append (R, "\f");
            when Character'Val (10) =>
               Append (R, "\n");
            when Character'Val (13) =>
               Append (R, "\r");
            when Character'Val (9) =>
               Append (R, "\t");
            when others =>
               if Character'Pos (C) < 32 then
                  Append (R, "\u00" & Hex2 (Character'Pos (C)));
               else
                  Append (R, C);
               end if;
         end case;
      end loop;
      return To_String (R);
   end Escape;

   function Unescape (S : String; OK : out Boolean) return String is
      R    : Unbounded_String;
      I    : Natural := S'First;
      Code : Natural;
      D    : Natural;
   begin
      OK := True;
      while I <= S'Last loop
         if S (I) /= '\' then
            Append (R, S (I));
            I := I + 1;
         else
            I := I + 1;
            if I > S'Last then
               OK := False;
               return "";
            end if;
            case S (I) is
               when '"' => Append (R, '"');
               when '\' => Append (R, '\');
               when '/' => Append (R, '/');
               when 'b' => Append (R, Character'Val (8));
               when 'f' => Append (R, Character'Val (12));
               when 'n' => Append (R, Character'Val (10));
               when 'r' => Append (R, Character'Val (13));
               when 't' => Append (R, Character'Val (9));
               when 'u' =>
                  Code := 0;
                  for K in 1 .. 4 loop
                     if I + K > S'Last then
                        OK := False;
                        return "";
                     end if;
                     declare
                        H : Boolean;
                     begin
                        D := Hex_Val (S (I + K), H);
                        if not H then
                           OK := False;
                           return "";
                        end if;
                     end;
                     Code := Code * 16 + D;
                  end loop;
                  --  Surrogate halves need a pair; reject in v1.
                  if Code >= 16#D800# and then Code <= 16#DFFF# then
                     OK := False;
                     return "";
                  end if;
                  if Code > 16#FFFF# then
                     OK := False;
                     return "";
                  end if;
                  Append_Utf8 (R, Code);
                  I := I + 4;
               when others =>
                  OK := False;
                  return "";
            end case;
            I := I + 1;
         end if;
      end loop;
      return To_String (R);
   end Unescape;

   ---------------------------------------------------------------
   --  Number formatting / parsing
   ---------------------------------------------------------------

   --  Float_Image renders X as JSON number text: decimal, with the
   --  exponent folded into the digits (so 1.5e2 prints as "150", like
   --  Go's encoder), trailing fraction zeros stripped, and no
   --  exponent when the value is integral-range. Long_Float'Image
   --  gives " D.DDDDDDDDDDDDDDDDE+XX"; we renormalise from its digits.
   function Float_Image (X : Long_Float) return String is
      Img : constant String := Long_Float'Image (X);
      S   : constant String := Ada.Strings.Fixed.Trim
        (Img, Ada.Strings.Left);
      E   : constant Natural := Ada.Strings.Fixed.Index (S, "E");
      Man : constant String := S (S'First .. E - 1);  --  [-]D.DDD
      Exp : constant Integer := Integer'Value (S (E + 1 .. S'Last));
      Neg : constant Boolean := Man (Man'First) = '-';
      Dig : constant String := (if Neg then Man (Man'First + 1 .. Man'Last)
                                else Man);
      --  Split mantissa into digits and point position.
      Dot : constant Natural := Ada.Strings.Fixed.Index (Dig, ".");
      Dig_S : constant String :=
        (if Dot = 0 then Dig
         else Dig (Dig'First .. Dot - 1) & Dig (Dot + 1 .. Dig'Last));
      Point : constant Natural :=
        (if Dot = 0 then Dig_S'Length else Dot - Dig'First);
      --  Apply the exponent: new point position.
      New_Point : constant Integer :=
        Integer (Point) + Exp;
      --  Scientific exponent e: value = D.DDD… * 10**e. Go's encoder
      --  (encoding/json) switches to 'e' format only when
      --  e < -6 or e >= 21 (abs < 1e-6 or abs >= 1e21).
      E10 : constant Integer := New_Point - 1;
      R : Unbounded_String;
   begin
      if E10 < -6 or else E10 >= 21 then
         --  Scientific: d[.ddd]e±XX — mantissa digits, first then
         --  fraction, trailing zeros stripped, then e and the signed
         --  exponent without leading zeros ('+' kept, as in Go).
         declare
            Man : constant String := Dig_S;
            Last : Natural := Man'Last;
         begin
            while Last > Man'First and then Man (Last) = '0' loop
               Last := Last - 1;
            end loop;
            if Neg then
               Append (R, '-');
            end if;
            Append (R, Man (Man'First));
            if Last > Man'First then
               Append (R, '.');
               Append (R, Man (Man'First + 1 .. Last));
            end if;
            Append (R, 'e');
            if E10 < 0 then
               Append (R, '-');
            else
               Append (R, '+');
            end if;
            declare
               EI : constant String :=
                 Ada.Strings.Fixed.Trim (Integer'Image (abs E10),
                                         Ada.Strings.Left);
            begin
               Append (R, EI);
            end;
            return To_String (R);
         end;
      end if;
      if Neg then
         Append (R, '-');
      end if;
      if New_Point >= Dig_S'Length then
         --  Integral: digits + padding zeros.
         Append (R, Dig_S);
         for K in 1 .. New_Point - Integer (Dig_S'Length) loop
            Append (R, '0');
         end loop;
      elsif New_Point <= 0 then
         Append (R, "0.");
         for K in 1 .. (-New_Point) loop
            Append (R, '0');
         end loop;
         Append (R, Dig_S);
      else
         Append (R, Dig_S (Dig_S'First .. Dig_S'First + New_Point - 1));
         Append (R, '.');
         Append (R, Dig_S (Dig_S'First + New_Point .. Dig_S'Last));
      end if;
      declare
         T : constant String := To_String (R);
         Last : Natural := T'Last;
      begin
         --  Strip trailing fraction zeros, then a bare trailing point.
         if Ada.Strings.Fixed.Index (T, ".") > 0 then
            while Last >= T'First and then T (Last) = '0' loop
               Last := Last - 1;
            end loop;
            if Last >= T'First and then T (Last) = '.' then
               Last := Last - 1;
            end if;
         end if;
         return T (T'First .. Last);
      end;
   end Float_Image;

   --  Only_Ws_From reports whether S (I .. S'Last) is all whitespace.
   function Only_Ws_From (S : String; I : Natural) return Boolean is
   begin
      for K in I .. S'Last loop
         if not Is_Ws (S (K)) then
            return False;
         end if;
      end loop;
      return True;
   end Only_Ws_From;

   --  Parse_Scalar_At parses one JSON scalar starting at or after I
   --  (leading whitespace skipped), leaving I just past the value.
   --  v1 supports scalars only (objects/arrays are Parse_Object's job).
   --  OK = False on any syntax error.
   procedure Parse_Scalar_At (Text : String; I : in out Natural;
                              V : out Scalar; OK : out Boolean) is
   begin
      OK := False;
      V := (Kind => K_Invalid);
      while I <= Text'Last and then Is_Ws (Text (I)) loop
         I := I + 1;
      end loop;
      if I > Text'Last then
         return;
      end if;
      case Text (I) is
         when '"' =>
            declare
               J : Natural := I + 1;
            begin
               while J <= Text'Last loop
                  if Text (J) = '\' then
                     J := J + 2;
                  elsif Text (J) = '"' then
                     exit;
                  else
                     J := J + 1;
                  end if;
               end loop;
               if J > Text'Last or else not Only_Ws_From (Text, J + 1) then
                  return;
               end if;
               declare
                  U  : Boolean;
                  Uc : constant String :=
                    Unescape (Text (I + 1 .. J - 1), U);
               begin
                  if not U then
                     return;
                  end if;
                  V := (K_String, To_Unbounded_String (Uc));
                  OK := True;
               end;
            end;
         when 't' =>
            if Text (I .. Text'Last) = "true"
              and then Only_Ws_From (Text, I + 4)
            then
               V := (K_Bool, True);
               OK := True;
            end if;
         when 'f' =>
            if Text (I .. Text'Last) = "false"
              and then Only_Ws_From (Text, I + 5)
            then
               V := (K_Bool, False);
               OK := True;
            end if;
         when 'n' =>
            if Text (I .. Text'Last) = "null"
              and then Only_Ws_From (Text, I + 4)
            then
               V := (Kind => K_Null);
               OK := True;
            end if;
         when '-' | '0' .. '9' =>
            declare
               J        : Natural := I;
               Is_Float : Boolean := False;
            begin
               if Text (J) = '-' then
                  J := J + 1;
               end if;
               if J > Text'Last or else Text (J) not in '0' .. '9' then
                  return;
               end if;
               while J <= Text'Last and then Text (J) in '0' .. '9' loop
                  J := J + 1;
               end loop;
               if J <= Text'Last and then Text (J) = '.' then
                  Is_Float := True;
                  J := J + 1;
                  if J > Text'Last or else Text (J) not in '0' .. '9' then
                     return;
                  end if;
                  while J <= Text'Last and then Text (J) in '0' .. '9' loop
                     J := J + 1;
                  end loop;
               end if;
               if J <= Text'Last and then (Text (J) = 'e' or else
                                           Text (J) = 'E')
               then
                  Is_Float := True;
                  J := J + 1;
                  if J <= Text'Last and then (Text (J) = '+' or else
                                              Text (J) = '-')
                  then
                     J := J + 1;
                  end if;
                  if J > Text'Last or else Text (J) not in '0' .. '9' then
                     return;
                  end if;
                  while J <= Text'Last and then Text (J) in '0' .. '9' loop
                     J := J + 1;
                  end loop;
               end if;
               if not Only_Ws_From (Text, J) then
                  return;
               end if;
               declare
                  Num : constant String := Text (I .. J - 1);
               begin
                  if Is_Float then
                     begin
                        V := (K_Float, Long_Float'Value (Num));
                     exception
                        when Constraint_Error =>
                           return;
                     end;
                  else
                     begin
                        V := (K_Int, Long_Long_Integer'Value (Num));
                     exception
                        when Constraint_Error =>
                           --  Overflows int64: Go widens to float64.
                           begin
                              V := (K_Float, Long_Float'Value (Num));
                           exception
                              when Constraint_Error =>
                                 return;
                           end;
                     end;
                  end if;
                  OK := True;
               end;
            end;
         when others =>
            return;
      end case;
   end Parse_Scalar;

   ---------------------------------------------------------------
   --  Reflect-driven value encoding
   ---------------------------------------------------------------

   function Encode_Value (V : Gada.Reflect.Values.Value)
                          return Unbounded_String is
   begin
      case Gada.Reflect.Values.Kind (V) is
         when Gada.Reflect.Types.Bool_Kind =>
            if Gada.Reflect.Values.To_Bool (V) then
               return To_Unbounded_String ("true");
            else
               return To_Unbounded_String ("false");
            end if;
         when Gada.Reflect.Types.Int_Kind =>
            return To_Unbounded_String (Ada.Strings.Fixed.Trim
              (Gada.Reflect.Values.To_Int (V)'Image, Ada.Strings.Left));
         when Gada.Reflect.Types.Float_Kind =>
            return To_Unbounded_String
              (Float_Image (Gada.Reflect.Values.To_Float (V)));
         when Gada.Reflect.Types.String_Kind =>
            return To_Unbounded_String
              ('"' & Escape (Gada.Reflect.Values.To_String (V)) & '"');
         when others =>
            return To_Unbounded_String ("null");
      end case;
   end Encode_Value;

   ---------------------------------------------------------------
   --  Typed scalar encoders
   ---------------------------------------------------------------

   function Encode_Int (X : Integer) return Unbounded_String is
   begin
      return To_Unbounded_String (Ada.Strings.Fixed.Trim
        (X'Image, Ada.Strings.Left));
   end Encode_Int;

   function Encode_Float (X : Long_Float) return Unbounded_String is
   begin
      return To_Unbounded_String (Float_Image (X));
   end Encode_Float;

   function Encode_Bool (X : Boolean) return Unbounded_String is
   begin
      if X then
         return To_Unbounded_String ("true");
      else
         return To_Unbounded_String ("false");
      end if;
   end Encode_Bool;

   function Encode_String (S : String) return Unbounded_String is
   begin
      return To_Unbounded_String ('"' & Escape (S) & '"');
   end Encode_String;

   ---------------------------------------------------------------
   --  Marshal / Unmarshal
   ---------------------------------------------------------------

   procedure Marshal (X : Integer;
                      Data : out Byte_Slice;
                      Err  : out Error_Access) is
   begin
      Err  := No_Error;
      Data := To_Bytes (To_String (Encode_Int (X)));
   end Marshal;

   procedure Marshal (X : Long_Float;
                      Data : out Byte_Slice;
                      Err  : out Error_Access) is
   begin
      if X /= X then
         --  NaN: Go's encoder rejects it.
         Data := Byte_Vectors.Empty_Vector;
         Err  := New_K ("json: unsupported value: NaN");
         return;
      end if;
      Err  := No_Error;
      Data := To_Bytes (To_String (Encode_Float (X)));
   end Marshal;

   procedure Marshal (X : Boolean;
                      Data : out Byte_Slice;
                      Err  : out Error_Access) is
   begin
      Err  := No_Error;
      Data := To_Bytes (To_String (Encode_Bool (X)));
   end Marshal;

   procedure Marshal (X : String;
                      Data : out Byte_Slice;
                      Err  : out Error_Access) is
   begin
      Err  := No_Error;
      Data := To_Bytes (To_String (Encode_String (X)));
   end Marshal;

   procedure Marshal (V : Gada.Reflect.Values.Value;
                      Data : out Byte_Slice;
                      Err  : out Error_Access) is
   begin
      Err  := No_Error;
      Data := To_Bytes (To_String (Encode_Value (V)));
   end Marshal;

   procedure Unmarshal (Data : Byte_Slice;
                        V    : in out Integer;
                        Err  : out Error_Access) is
      P  : Scalar;
      OK : Boolean;
   begin
      Err := No_Error;
      Parse_Scalar (To_String (Data), P, OK);
      if not OK then
         Err := New_K ("json: invalid JSON text");
         return;
      end if;
      case P.Kind is
         when K_Int =>
            begin
               V := Integer (P.I);
            exception
               when Constraint_Error =>
                  Err := New_K ("json: value out of int range");
            end;
         when K_Null =>
            null;  --  Go leaves the target unchanged on null
         when others =>
            Err := New_K ("json: cannot unmarshal value into int");
      end case;
   end Unmarshal;

   procedure Unmarshal (Data : Byte_Slice;
                        V    : in out Long_Float;
                        Err  : out Error_Access) is
      P  : Scalar;
      OK : Boolean;
   begin
      Err := No_Error;
      Parse_Scalar (To_String (Data), P, OK);
      if not OK then
         Err := New_K ("json: invalid JSON text");
         return;
      end if;
      case P.Kind is
         when K_Int =>
            V := Long_Float (P.I);
         when K_Float =>
            V := P.F;
         when K_Null =>
            null;
         when others =>
            Err := New_K ("json: cannot unmarshal value into float64");
      end case;
   end Unmarshal;

   procedure Unmarshal (Data : Byte_Slice;
                        V    : in out Boolean;
                        Err  : out Error_Access) is
      P  : Scalar;
      OK : Boolean;
   begin
      Err := No_Error;
      Parse_Scalar (To_String (Data), P, OK);
      if not OK then
         Err := New_K ("json: invalid JSON text");
         return;
      end if;
      case P.Kind is
         when K_Bool =>
            V := P.B;
         when K_Null =>
            null;
         when others =>
            Err := New_K ("json: cannot unmarshal value into bool");
      end case;
   end Unmarshal;

   procedure Unmarshal (Data : Byte_Slice;
                        V    : in out Unbounded_String;
                        Err  : out Error_Access) is
      P  : Scalar;
      OK : Boolean;
   begin
      Err := No_Error;
      Parse_Scalar (To_String (Data), P, OK);
      if not OK then
         Err := New_K ("json: invalid JSON text");
         return;
      end if;
      case P.Kind is
         when K_String =>
            V := P.S;
         when K_Null =>
            null;
         when others =>
            Err := New_K ("json: cannot unmarshal value into string");
      end case;
   end Unmarshal;

end Gada.Std.Json;
