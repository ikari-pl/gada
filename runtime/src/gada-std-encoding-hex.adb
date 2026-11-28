--  Gada.Std.Encoding.Hex body — see spec.

with Gada.Std.Bytes; use Gada.Std.Bytes;

package body Gada.Std.Encoding.Hex is

   Hex_Digits : constant String := "0123456789abcdef";

   function Nibble (C : Character) return Natural is
   begin
      if C in '0' .. '9' then
         return Character'Pos (C) - Character'Pos ('0');
      elsif C in 'a' .. 'f' then
         return Character'Pos (C) - Character'Pos ('a') + 10;
      elsif C in 'A' .. 'F' then
         return Character'Pos (C) - Character'Pos ('A') + 10;
      end if;
      raise Constraint_Error with "hex: illegal character";
   end Nibble;

   function Encode_To_String (Data : Byte_Slice) return String is
      R : String (1 .. 2 * Natural (Byte_Vectors.Length (Data)));
   begin
      for I in 1 .. Natural (Byte_Vectors.Length (Data)) loop
         declare
            V : constant Natural :=
              Character'Pos (Byte_Vectors.Element (Data, I));
         begin
            R (2 * I - 1) := Hex_Digits (V / 16 + 1);
            R (2 * I)     := Hex_Digits (V mod 16 + 1);
         end;
      end loop;
      return R;
   end Encode_To_String;

   function Decode_String (S : String) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      if S'Length mod 2 /= 0 then
         raise Constraint_Error with "hex: odd-length string";
      end if;
      for I in 1 .. S'Length / 2 loop
         Byte_Vectors.Append
           (R, Character'Val
              (Nibble (S (2 * I - 1)) * 16 + Nibble (S (2 * I))));
      end loop;
      return R;
   end Decode_String;

   function Encoded_Len (N : Natural) return Natural is (2 * N);

   function Decoded_Len (N : Natural) return Natural is (N / 2);

end Gada.Std.Encoding.Hex;
