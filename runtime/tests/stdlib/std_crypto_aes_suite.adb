--  Body of Std_Crypto_Aes_Suite — see spec for test rationale. All
--  expected values pinned from Go 1.27 via `go run`.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Crypto.Aes;
with Gada.Std.Crypto.Cipher;

package body Std_Crypto_Aes_Suite is

   overriding function Name
     (T : Std_Crypto_Aes_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Crypto.Aes/Cipher suite (PKG=stdlib.crypto.aes)"));

   overriding procedure Register_Tests (T : in out Std_Crypto_Aes_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Ecb_Kat'Access, "FIPS-197 ECB KAT 128/192/256");
      Register_Routine (T, Test_Cbc'Access, "SP 800-38A CBC 128/192/256");
      Register_Routine (T, Test_Ctr'Access, "SP 800-38A CTR 128/192/256");
      Register_Routine (T, Test_Gcm'Access, "GCM seal/open vectors");
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

   type Ecb_Vec is record
      Name : Unbounded_String;
      Key, Pt, Ct : Unbounded_String;
   end record;
   Ecb_Vecs : constant array (Positive range <>) of Ecb_Vec :=
     (      (To_Unbounded_String ("ecb128"),
       To_Unbounded_String ("000102030405060708090a0b0c0d0e0f"),
       To_Unbounded_String ("00112233445566778899aabbccddeeff"),
       To_Unbounded_String ("69c4e0d86a7b0430d8cdb78070b4c55a")),
      (To_Unbounded_String ("ecb192"),
       To_Unbounded_String ("000102030405060708090a0b0c0d0e0f1011121314151617"),
       To_Unbounded_String ("00112233445566778899aabbccddeeff"),
       To_Unbounded_String ("dda97ca4864cdfe06eaf70a0ec0d7191")),
      (To_Unbounded_String ("ecb256"),
       To_Unbounded_String ("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"),
       To_Unbounded_String ("00112233445566778899aabbccddeeff"),
       To_Unbounded_String ("8ea2b7ca516745bfeafc49904b496089")));

   type Mode_Vec is record
      Bits : Unbounded_String;
      Key, Iv, Pt, Ct : Unbounded_String;
   end record;
   Cbc_Vecs : constant array (Positive range <>) of Mode_Vec :=
     (      (To_Unbounded_String ("128"),
       To_Unbounded_String ("2b7e151628aed2a6abf7158809cf4f3c"),
       To_Unbounded_String ("000102030405060708090a0b0c0d0e0f"),
       To_Unbounded_String ("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66bc90a"),
       To_Unbounded_String ("7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b273bed6b8e3c1743b7116e69e22229516ddba83e673714b12b8c54269b3e295c0")),
      (To_Unbounded_String ("192"),
       To_Unbounded_String ("2b7e151628aed2a6abf7158809cf4f3ca0a1a2a3a4a5a6a7"),
       To_Unbounded_String ("000102030405060708090a0b0c0d0e0f"),
       To_Unbounded_String ("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66bc90a"),
       To_Unbounded_String ("464919b950fc3692cf41b803c5e3b05934269211e68784adfd6b7b895c0a65b363e4d5689aeb357ed53f055a45aadae7fab7385620d68f649f018793e85471c0")),
      (To_Unbounded_String ("256"),
       To_Unbounded_String ("2b7e151628aed2a6abf7158809cf4f3ca0a1a2a3a4a5a6a7a8a9aaabacadaeaf"),
       To_Unbounded_String ("000102030405060708090a0b0c0d0e0f"),
       To_Unbounded_String ("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66bc90a"),
       To_Unbounded_String ("4ba69d06714af50bfe160bd4a5e78ef7926d97d5f17f93e79833f7b4bd58d455a7207b5eb56e95100c444b486870c6be59517727b214a1fa53264cf76713d59c")));
   Ctr_Vecs : constant array (Positive range <>) of Mode_Vec :=
     (      (To_Unbounded_String ("128"),
       To_Unbounded_String ("2b7e151628aed2a6abf7158809cf4f3c"),
       To_Unbounded_String ("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"),
       To_Unbounded_String ("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66bc90a"),
       To_Unbounded_String ("874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff5ae4df3edbd5d35e5b4f09020db03eab1e031dda2fbe03d1792170a0f30762f4")),
      (To_Unbounded_String ("192"),
       To_Unbounded_String ("2b7e151628aed2a6abf7158809cf4f3ca0a1a2a3a4a5a6a7"),
       To_Unbounded_String ("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"),
       To_Unbounded_String ("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66bc90a"),
       To_Unbounded_String ("3beb16622e5fb743b8cafed386d444ebf4e89ce276526a4d38344703e57a06fc374df9a4b7d971127323edf5f40f68ee259add01374d53c1a8d6421b2f94ddb8")),
      (To_Unbounded_String ("256"),
       To_Unbounded_String ("2b7e151628aed2a6abf7158809cf4f3ca0a1a2a3a4a5a6a7a8a9aaabacadaeaf"),
       To_Unbounded_String ("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"),
       To_Unbounded_String ("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66bc90a"),
       To_Unbounded_String ("e7069ae9e925be2de0616fcf87e722cf40592948cdb5d3ac8f3356da802a0bc3cfdde90191b0299843dad64cbb503efe997e2495e0a681cf078595f55d07817c")));

   type Gcm_Vec is record
      Name : Unbounded_String;
      Key, Nonce, Pt, Aad, Sealed : Unbounded_String;
   end record;
   Gcm_Vecs : constant array (Positive range <>) of Gcm_Vec :=
     (      (To_Unbounded_String ("gcm-empty"),
       To_Unbounded_String ("00000000000000000000000000000000"),
       To_Unbounded_String ("000000000000000000000000"),
       To_Unbounded_String (""),
       To_Unbounded_String (""),
       To_Unbounded_String ("58e2fccefa7e3061367f1d57a4e7455a")),
      (To_Unbounded_String ("gcm-1blk"),
       To_Unbounded_String ("00000000000000000000000000000000"),
       To_Unbounded_String ("000000000000000000000000"),
       To_Unbounded_String ("00000000000000000000000000000000"),
       To_Unbounded_String (""),
       To_Unbounded_String ("0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf")),
      (To_Unbounded_String ("gcm-aad"),
       To_Unbounded_String ("fefefefefefefefefefefefefefefefe"),
       To_Unbounded_String ("cafebabefacedbaddecaf888"),
       To_Unbounded_String ("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721d0c9e0f742b62225f65831c8a5374a10bac0b9e1a320a44512e"),
       To_Unbounded_String ("fefefefefefefefefefefefefefefefefefefefe"),
       To_Unbounded_String ("8d3ee22ec8f9269a339309df2d65408c456c01415f436234e6de118fc2b6a26e4e256ffe4f4d37c1fc7587d9366a76d026ca341495b7d1867e7beebbbb434dddedb380cdf850149bdba0")),
      (To_Unbounded_String ("gcm256"),
       To_Unbounded_String ("0101010101010101010101010101010101010101010101010101010101010101"),
       To_Unbounded_String ("020202020202020202020202"),
       To_Unbounded_String ("68656c6c6f20676164612067636d20776f726c642121"),
       To_Unbounded_String ("616164"),
       To_Unbounded_String ("6fb3a5252577a69cb7ad9caf3fcae2c5cdc7bd8bca9003ce5fad67db5e43458f2e76f4b333e0")));

   procedure Test_Ecb_Kat (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for V of Ecb_Vecs loop
         declare
            B  : constant Gada.Std.Crypto.Aes.Block :=
              Gada.Std.Crypto.Aes.New_Cipher (From_Hex (To_String (V.Key)));
            Pt : constant Byte_Slice := From_Hex (To_String (V.Pt));
         begin
            Assert (Gada.Std.Crypto.Aes.Block_Size (B) = 16, "Block_Size");
            Assert
              (To_Hex (Gada.Std.Crypto.Aes.Encrypt (B, Pt))
                 = To_String (V.Ct),
               "ECB encrypt " & To_String (V.Name));
            Assert
              (To_Hex (Gada.Std.Crypto.Aes.Decrypt
                 (B, From_Hex (To_String (V.Ct)))) = To_String (V.Pt),
               "ECB decrypt " & To_String (V.Name));
         end;
      end loop;
   end Test_Ecb_Kat;

   procedure Test_Cbc (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for V of Cbc_Vecs loop
         declare
            B   : constant Gada.Std.Crypto.Aes.Block :=
              Gada.Std.Crypto.Aes.New_Cipher (From_Hex (To_String (V.Key)));
            IV  : constant Byte_Slice := From_Hex (To_String (V.Iv));
            Pt  : constant Byte_Slice := From_Hex (To_String (V.Pt));
            E   : Gada.Std.Crypto.Cipher.Block_Mode :=
              Gada.Std.Crypto.Cipher.New_CBC_Encrypter (B, IV);
            D   : Gada.Std.Crypto.Cipher.Block_Mode :=
              Gada.Std.Crypto.Cipher.New_CBC_Decrypter (B, IV);
            Ct  : Byte_Slice;
            Rt  : Byte_Slice;
         begin
            Gada.Std.Crypto.Cipher.Crypt_Blocks (E, Ct, Pt);
            Assert (To_Hex (Ct) = To_String (V.Ct),
                    "CBC encrypt " & To_String (V.Bits));
            Gada.Std.Crypto.Cipher.Crypt_Blocks (D, Rt, Ct);
            Assert (To_Hex (Rt) = To_String (V.Pt),
                    "CBC decrypt " & To_String (V.Bits));
         end;
      end loop;
   end Test_Cbc;

   procedure Test_Ctr (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for V of Ctr_Vecs loop
         declare
            B  : constant Gada.Std.Crypto.Aes.Block :=
              Gada.Std.Crypto.Aes.New_Cipher (From_Hex (To_String (V.Key)));
            IV : constant Byte_Slice := From_Hex (To_String (V.Iv));
            Pt : constant Byte_Slice := From_Hex (To_String (V.Pt));
            S  : Gada.Std.Crypto.Cipher.Stream :=
              Gada.Std.Crypto.Cipher.New_CTR (B, IV);
            S2 : Gada.Std.Crypto.Cipher.Stream :=
              Gada.Std.Crypto.Cipher.New_CTR (B, IV);
            Ct : Byte_Slice;
            Rt : Byte_Slice;
         begin
            Gada.Std.Crypto.Cipher.XOR_Key_Stream (S, Ct, Pt);
            Assert (To_Hex (Ct) = To_String (V.Ct),
                    "CTR encrypt " & To_String (V.Bits));
            Gada.Std.Crypto.Cipher.XOR_Key_Stream (S2, Rt, Ct);
            Assert (To_Hex (Rt) = To_String (V.Pt),
                    "CTR decrypt " & To_String (V.Bits));
         end;
      end loop;
   end Test_Ctr;

   procedure Test_Gcm (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for V of Gcm_Vecs loop
         declare
            B : constant Gada.Std.Crypto.Aes.Block :=
              Gada.Std.Crypto.Aes.New_Cipher (From_Hex (To_String (V.Key)));
            G : constant Gada.Std.Crypto.Cipher.GCM :=
              Gada.Std.Crypto.Cipher.New_GCM (B);
            N : constant Byte_Slice := From_Hex (To_String (V.Nonce));
            P : constant Byte_Slice :=
              (if To_String (V.Pt)'Length = 0 then Byte_Vectors.Empty_Vector
               else From_Hex (To_String (V.Pt)));
            A : constant Byte_Slice :=
              (if To_String (V.Aad)'Length = 0 then Byte_Vectors.Empty_Vector
               else From_Hex (To_String (V.Aad)));
            Sealed : Byte_Slice;
         begin
            Assert (Gada.Std.Crypto.Cipher.Nonce_Size (G) = 12, "Nonce_Size");
            Assert (Gada.Std.Crypto.Cipher.Overhead (G) = 16, "Overhead");
            Sealed := Gada.Std.Crypto.Cipher.Seal (G, N, P, A);
            Assert (To_Hex (Sealed) = To_String (V.Sealed),
                    "GCM seal " & To_String (V.Name));
            Assert
              (To_Hex (Gada.Std.Crypto.Cipher.Open (G, N, Sealed, A))
                 = To_String (V.Pt),
               "GCM open " & To_String (V.Name));
         end;
      end loop;
      --  corrupted tag must raise (Go's Open error half)
      declare
         B : constant Gada.Std.Crypto.Aes.Block :=
           Gada.Std.Crypto.Aes.New_Cipher (From_Hex ("00" & "00" & "00" & "00" & "00" & "00" & "00" & "00" & "00" & "00" & "00" & "00" & "00" & "00" & "00" & "00"));
         G : constant Gada.Std.Crypto.Cipher.GCM :=
           Gada.Std.Crypto.Cipher.New_GCM (B);
         N : constant Byte_Slice := From_Hex ("000000000000000000000000");
         S : constant Byte_Slice :=
           Gada.Std.Crypto.Cipher.Seal (G, N, From_Hex ("00000000000000000000000000000000"), Byte_Vectors.Empty_Vector);
         Bad  : Byte_Slice := S;
         Last : constant Positive := Natural (Byte_Vectors.Length (Bad));
      begin
         Byte_Vectors.Replace_Element
           (Bad, Last,
            Character'Val
              (Character'Pos (Byte_Vectors.Element (Bad, Last)) xor 1));
         declare
            P : Byte_Slice := Gada.Std.Crypto.Cipher.Open (G, N, Bad, Byte_Vectors.Empty_Vector);
            pragma Unreferenced (P);
         begin
            Assert (False, "GCM open with bad tag must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
   end Test_Gcm;

   procedure Test_Errors (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Sizes : constant array (Positive range <>) of Natural :=
        (0, 15, 17, 33);
   begin
      --  bad key sizes (Go: NewCipher error)
      for L of Sizes loop
         begin
            declare
               B : constant Gada.Std.Crypto.Aes.Block :=
                 Gada.Std.Crypto.Aes.New_Cipher (New_Bytes (L));
               pragma Unreferenced (B);
            begin
               Assert (False, "bad key size must raise");
            end;
         exception
            when Constraint_Error => null;  --  expected
         end;
      end loop;
      --  Encrypt/Decrypt want exactly one block
      declare
         B : constant Gada.Std.Crypto.Aes.Block :=
           Gada.Std.Crypto.Aes.New_Cipher (New_Bytes (16));
         R : Byte_Slice := Gada.Std.Crypto.Aes.Encrypt (B, New_Bytes (15));
         pragma Unreferenced (R);
      begin
         Assert (False, "short block must raise");
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  bad IV length for CBC and CTR
      declare
         B : constant Gada.Std.Crypto.Aes.Block :=
           Gada.Std.Crypto.Aes.New_Cipher (New_Bytes (16));
         M : constant Gada.Std.Crypto.Cipher.Block_Mode :=
           Gada.Std.Crypto.Cipher.New_CBC_Encrypter (B, New_Bytes (8));
         pragma Unreferenced (M);
      begin
         Assert (False, "short IV must raise");
      exception
         when Constraint_Error => null;  --  expected
      end;
      declare
         B : constant Gada.Std.Crypto.Aes.Block :=
           Gada.Std.Crypto.Aes.New_Cipher (New_Bytes (16));
         S : constant Gada.Std.Crypto.Cipher.Stream :=
           Gada.Std.Crypto.Cipher.New_CTR (B, New_Bytes (8));
         pragma Unreferenced (S);
      begin
         Assert (False, "short CTR IV must raise");
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  CBC src not a multiple of 16
      declare
         B : constant Gada.Std.Crypto.Aes.Block :=
           Gada.Std.Crypto.Aes.New_Cipher (New_Bytes (16));
         M : Gada.Std.Crypto.Cipher.Block_Mode :=
           Gada.Std.Crypto.Cipher.New_CBC_Encrypter (B, New_Bytes (16));
         D : Byte_Slice;
      begin
         Gada.Std.Crypto.Cipher.Crypt_Blocks (M, D, New_Bytes (17));
         pragma Unreferenced (D);
         Assert (False, "partial CBC block must raise");
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  GCM bad nonce length
      declare
         B : constant Gada.Std.Crypto.Aes.Block :=
           Gada.Std.Crypto.Aes.New_Cipher (New_Bytes (16));
         G : constant Gada.Std.Crypto.Cipher.GCM :=
           Gada.Std.Crypto.Cipher.New_GCM (B);
         S : constant Byte_Slice :=
           Gada.Std.Crypto.Cipher.Seal (G, New_Bytes (8), Byte_Vectors.Empty_Vector, Byte_Vectors.Empty_Vector);
         pragma Unreferenced (S);
      begin
         Assert (False, "short GCM nonce must raise");
      exception
         when Constraint_Error => null;  --  expected
      end;
   end Test_Errors;

end Std_Crypto_Aes_Suite;
