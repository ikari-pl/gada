--  Body of Std_Encoding_Suite — see spec. All expected values pinned
--  from Go 1.27 via `go run`.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces; use Interfaces;

with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Encoding.Base64;
with Gada.Std.Encoding.Hex;
with Gada.Std.Encoding.Binary;

package body Std_Encoding_Suite is

   overriding function Name
     (T : Std_Encoding_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Encoding suite (PKG=stdlib.encoding)"));

   overriding procedure Register_Tests (T : in out Std_Encoding_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Base64'Access, "base64 std/url/raw vectors");
      Register_Routine (T, Test_Hex'Access, "hex vectors");
      Register_Routine (T, Test_Binary'Access, "binary fixed + varint");
      Register_Routine (T, Test_Errors'Access, "error paths raise");
   end Register_Tests;

   function To_Hex (B : Byte_Slice) return String is
      Hex : constant String := "0123456789abcdef";
      R   : String (1 .. 2 * Natural (Byte_Vectors.Length (B)));
   begin
      for I in 1 .. Natural (Byte_Vectors.Length (B)) loop
         declare
            V : constant Natural :=
              Character'Pos (Byte_Vectors.Element (B, I));
         begin
            R (2 * I - 1) := Hex (V / 16 + 1);
            R (2 * I)     := Hex (V mod 16 + 1);
         end;
      end loop;
      return R;
   end To_Hex;

   function From_Hex (S : String) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;

      function Nib (C : Character) return Natural is
        (if C in '0' .. '9' then Character'Pos (C) - Character'Pos ('0')
         else Character'Pos (C) - Character'Pos ('a') + 10);
   begin
      for I in 1 .. S'Length / 2 loop
         Byte_Vectors.Append
           (R, Character'Val (Nib (S (2 * I - 1)) * 16 + Nib (S (2 * I))));
      end loop;
      return R;
   end From_Hex;

   type B64_Vec is record
      In_Bytes, Std, URL, Raw, RawURL : Unbounded_String;
   end record;
   B64_Vecs : constant array (Positive range <>) of B64_Vec :=
     (      (To_Unbounded_String (""),
       To_Unbounded_String (""),
       To_Unbounded_String (""),
       To_Unbounded_String (""),
       To_Unbounded_String ("")),
      (To_Unbounded_String ("40"),
       To_Unbounded_String ("QA=="),
       To_Unbounded_String ("QA=="),
       To_Unbounded_String ("QA"),
       To_Unbounded_String ("QA")),
      (To_Unbounded_String ("4041"),
       To_Unbounded_String ("QEE="),
       To_Unbounded_String ("QEE="),
       To_Unbounded_String ("QEE"),
       To_Unbounded_String ("QEE")),
      (To_Unbounded_String ("404142"),
       To_Unbounded_String ("QEFC"),
       To_Unbounded_String ("QEFC"),
       To_Unbounded_String ("QEFC"),
       To_Unbounded_String ("QEFC")),
      (To_Unbounded_String ("40414243"),
       To_Unbounded_String ("QEFCQw=="),
       To_Unbounded_String ("QEFCQw=="),
       To_Unbounded_String ("QEFCQw"),
       To_Unbounded_String ("QEFCQw")),
      (To_Unbounded_String ("4041424344"),
       To_Unbounded_String ("QEFCQ0Q="),
       To_Unbounded_String ("QEFCQ0Q="),
       To_Unbounded_String ("QEFCQ0Q"),
       To_Unbounded_String ("QEFCQ0Q")),
      (To_Unbounded_String ("404142434445"),
       To_Unbounded_String ("QEFCQ0RF"),
       To_Unbounded_String ("QEFCQ0RF"),
       To_Unbounded_String ("QEFCQ0RF"),
       To_Unbounded_String ("QEFCQ0RF")),
      (To_Unbounded_String ("40414243444546"),
       To_Unbounded_String ("QEFCQ0RFRg=="),
       To_Unbounded_String ("QEFCQ0RFRg=="),
       To_Unbounded_String ("QEFCQ0RFRg"),
       To_Unbounded_String ("QEFCQ0RFRg")),
      (To_Unbounded_String ("4041424344454647"),
       To_Unbounded_String ("QEFCQ0RFRkc="),
       To_Unbounded_String ("QEFCQ0RFRkc="),
       To_Unbounded_String ("QEFCQ0RFRkc"),
       To_Unbounded_String ("QEFCQ0RFRkc")),
      (To_Unbounded_String ("fbfffe"),
       To_Unbounded_String ("+//+"),
       To_Unbounded_String ("-__-"),
       To_Unbounded_String ("+//+"),
       To_Unbounded_String ("-__-")),
      (To_Unbounded_String ("fbfffefdfc"),
       To_Unbounded_String ("+//+/fw="),
       To_Unbounded_String ("-__-_fw="),
       To_Unbounded_String ("+//+/fw"),
       To_Unbounded_String ("-__-_fw")));

   type Hex_Vec is record
      In_Bytes, Enc : Unbounded_String;
   end record;
   Hex_Vecs : constant array (Positive range <>) of Hex_Vec :=
     (      (To_Unbounded_String (""), To_Unbounded_String ("")),
      (To_Unbounded_String ("40"), To_Unbounded_String ("40")),
      (To_Unbounded_String ("4041"), To_Unbounded_String ("4041")),
      (To_Unbounded_String ("404142"), To_Unbounded_String ("404142")),
      (To_Unbounded_String ("40414243"), To_Unbounded_String ("40414243")),
      (To_Unbounded_String ("4041424344"), To_Unbounded_String ("4041424344")),
      (To_Unbounded_String ("404142434445"), To_Unbounded_String ("404142434445")),
      (To_Unbounded_String ("40414243444546"), To_Unbounded_String ("40414243444546")),
      (To_Unbounded_String ("4041424344454647"), To_Unbounded_String ("4041424344454647")),
      (To_Unbounded_String ("fbfffe"), To_Unbounded_String ("fbfffe")),
      (To_Unbounded_String ("fbfffefdfc"), To_Unbounded_String ("fbfffefdfc")));

   type Bin_Vec is record
      V : Unbounded_String;  --  decimal value
      BE, LE : Unbounded_String;  --  encoded bytes, hex
   end record;
   Bin16_Vecs : constant array (Positive range <>) of Bin_Vec :=
     (      (To_Unbounded_String ("0"),
       To_Unbounded_String ("0000"),
       To_Unbounded_String ("0000")),
      (To_Unbounded_String ("1"),
       To_Unbounded_String ("0001"),
       To_Unbounded_String ("0100")),
      (To_Unbounded_String ("258"),
       To_Unbounded_String ("0102"),
       To_Unbounded_String ("0201")),
      (To_Unbounded_String ("1800"),
       To_Unbounded_String ("0708"),
       To_Unbounded_String ("0807")),
      (To_Unbounded_String ("65535"),
       To_Unbounded_String ("ffff"),
       To_Unbounded_String ("ffff")),
      (To_Unbounded_String ("300"),
       To_Unbounded_String ("012c"),
       To_Unbounded_String ("2c01")));
   Bin32_Vecs : constant array (Positive range <>) of Bin_Vec :=
     (      (To_Unbounded_String ("0"),
       To_Unbounded_String ("00000000"),
       To_Unbounded_String ("00000000")),
      (To_Unbounded_String ("1"),
       To_Unbounded_String ("00000001"),
       To_Unbounded_String ("01000000")),
      (To_Unbounded_String ("258"),
       To_Unbounded_String ("00000102"),
       To_Unbounded_String ("02010000")),
      (To_Unbounded_String ("84281096"),
       To_Unbounded_String ("05060708"),
       To_Unbounded_String ("08070605")),
      (To_Unbounded_String ("4294967295"),
       To_Unbounded_String ("ffffffff"),
       To_Unbounded_String ("ffffffff")),
      (To_Unbounded_String ("300"),
       To_Unbounded_String ("0000012c"),
       To_Unbounded_String ("2c010000")));
   Bin64_Vecs : constant array (Positive range <>) of Bin_Vec :=
     (      (To_Unbounded_String ("0"),
       To_Unbounded_String ("0000000000000000"),
       To_Unbounded_String ("0000000000000000")),
      (To_Unbounded_String ("1"),
       To_Unbounded_String ("0000000000000001"),
       To_Unbounded_String ("0100000000000000")),
      (To_Unbounded_String ("258"),
       To_Unbounded_String ("0000000000000102"),
       To_Unbounded_String ("0201000000000000")),
      (To_Unbounded_String ("72623859790382856"),
       To_Unbounded_String ("0102030405060708"),
       To_Unbounded_String ("0807060504030201")),
      (To_Unbounded_String ("18446744073709551615"),
       To_Unbounded_String ("ffffffffffffffff"),
       To_Unbounded_String ("ffffffffffffffff")),
      (To_Unbounded_String ("300"),
       To_Unbounded_String ("000000000000012c"),
       To_Unbounded_String ("2c01000000000000")));

   type Var_Vec is record
      V : Unbounded_String;  --  decimal (signed for varint)
      Enc : Unbounded_String;  --  encoded bytes, hex
      N : Natural;
   end record;
   Uvar_Vecs : constant array (Positive range <>) of Var_Vec :=
     (      (To_Unbounded_String ("0"), To_Unbounded_String ("00"), 1),
      (To_Unbounded_String ("1"), To_Unbounded_String ("01"), 1),
      (To_Unbounded_String ("127"), To_Unbounded_String ("7f"), 1),
      (To_Unbounded_String ("128"), To_Unbounded_String ("8001"), 2),
      (To_Unbounded_String ("300"), To_Unbounded_String ("ac02"), 2),
      (To_Unbounded_String ("16384"), To_Unbounded_String ("808001"), 3),
      (To_Unbounded_String ("4294967295"), To_Unbounded_String ("ffffffff0f"), 5),
      (To_Unbounded_String ("18446744073709551615"), To_Unbounded_String ("ffffffffffffffffff01"), 10));
   Var_Vecs : constant array (Positive range <>) of Var_Vec :=
     (      (To_Unbounded_String ("0"), To_Unbounded_String ("00"), 1),
      (To_Unbounded_String ("1"), To_Unbounded_String ("02"), 1),
      (To_Unbounded_String ("-1"), To_Unbounded_String ("01"), 1),
      (To_Unbounded_String ("63"), To_Unbounded_String ("7e"), 1),
      (To_Unbounded_String ("-64"), To_Unbounded_String ("7f"), 1),
      (To_Unbounded_String ("64"), To_Unbounded_String ("8001"), 2),
      (To_Unbounded_String ("-65"), To_Unbounded_String ("8101"), 2),
      (To_Unbounded_String ("300"), To_Unbounded_String ("d804"), 2),
      (To_Unbounded_String ("-300"), To_Unbounded_String ("d704"), 2),
      (To_Unbounded_String ("4611686018427387904"), To_Unbounded_String ("80808080808080808001"), 10),
      (To_Unbounded_String ("-4611686018427387904"), To_Unbounded_String ("ffffffffffffffff7f"), 9));

   procedure Test_Base64 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for V of B64_Vecs loop
         declare
            In_Bytes : constant Byte_Slice :=
              From_Hex (To_String (V.In_Bytes));
         begin
            Assert (Gada.Std.Encoding.Base64.Encode_Std (In_Bytes)
                      = To_String (V.Std), "std enc");
            Assert (Gada.Std.Encoding.Base64.Encode_URL (In_Bytes)
                      = To_String (V.URL), "url enc");
            Assert (Gada.Std.Encoding.Base64.Encode_Raw_Std (In_Bytes)
                      = To_String (V.Raw), "raw enc");
            Assert (Gada.Std.Encoding.Base64.Encode_Raw_URL (In_Bytes)
                      = To_String (V.RawURL), "rawurl enc");
            Assert (To_Hex (Gada.Std.Encoding.Base64.Decode_Std
                      (To_String (V.Std))) = To_String (V.In_Bytes),
                    "std dec");
            Assert (To_Hex (Gada.Std.Encoding.Base64.Decode_URL
                      (To_String (V.URL))) = To_String (V.In_Bytes),
                    "url dec");
            Assert (To_Hex (Gada.Std.Encoding.Base64.Decode_Raw_Std
                      (To_String (V.Raw))) = To_String (V.In_Bytes),
                    "raw dec");
            Assert (To_Hex (Gada.Std.Encoding.Base64.Decode_Raw_URL
                      (To_String (V.RawURL))) = To_String (V.In_Bytes),
                    "rawurl dec");
         end;
      end loop;
   end Test_Base64;

   procedure Test_Hex (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for V of Hex_Vecs loop
         declare
            In_Bytes : constant Byte_Slice :=
              From_Hex (To_String (V.In_Bytes));
         begin
            Assert (Gada.Std.Encoding.Hex.Encode_To_String (In_Bytes)
                      = To_String (V.Enc), "hex enc");
            Assert (To_Hex (Gada.Std.Encoding.Hex.Decode_String
                      (To_String (V.Enc))) = To_String (V.In_Bytes),
                    "hex dec");
         end;
      end loop;
      Assert (Gada.Std.Encoding.Hex.Encoded_Len (5) = 10, "Encoded_Len");
      Assert (Gada.Std.Encoding.Hex.Decoded_Len (10) = 5, "Decoded_Len");
   end Test_Hex;

   procedure Test_Binary (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for V of Bin16_Vecs loop
         declare
            Val : constant Unsigned_16 :=
              Unsigned_16'Value (To_String (V.V));
            Buf : Byte_Slice := Byte_Vectors.Empty_Vector;
         begin
            Assert (To_Hex (Gada.Std.Encoding.Binary.Encode_Uint16_BE (Val))
                      = To_String (V.BE), "u16 BE enc");
            Assert (To_Hex (Gada.Std.Encoding.Binary.Encode_Uint16_LE (Val))
                      = To_String (V.LE), "u16 LE enc");
            Assert (Gada.Std.Encoding.Binary.Uint16_BE
                      (From_Hex (To_String (V.BE))) = Val, "u16 BE dec");
            Assert (Gada.Std.Encoding.Binary.Uint16_LE
                      (From_Hex (To_String (V.LE))) = Val, "u16 LE dec");
            Gada.Std.Encoding.Binary.Append_Uint16_BE (Buf, Val);
            Assert (To_Hex (Buf) = To_String (V.BE), "u16 BE append");
         end;
      end loop;
      for V of Bin32_Vecs loop
         declare
            Val : constant Unsigned_32 :=
              Unsigned_32'Value (To_String (V.V));
            Buf : Byte_Slice := Byte_Vectors.Empty_Vector;
         begin
            Assert (To_Hex (Gada.Std.Encoding.Binary.Encode_Uint32_BE (Val))
                      = To_String (V.BE), "u32 BE enc");
            Assert (To_Hex (Gada.Std.Encoding.Binary.Encode_Uint32_LE (Val))
                      = To_String (V.LE), "u32 LE enc");
            Assert (Gada.Std.Encoding.Binary.Uint32_BE
                      (From_Hex (To_String (V.BE))) = Val, "u32 BE dec");
            Assert (Gada.Std.Encoding.Binary.Uint32_LE
                      (From_Hex (To_String (V.LE))) = Val, "u32 LE dec");
            Gada.Std.Encoding.Binary.Append_Uint32_LE (Buf, Val);
            Assert (To_Hex (Buf) = To_String (V.LE), "u32 LE append");
         end;
      end loop;
      for V of Bin64_Vecs loop
         declare
            Val : constant Unsigned_64 :=
              Unsigned_64'Value (To_String (V.V));
            Buf : Byte_Slice := Byte_Vectors.Empty_Vector;
         begin
            Assert (To_Hex (Gada.Std.Encoding.Binary.Encode_Uint64_BE (Val))
                      = To_String (V.BE), "u64 BE enc");
            Assert (To_Hex (Gada.Std.Encoding.Binary.Encode_Uint64_LE (Val))
                      = To_String (V.LE), "u64 LE enc");
            Assert (Gada.Std.Encoding.Binary.Uint64_BE
                      (From_Hex (To_String (V.BE))) = Val, "u64 BE dec");
            Assert (Gada.Std.Encoding.Binary.Uint64_LE
                      (From_Hex (To_String (V.LE))) = Val, "u64 LE dec");
            Gada.Std.Encoding.Binary.Append_Uint64_BE (Buf, Val);
            Assert (To_Hex (Buf) = To_String (V.BE), "u64 BE append");
         end;
      end loop;
      for V of Uvar_Vecs loop
         declare
            Val : constant Unsigned_64 :=
              Unsigned_64'Value (To_String (V.V));
            Buf : Byte_Slice := Byte_Vectors.Empty_Vector;
            Got : Unsigned_64;
            N   : Natural;
         begin
            Gada.Std.Encoding.Binary.Append_Uvarint (Buf, Val);
            Assert (To_Hex (Buf) = To_String (V.Enc), "uvarint enc");
            Assert (Integer (Byte_Vectors.Length (Buf)) = V.N, "uvarint n");
            Gada.Std.Encoding.Binary.Uvarint
              (From_Hex (To_String (V.Enc)), Got, N);
            Assert (Got = Val and then N = V.N, "uvarint dec");
         end;
      end loop;
      for V of Var_Vecs loop
         declare
            Val : constant Integer_64 :=
              Integer_64'Value (To_String (V.V));
            Buf : Byte_Slice := Byte_Vectors.Empty_Vector;
            Got : Integer_64;
            N   : Natural;
         begin
            Gada.Std.Encoding.Binary.Append_Varint (Buf, Val);
            Assert (To_Hex (Buf) = To_String (V.Enc), "varint enc");
            Gada.Std.Encoding.Binary.Varint
              (From_Hex (To_String (V.Enc)), Got, N);
            Assert (Got = Val and then N = V.N, "varint dec");
         end;
      end loop;
      --  empty buffer: Go returns (0, 0)
      declare
         Got : Unsigned_64;
         N   : Natural;
      begin
         Gada.Std.Encoding.Binary.Uvarint
           (Byte_Vectors.Empty_Vector, Got, N);
         Assert (Got = 0 and then N = 0, "uvarint empty");
      end;
   end Test_Binary;

   procedure Test_Errors (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  base64: illegal character
      begin
         declare
            R : constant Byte_Slice :=
              Gada.Std.Encoding.Base64.Decode_Std ("Q!AA");
            pragma Unreferenced (R);
         begin
            Assert (False, "illegal base64 char must raise");
         end;
      exception
         when Constraint_Error => null;
      end;
      --  base64: '=' in a raw encoding
      begin
         declare
            R : constant Byte_Slice :=
              Gada.Std.Encoding.Base64.Decode_Raw_Std ("QA==");
            pragma Unreferenced (R);
         begin
            Assert (False, "raw base64 with padding must raise");
         end;
      exception
         when Constraint_Error => null;
      end;
      --  base64: padded length not a multiple of 4
      begin
         declare
            R : constant Byte_Slice :=
              Gada.Std.Encoding.Base64.Decode_Std ("Q");
            pragma Unreferenced (R);
         begin
            Assert (False, "bad padded length must raise");
         end;
      exception
         when Constraint_Error => null;
      end;
      --  hex: odd length and illegal char
      begin
         declare
            R : constant Byte_Slice :=
              Gada.Std.Encoding.Hex.Decode_String ("abc");
            pragma Unreferenced (R);
         begin
            Assert (False, "odd hex must raise");
         end;
      exception
         when Constraint_Error => null;
      end;
      begin
         declare
            R : constant Byte_Slice :=
              Gada.Std.Encoding.Hex.Decode_String ("zz");
            pragma Unreferenced (R);
         begin
            Assert (False, "illegal hex char must raise");
         end;
      exception
         when Constraint_Error => null;
      end;
      --  uvarint: truncated and overflow
      begin
         declare
            V : Unsigned_64;
            N : Natural;
         begin
            Gada.Std.Encoding.Binary.Uvarint (From_Hex ("80"), V, N);
            pragma Unreferenced (V, N);
            Assert (False, "truncated uvarint must raise");
         end;
      exception
         when Constraint_Error => null;
      end;
      begin
         declare
            V : Unsigned_64;
            N : Natural;
         begin
            Gada.Std.Encoding.Binary.Uvarint
              (From_Hex ("80808080808080808002"), V, N);
            pragma Unreferenced (V, N);
            Assert (False, "overflowing uvarint must raise");
         end;
      exception
         when Constraint_Error => null;
      end;
      --  fixed-width read on a short buffer
      begin
         declare
            V : constant Unsigned_32 :=
              Gada.Std.Encoding.Binary.Uint32_BE (New_Bytes (2));
            pragma Unreferenced (V);
         begin
            Assert (False, "short buffer must raise");
         end;
      exception
         when Constraint_Error => null;
      end;
   end Test_Errors;

end Std_Encoding_Suite;
