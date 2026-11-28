--  Gada.Std.Encoding.Binary body — see spec.

with Gada.Std.Bytes; use Gada.Std.Bytes;

package body Gada.Std.Encoding.Binary is

   procedure Need (B : Byte_Slice; N : Natural) is
   begin
      if Natural (Byte_Vectors.Length (B)) < N then
         raise Constraint_Error
           with "binary: buffer too short (want" & Natural'Image (N)
                & ", got" & Natural'Image (Natural (Byte_Vectors.Length (B)))
                & ")";
      end if;
   end Need;

   function Encode_Uint16_BE (V : Unsigned_16) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      Append_Uint16_BE (R, V);
      return R;
   end Encode_Uint16_BE;

   function Encode_Uint32_BE (V : Unsigned_32) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      Append_Uint32_BE (R, V);
      return R;
   end Encode_Uint32_BE;

   function Encode_Uint64_BE (V : Unsigned_64) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      Append_Uint64_BE (R, V);
      return R;
   end Encode_Uint64_BE;

   function Encode_Uint16_LE (V : Unsigned_16) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      Append_Uint16_LE (R, V);
      return R;
   end Encode_Uint16_LE;

   function Encode_Uint32_LE (V : Unsigned_32) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      Append_Uint32_LE (R, V);
      return R;
   end Encode_Uint32_LE;

   function Encode_Uint64_LE (V : Unsigned_64) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      Append_Uint64_LE (R, V);
      return R;
   end Encode_Uint64_LE;

   procedure Append_Uint16_BE (Buf : in out Byte_Slice; V : Unsigned_16) is
   begin
      Byte_Vectors.Append (Buf, Character'Val (Shift_Right (V, 8)));
      Byte_Vectors.Append (Buf, Character'Val (V and 16#FF#));
   end Append_Uint16_BE;

   procedure Append_Uint32_BE (Buf : in out Byte_Slice; V : Unsigned_32) is
   begin
      for J in 0 .. 3 loop
         Byte_Vectors.Append
           (Buf, Character'Val (Shift_Right (V, 8 * (3 - J)) and 16#FF#));
      end loop;
   end Append_Uint32_BE;

   procedure Append_Uint64_BE (Buf : in out Byte_Slice; V : Unsigned_64) is
   begin
      for J in 0 .. 7 loop
         Byte_Vectors.Append
           (Buf, Character'Val (Shift_Right (V, 8 * (7 - J)) and 16#FF#));
      end loop;
   end Append_Uint64_BE;

   procedure Append_Uint16_LE (Buf : in out Byte_Slice; V : Unsigned_16) is
   begin
      Byte_Vectors.Append (Buf, Character'Val (V and 16#FF#));
      Byte_Vectors.Append (Buf, Character'Val (Shift_Right (V, 8)));
   end Append_Uint16_LE;

   procedure Append_Uint32_LE (Buf : in out Byte_Slice; V : Unsigned_32) is
   begin
      for J in 0 .. 3 loop
         Byte_Vectors.Append
           (Buf, Character'Val (Shift_Right (V, 8 * J) and 16#FF#));
      end loop;
   end Append_Uint32_LE;

   procedure Append_Uint64_LE (Buf : in out Byte_Slice; V : Unsigned_64) is
   begin
      for J in 0 .. 7 loop
         Byte_Vectors.Append
           (Buf, Character'Val (Shift_Right (V, 8 * J) and 16#FF#));
      end loop;
   end Append_Uint64_LE;

   function Uint16_BE (B : Byte_Slice) return Unsigned_16 is
   begin
      Need (B, 2);
      return Shift_Left (Unsigned_16 (Character'Pos (Byte_Vectors.Element (B, 1))), 8)
        or Unsigned_16 (Character'Pos (Byte_Vectors.Element (B, 2)));
   end Uint16_BE;

   function Uint32_BE (B : Byte_Slice) return Unsigned_32 is
   begin
      Need (B, 4);
      return Shift_Left (Unsigned_32 (Character'Pos (Byte_Vectors.Element (B, 1))), 24)
        or Shift_Left (Unsigned_32 (Character'Pos (Byte_Vectors.Element (B, 2))), 16)
        or Shift_Left (Unsigned_32 (Character'Pos (Byte_Vectors.Element (B, 3))), 8)
        or Unsigned_32 (Character'Pos (Byte_Vectors.Element (B, 4)));
   end Uint32_BE;

   function Uint64_BE (B : Byte_Slice) return Unsigned_64 is
      R : Unsigned_64 := 0;
   begin
      Need (B, 8);
      for I in 1 .. 8 loop
         R := Shift_Left (R, 8)
           or Unsigned_64 (Character'Pos (Byte_Vectors.Element (B, I)));
      end loop;
      return R;
   end Uint64_BE;

   function Uint16_LE (B : Byte_Slice) return Unsigned_16 is
   begin
      Need (B, 2);
      return Unsigned_16 (Character'Pos (Byte_Vectors.Element (B, 1)))
        or Shift_Left (Unsigned_16 (Character'Pos (Byte_Vectors.Element (B, 2))), 8);
   end Uint16_LE;

   function Uint32_LE (B : Byte_Slice) return Unsigned_32 is
      R : Unsigned_32 := 0;
   begin
      Need (B, 4);
      for I in 1 .. 4 loop
         R := R
           or Shift_Left (Unsigned_32 (Character'Pos (Byte_Vectors.Element (B, I))), 8 * (I - 1));
      end loop;
      return R;
   end Uint32_LE;

   function Uint64_LE (B : Byte_Slice) return Unsigned_64 is
      R : Unsigned_64 := 0;
   begin
      Need (B, 8);
      for I in 1 .. 8 loop
         R := R
           or Shift_Left (Unsigned_64 (Character'Pos (Byte_Vectors.Element (B, I))), 8 * (I - 1));
      end loop;
      return R;
   end Uint64_LE;

   procedure Append_Uvarint (Buf : in out Byte_Slice; V : Unsigned_64) is
      X : Unsigned_64 := V;
   begin
      loop
         if X < 16#80# then
            Byte_Vectors.Append (Buf, Character'Val (X));
            exit;
         end if;
         Byte_Vectors.Append (Buf, Character'Val ((X and 16#7F#) or 16#80#));
         X := Shift_Right (X, 7);
      end loop;
   end Append_Uvarint;

   procedure Uvarint (B : Byte_Slice; V : out Unsigned_64; N : out Natural) is
      X : Unsigned_64 := 0;
      S : Natural := 0;
   begin
      N := 0;
      V := 0;
      if Natural (Byte_Vectors.Length (B)) = 0 then
         return;  --  Go: Uvarint of empty returns (0, 0)
      end if;
      for I in 1 .. Natural (Byte_Vectors.Length (B)) loop
         declare
            Byte : constant Unsigned_64 :=
              Unsigned_64 (Character'Pos (Byte_Vectors.Element (B, I)));
         begin
            if I > 10 then
               raise Constraint_Error with "binary: uvarint overflow";
            end if;
            if I = 10 and then Byte > 1 then
               raise Constraint_Error with "binary: uvarint overflow";
            end if;
            X := X or Shift_Left (Byte and 16#7F#, S);
            N := I;
            if (Byte and 16#80#) = 0 then
               V := X;
               return;
            end if;
            S := S + 7;
         end;
      end loop;
      --  ran out of bytes with the continuation bit set: N stays at
      --  the last index but V is unset — Go returns n <= 0 here.
      raise Constraint_Error with "binary: truncated uvarint";
   end Uvarint;

   procedure Append_Varint (Buf : in out Byte_Slice; V : Integer_64) is
      X : Unsigned_64 := Shift_Left (Unsigned_64 (V), 1);
   begin
      if V < 0 then
         X := not X;
      end if;
      Append_Uvarint (Buf, X);
   end Append_Varint;

   procedure Varint (B : Byte_Slice; V : out Integer_64; N : out Natural) is
      X : Unsigned_64;
   begin
      Uvarint (B, X, N);
      --  zigzag decode; xor is only defined for modular types in Ada
      V := Integer_64
        (Shift_Right (X, 1) xor (if (X and 1) /= 0 then 1 else 0));
   end Varint;

end Gada.Std.Encoding.Binary;
