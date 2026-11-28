--  Gada.Std.Encoding.Base64 body — see spec. One internal Encode /
--  Decode over (alphabet, padding) flags; the four public functions
--  are thin wrappers.

with Gada.Std.Bytes; use Gada.Std.Bytes;
with Interfaces; use Interfaces;

package body Gada.Std.Encoding.Base64 is

   Alpha_Std : constant String :=
     "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
   Alpha_URL : constant String :=
     "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

   function Encode (Data : Byte_Slice; Alpha : String; Pad : Boolean)
      return String is
      N   : constant Natural := Natural (Byte_Vectors.Length (Data));
      Out_Len : constant Natural :=
        (if Pad then 4 * ((N + 2) / 3)
         else (N / 3) * 4 + (if N mod 3 = 0 then 0 elsif N mod 3 = 1 then 2 else 3));
      R   : String (1 .. Out_Len);
      P   : Positive := 1;

      procedure Put_Char (V6 : Natural) is
      begin
         R (P) := Alpha (Alpha'First + V6);
         P := P + 1;
      end Put_Char;
   begin
      for Off in 0 .. N / 3 - 1 loop
         declare
            B0 : constant Natural := Character'Pos (Byte_Vectors.Element (Data, 3 * Off + 1));
            B1 : constant Natural := Character'Pos (Byte_Vectors.Element (Data, 3 * Off + 2));
            B2 : constant Natural := Character'Pos (Byte_Vectors.Element (Data, 3 * Off + 3));
         begin
            Put_Char (B0 / 4);
            Put_Char ((B0 mod 4) * 16 + B1 / 16);
            Put_Char ((B1 mod 16) * 4 + B2 / 64);
            Put_Char (B2 mod 64);
         end;
      end loop;
      case N mod 3 is
         when 0 => null;
         when 1 =>
            declare
               B0 : constant Natural :=
                 Character'Pos (Byte_Vectors.Element (Data, N));
            begin
               Put_Char (B0 / 4);
               Put_Char ((B0 mod 4) * 16);
               if Pad then
                  R (P) := '='; P := P + 1;
                  R (P) := '='; P := P + 1;
               end if;
            end;
         when others =>
            declare
               B0 : constant Natural :=
                 Character'Pos (Byte_Vectors.Element (Data, N - 1));
               B1 : constant Natural :=
                 Character'Pos (Byte_Vectors.Element (Data, N));
            begin
               Put_Char (B0 / 4);
               Put_Char ((B0 mod 4) * 16 + B1 / 16);
               Put_Char ((B1 mod 16) * 4);
               if Pad then
                  R (P) := '='; P := P + 1;
               end if;
            end;
      end case;
      return R;
   end Encode;

   function Decode (S : String; Alpha : String; Padded : Boolean)
      return Byte_Slice is
      type Rev_Table is array (Natural range 0 .. 255) of Integer;
      Rev : Rev_Table := (others => -1);
      R   : Byte_Slice := Byte_Vectors.Empty_Vector;

      function Val (C : Character) return Integer is
        (Rev (Character'Pos (C)));
   begin
      for I in Alpha'Range loop
         Rev (Character'Pos (Alpha (I))) := I - Alpha'First;
      end loop;
      if Padded and then S'Length mod 4 /= 0 then
         raise Constraint_Error
           with "base64: padded input length not a multiple of 4";
      end if;
      if not Padded and then S'Length mod 4 = 1 then
         raise Constraint_Error with "base64: raw input length mod 4 = 1";
      end if;
      declare
         I : Natural := S'First;
      begin
         while I <= S'Last loop
            declare
               K    : constant Natural := Natural'Min (4, S'Last - I + 1);
               V    : array (0 .. 3) of Integer := (others => -1);
               Pads : Natural := 0;
               D    : Natural;  --  data chars in this quantum
            begin
               for J in 0 .. K - 1 loop
                  declare
                     C : constant Character := S (I + J);
                  begin
                     if C = '=' then
                        --  '=' is legal only in the last two positions
                        --  of the final quantum of a padded input
                        if not Padded or else J < 2
                          or else I + J < S'Last - 1 then
                           raise Constraint_Error
                             with "base64: illegal padding";
                        end if;
                        Pads := Pads + 1;
                     else
                        if Val (C) < 0 then
                           raise Constraint_Error
                             with "base64: illegal character";
                        end if;
                        V (J) := Val (C);
                     end if;
                  end;
               end loop;
               D := (if Padded then K - Pads else K);
               --  the D data chars are V (0) .. V (D - 1); pad slots
               --  stay -1 and are never read here
               if D >= 2 then
                  Byte_Vectors.Append
                    (R, Character'Val (V (0) * 4 + V (1) / 16));
               end if;
               if D >= 3 then
                  Byte_Vectors.Append
                    (R, Character'Val ((V (1) mod 16) * 16 + V (2) / 4));
               end if;
               if D = 4 then
                  Byte_Vectors.Append
                    (R, Character'Val ((V (2) mod 4) * 64 + V (3)));
               end if;
               I := I + K;
            end;
         end loop;
      end;
      return R;
   end Decode;

   function Encode_Std (Data : Byte_Slice) return String is
      (Encode (Data, Alpha_Std, True));
   function Encode_URL (Data : Byte_Slice) return String is
      (Encode (Data, Alpha_URL, True));
   function Encode_Raw_Std (Data : Byte_Slice) return String is
      (Encode (Data, Alpha_Std, False));
   function Encode_Raw_URL (Data : Byte_Slice) return String is
      (Encode (Data, Alpha_URL, False));

   function Decode_Std (S : String) return Byte_Slice is
      (Decode (S, Alpha_Std, True));
   function Decode_URL (S : String) return Byte_Slice is
      (Decode (S, Alpha_URL, True));
   function Decode_Raw_Std (S : String) return Byte_Slice is
      (Decode (S, Alpha_Std, False));
   function Decode_Raw_URL (S : String) return Byte_Slice is
      (Decode (S, Alpha_URL, False));

end Gada.Std.Encoding.Base64;
