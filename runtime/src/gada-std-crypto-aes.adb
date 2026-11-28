--  Gada.Std.Crypto.Aes body — see spec. State is kept as a 4x4
--  byte matrix, column-major (state (R, C) = input byte 4*C + R),
--  per FIPS-197. GF(2^8) multiplication is the shift-and-xor
--  Russian-peasant form with the 0x1B reduction polynomial, shared
--  by MixColumns (2, 3) and InvMixColumns (9, 11, 13, 14).

with Gada.Std.Bytes; use Gada.Std.Bytes;

package body Gada.Std.Crypto.Aes is

   use Interfaces;

   type Byte16 is array (Natural range 0 .. 15) of Unsigned_8;
   type State is array (Natural range 0 .. 3, Natural range 0 .. 3)
     of Unsigned_8;

   Sbox : constant array (Natural range 0 .. 255) of Unsigned_8 :=
     (      16#63#, 16#7C#, 16#77#, 16#7B#, 16#F2#, 16#6B#, 16#6F#, 16#C5#,
      16#30#, 16#01#, 16#67#, 16#2B#, 16#FE#, 16#D7#, 16#AB#, 16#76#,
      16#CA#, 16#82#, 16#C9#, 16#7D#, 16#FA#, 16#59#, 16#47#, 16#F0#,
      16#AD#, 16#D4#, 16#A2#, 16#AF#, 16#9C#, 16#A4#, 16#72#, 16#C0#,
      16#B7#, 16#FD#, 16#93#, 16#26#, 16#36#, 16#3F#, 16#F7#, 16#CC#,
      16#34#, 16#A5#, 16#E5#, 16#F1#, 16#71#, 16#D8#, 16#31#, 16#15#,
      16#04#, 16#C7#, 16#23#, 16#C3#, 16#18#, 16#96#, 16#05#, 16#9A#,
      16#07#, 16#12#, 16#80#, 16#E2#, 16#EB#, 16#27#, 16#B2#, 16#75#,
      16#09#, 16#83#, 16#2C#, 16#1A#, 16#1B#, 16#6E#, 16#5A#, 16#A0#,
      16#52#, 16#3B#, 16#D6#, 16#B3#, 16#29#, 16#E3#, 16#2F#, 16#84#,
      16#53#, 16#D1#, 16#00#, 16#ED#, 16#20#, 16#FC#, 16#B1#, 16#5B#,
      16#6A#, 16#CB#, 16#BE#, 16#39#, 16#4A#, 16#4C#, 16#58#, 16#CF#,
      16#D0#, 16#EF#, 16#AA#, 16#FB#, 16#43#, 16#4D#, 16#33#, 16#85#,
      16#45#, 16#F9#, 16#02#, 16#7F#, 16#50#, 16#3C#, 16#9F#, 16#A8#,
      16#51#, 16#A3#, 16#40#, 16#8F#, 16#92#, 16#9D#, 16#38#, 16#F5#,
      16#BC#, 16#B6#, 16#DA#, 16#21#, 16#10#, 16#FF#, 16#F3#, 16#D2#,
      16#CD#, 16#0C#, 16#13#, 16#EC#, 16#5F#, 16#97#, 16#44#, 16#17#,
      16#C4#, 16#A7#, 16#7E#, 16#3D#, 16#64#, 16#5D#, 16#19#, 16#73#,
      16#60#, 16#81#, 16#4F#, 16#DC#, 16#22#, 16#2A#, 16#90#, 16#88#,
      16#46#, 16#EE#, 16#B8#, 16#14#, 16#DE#, 16#5E#, 16#0B#, 16#DB#,
      16#E0#, 16#32#, 16#3A#, 16#0A#, 16#49#, 16#06#, 16#24#, 16#5C#,
      16#C2#, 16#D3#, 16#AC#, 16#62#, 16#91#, 16#95#, 16#E4#, 16#79#,
      16#E7#, 16#C8#, 16#37#, 16#6D#, 16#8D#, 16#D5#, 16#4E#, 16#A9#,
      16#6C#, 16#56#, 16#F4#, 16#EA#, 16#65#, 16#7A#, 16#AE#, 16#08#,
      16#BA#, 16#78#, 16#25#, 16#2E#, 16#1C#, 16#A6#, 16#B4#, 16#C6#,
      16#E8#, 16#DD#, 16#74#, 16#1F#, 16#4B#, 16#BD#, 16#8B#, 16#8A#,
      16#70#, 16#3E#, 16#B5#, 16#66#, 16#48#, 16#03#, 16#F6#, 16#0E#,
      16#61#, 16#35#, 16#57#, 16#B9#, 16#86#, 16#C1#, 16#1D#, 16#9E#,
      16#E1#, 16#F8#, 16#98#, 16#11#, 16#69#, 16#D9#, 16#8E#, 16#94#,
      16#9B#, 16#1E#, 16#87#, 16#E9#, 16#CE#, 16#55#, 16#28#, 16#DF#,
      16#8C#, 16#A1#, 16#89#, 16#0D#, 16#BF#, 16#E6#, 16#42#, 16#68#,
      16#41#, 16#99#, 16#2D#, 16#0F#, 16#B0#, 16#54#, 16#BB#, 16#16#);

   Inv_Sbox : constant array (Natural range 0 .. 255) of Unsigned_8 :=
     (      16#52#, 16#09#, 16#6A#, 16#D5#, 16#30#, 16#36#, 16#A5#, 16#38#,
      16#BF#, 16#40#, 16#A3#, 16#9E#, 16#81#, 16#F3#, 16#D7#, 16#FB#,
      16#7C#, 16#E3#, 16#39#, 16#82#, 16#9B#, 16#2F#, 16#FF#, 16#87#,
      16#34#, 16#8E#, 16#43#, 16#44#, 16#C4#, 16#DE#, 16#E9#, 16#CB#,
      16#54#, 16#7B#, 16#94#, 16#32#, 16#A6#, 16#C2#, 16#23#, 16#3D#,
      16#EE#, 16#4C#, 16#95#, 16#0B#, 16#42#, 16#FA#, 16#C3#, 16#4E#,
      16#08#, 16#2E#, 16#A1#, 16#66#, 16#28#, 16#D9#, 16#24#, 16#B2#,
      16#76#, 16#5B#, 16#A2#, 16#49#, 16#6D#, 16#8B#, 16#D1#, 16#25#,
      16#72#, 16#F8#, 16#F6#, 16#64#, 16#86#, 16#68#, 16#98#, 16#16#,
      16#D4#, 16#A4#, 16#5C#, 16#CC#, 16#5D#, 16#65#, 16#B6#, 16#92#,
      16#6C#, 16#70#, 16#48#, 16#50#, 16#FD#, 16#ED#, 16#B9#, 16#DA#,
      16#5E#, 16#15#, 16#46#, 16#57#, 16#A7#, 16#8D#, 16#9D#, 16#84#,
      16#90#, 16#D8#, 16#AB#, 16#00#, 16#8C#, 16#BC#, 16#D3#, 16#0A#,
      16#F7#, 16#E4#, 16#58#, 16#05#, 16#B8#, 16#B3#, 16#45#, 16#06#,
      16#D0#, 16#2C#, 16#1E#, 16#8F#, 16#CA#, 16#3F#, 16#0F#, 16#02#,
      16#C1#, 16#AF#, 16#BD#, 16#03#, 16#01#, 16#13#, 16#8A#, 16#6B#,
      16#3A#, 16#91#, 16#11#, 16#41#, 16#4F#, 16#67#, 16#DC#, 16#EA#,
      16#97#, 16#F2#, 16#CF#, 16#CE#, 16#F0#, 16#B4#, 16#E6#, 16#73#,
      16#96#, 16#AC#, 16#74#, 16#22#, 16#E7#, 16#AD#, 16#35#, 16#85#,
      16#E2#, 16#F9#, 16#37#, 16#E8#, 16#1C#, 16#75#, 16#DF#, 16#6E#,
      16#47#, 16#F1#, 16#1A#, 16#71#, 16#1D#, 16#29#, 16#C5#, 16#89#,
      16#6F#, 16#B7#, 16#62#, 16#0E#, 16#AA#, 16#18#, 16#BE#, 16#1B#,
      16#FC#, 16#56#, 16#3E#, 16#4B#, 16#C6#, 16#D2#, 16#79#, 16#20#,
      16#9A#, 16#DB#, 16#C0#, 16#FE#, 16#78#, 16#CD#, 16#5A#, 16#F4#,
      16#1F#, 16#DD#, 16#A8#, 16#33#, 16#88#, 16#07#, 16#C7#, 16#31#,
      16#B1#, 16#12#, 16#10#, 16#59#, 16#27#, 16#80#, 16#EC#, 16#5F#,
      16#60#, 16#51#, 16#7F#, 16#A9#, 16#19#, 16#B5#, 16#4A#, 16#0D#,
      16#2D#, 16#E5#, 16#7A#, 16#9F#, 16#93#, 16#C9#, 16#9C#, 16#EF#,
      16#A0#, 16#E0#, 16#3B#, 16#4D#, 16#AE#, 16#2A#, 16#F5#, 16#B0#,
      16#C8#, 16#EB#, 16#BB#, 16#3C#, 16#83#, 16#53#, 16#99#, 16#61#,
      16#17#, 16#2B#, 16#04#, 16#7E#, 16#BA#, 16#77#, 16#D6#, 16#26#,
      16#E1#, 16#69#, 16#14#, 16#63#, 16#55#, 16#21#, 16#0C#, 16#7D#);

   Rcon : constant array (Positive range 1 .. 10) of Unsigned_8 :=
     (16#01#, 16#02#, 16#04#, 16#08#, 16#10#, 16#20#, 16#40#, 16#80#,
      16#1B#, 16#36#);

   function XTime (X : Unsigned_8) return Unsigned_8 is
     (Shift_Left (X, 1) xor (if X >= 16#80# then 16#1B# else 0));

   function GF_Mul (X, Y : Unsigned_8) return Unsigned_8 is
      A : Unsigned_8 := X;
      B : Unsigned_8 := Y;
      R : Unsigned_8 := 0;
   begin
      for I in 0 .. 7 loop
         if (B and 1) /= 0 then
            R := R xor A;
         end if;
         A := XTime (A);
         B := Shift_Right (B, 1);
      end loop;
      return R;
   end GF_Mul;

   function Sub_Word (W : Unsigned_32) return Unsigned_32 is
   begin
      return Shift_Left (Unsigned_32 (Sbox (Natural (Shift_Right (W, 24)))), 24)
        or Shift_Left (Unsigned_32 (Sbox (Natural (Shift_Right (W, 16) and 16#FF#))), 16)
        or Shift_Left (Unsigned_32 (Sbox (Natural (Shift_Right (W, 8) and 16#FF#))), 8)
        or Unsigned_32 (Sbox (Natural (W and 16#FF#)));
   end Sub_Word;

   procedure Expand (Key : Byte_Slice; B : out Block) is
      Nk : constant Natural := Natural (Byte_Vectors.Length (Key)) / 4;
   begin
      B.Nr := Nk + 6;
      for I in 0 .. Nk - 1 loop
         B.W (I) :=
           Shift_Left (Unsigned_32 (Character'Pos (Byte_Vectors.Element (Key, 4 * I + 1))), 24)
           or Shift_Left (Unsigned_32 (Character'Pos (Byte_Vectors.Element (Key, 4 * I + 2))), 16)
           or Shift_Left (Unsigned_32 (Character'Pos (Byte_Vectors.Element (Key, 4 * I + 3))), 8)
           or Unsigned_32 (Character'Pos (Byte_Vectors.Element (Key, 4 * I + 4)));
      end loop;
      for I in Nk .. 4 * (B.Nr + 1) - 1 loop
         declare
            T : Unsigned_32 := B.W (I - 1);
         begin
            if I mod Nk = 0 then
               T := Sub_Word (Rotate_Left (T, 8))
                 xor Shift_Left (Unsigned_32 (Rcon (I / Nk)), 24);
            elsif Nk > 6 and I mod Nk = 4 then
               T := Sub_Word (T);
            end if;
            B.W (I) := B.W (I - Nk) xor T;
         end;
      end loop;
   end Expand;

   function To_State (Src : Byte16) return State is
      S : State;
   begin
      for C in 0 .. 3 loop
         for R in 0 .. 3 loop
            S (R, C) := Src (4 * C + R);
         end loop;
      end loop;
      return S;
   end To_State;

   function To_Block16 (S : State) return Byte16 is
      B : Byte16;
   begin
      for C in 0 .. 3 loop
         for R in 0 .. 3 loop
            B (4 * C + R) := S (R, C);
         end loop;
      end loop;
      return B;
   end To_Block16;

   procedure Add_Round_Key (S : in out State; W : Key_Schedule;
                            Round : Natural) is
   begin
      for C in 0 .. 3 loop
         declare
            K : constant Unsigned_32 := W (4 * Round + C);
         begin
            for R in 0 .. 3 loop
               S (R, C) := S (R, C)
                 xor Unsigned_8 (Shift_Right (K, 8 * (3 - R)) and 16#FF#);
            end loop;
         end;
      end loop;
   end Add_Round_Key;

   procedure Sub_Bytes (S : in out State) is
   begin
      for R in 0 .. 3 loop
         for C in 0 .. 3 loop
            S (R, C) := Sbox (Natural (S (R, C)));
         end loop;
      end loop;
   end Sub_Bytes;

   procedure Inv_Sub_Bytes (S : in out State) is
   begin
      for R in 0 .. 3 loop
         for C in 0 .. 3 loop
            S (R, C) := Inv_Sbox (Natural (S (R, C)));
         end loop;
      end loop;
   end Inv_Sub_Bytes;

   procedure Shift_Rows (S : in out State) is
      T : State;
   begin
      for R in 0 .. 3 loop
         for C in 0 .. 3 loop
            T (R, C) := S (R, (C + R) mod 4);
         end loop;
      end loop;
      S := T;
   end Shift_Rows;

   procedure Inv_Shift_Rows (S : in out State) is
      T : State;
   begin
      for R in 0 .. 3 loop
         for C in 0 .. 3 loop
            T (R, C) := S (R, (C + 4 - R) mod 4);
         end loop;
      end loop;
      S := T;
   end Inv_Shift_Rows;

   procedure Mix_Columns (S : in out State) is
   begin
      for C in 0 .. 3 loop
         declare
            A0 : constant Unsigned_8 := S (0, C);
            A1 : constant Unsigned_8 := S (1, C);
            A2 : constant Unsigned_8 := S (2, C);
            A3 : constant Unsigned_8 := S (3, C);
         begin
            S (0, C) := GF_Mul (A0, 2) xor GF_Mul (A1, 3) xor A2 xor A3;
            S (1, C) := A0 xor GF_Mul (A1, 2) xor GF_Mul (A2, 3) xor A3;
            S (2, C) := A0 xor A1 xor GF_Mul (A2, 2) xor GF_Mul (A3, 3);
            S (3, C) := GF_Mul (A0, 3) xor A1 xor A2 xor GF_Mul (A3, 2);
         end;
      end loop;
   end Mix_Columns;

   procedure Inv_Mix_Columns (S : in out State) is
   begin
      for C in 0 .. 3 loop
         declare
            A0 : constant Unsigned_8 := S (0, C);
            A1 : constant Unsigned_8 := S (1, C);
            A2 : constant Unsigned_8 := S (2, C);
            A3 : constant Unsigned_8 := S (3, C);
         begin
            S (0, C) := GF_Mul (A0, 14) xor GF_Mul (A1, 11) xor GF_Mul (A2, 13)
                         xor GF_Mul (A3, 9);
            S (1, C) := GF_Mul (A0, 9) xor GF_Mul (A1, 14) xor GF_Mul (A2, 11)
                         xor GF_Mul (A3, 13);
            S (2, C) := GF_Mul (A0, 13) xor GF_Mul (A1, 9) xor GF_Mul (A2, 14)
                         xor GF_Mul (A3, 11);
            S (3, C) := GF_Mul (A0, 11) xor GF_Mul (A1, 13) xor GF_Mul (A2, 9)
                         xor GF_Mul (A3, 14);
         end;
      end loop;
   end Inv_Mix_Columns;

   procedure Encrypt_Block (B : Block; Src : Byte16; Dst : out Byte16) is
      S : State := To_State (Src);
   begin
      Add_Round_Key (S, B.W, 0);
      for R in 1 .. B.Nr - 1 loop
         Sub_Bytes (S);
         Shift_Rows (S);
         Mix_Columns (S);
         Add_Round_Key (S, B.W, R);
      end loop;
      Sub_Bytes (S);
      Shift_Rows (S);
      Add_Round_Key (S, B.W, B.Nr);
      Dst := To_Block16 (S);
   end Encrypt_Block;

   procedure Decrypt_Block (B : Block; Src : Byte16; Dst : out Byte16) is
      S : State := To_State (Src);
   begin
      Add_Round_Key (S, B.W, B.Nr);
      for R in reverse 1 .. B.Nr - 1 loop
         Inv_Shift_Rows (S);
         Inv_Sub_Bytes (S);
         Add_Round_Key (S, B.W, R);
         Inv_Mix_Columns (S);
      end loop;
      Inv_Shift_Rows (S);
      Inv_Sub_Bytes (S);
      Add_Round_Key (S, B.W, 0);
      Dst := To_Block16 (S);
   end Decrypt_Block;

   function To_Byte16 (Src : Byte_Slice) return Byte16 is
      B : Byte16;
   begin
      for I in 0 .. 15 loop
         B (I) := Unsigned_8 (Character'Pos (Byte_Vectors.Element (Src, I + 1)));
      end loop;
      return B;
   end To_Byte16;

   function To_Bytes (B : Byte16) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      for I in 0 .. 15 loop
         Byte_Vectors.Append (R, Character'Val (B (I)));
      end loop;
      return R;
   end To_Bytes;

   function New_Cipher (Key : Byte_Slice) return Block is
      N : constant Natural := Natural (Byte_Vectors.Length (Key));
      B : Block := (Nr => 10, W => (others => 0));
   begin
      if N /= 16 and then N /= 24 and then N /= 32 then
         raise Constraint_Error
           with "aes: invalid key size " & Natural'Image (N)
                & " (want 16, 24 or 32 bytes)";
      end if;
      Expand (Key, B);
      return B;
   end New_Cipher;

   function Block_Size (B : Block) return Natural is
      pragma Unreferenced (B);
   begin
      return 16;
   end Block_Size;

   function Encrypt (B : Block; Src : Byte_Slice) return Byte_Slice is
      R : Byte16;
   begin
      if Natural (Byte_Vectors.Length (Src)) /= 16 then
         raise Constraint_Error with "aes: Encrypt wants exactly one block";
      end if;
      Encrypt_Block (B, To_Byte16 (Src), R);
      return To_Bytes (R);
   end Encrypt;

   function Decrypt (B : Block; Src : Byte_Slice) return Byte_Slice is
      R : Byte16;
   begin
      if Natural (Byte_Vectors.Length (Src)) /= 16 then
         raise Constraint_Error with "aes: Decrypt wants exactly one block";
      end if;
      Decrypt_Block (B, To_Byte16 (Src), R);
      return To_Bytes (R);
   end Decrypt;

end Gada.Std.Crypto.Aes;
