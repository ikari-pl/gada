--  Body of Std_Crypto_Hmac_Suite — see spec for test rationale. All
--  expected MACs pinned from Go 1.27 via `go run`.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Crypto.Hmac;

package body Std_Crypto_Hmac_Suite is

   overriding function Name
     (T : Std_Crypto_Hmac_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Crypto.Hmac suite (PKG=stdlib.crypto.hmac)"));

   overriding procedure Register_Tests (T : in out Std_Crypto_Hmac_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Rfc_Vectors'Access, "RFC 2202/4231 vectors");
      Register_Routine (T, Test_Api'Access, "Equal/Reset/Size/Block_Size");
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

   function Sub (B : Byte_Slice; First, Last : Natural) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      for I in First .. Last loop
         Byte_Vectors.Append (R, Byte_Vectors.Element (B, I));
      end loop;
      return R;
   end Sub;

   type Vec is record
      Name                     : Unbounded_String;
      Key, Data                : Unbounded_String;  --  hex
      Mac256, Mac512, Mac1, Mac5 : Unbounded_String;  --  hex
   end record;

   Vecs : constant array (Positive range <>) of Vec :=
     (      (To_Unbounded_String ("rfc4231-1"),
       To_Unbounded_String ("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"),
       To_Unbounded_String ("4869205468657265"),
       To_Unbounded_String ("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"),
       To_Unbounded_String ("87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854"),
       To_Unbounded_String ("b617318655057264e28bc0b6fb378c8ef146be00"),
       To_Unbounded_String ("5ccec34ea9656392457fa1ac27f08fbc")),
      (To_Unbounded_String ("rfc4231-2"),
       To_Unbounded_String ("4a656665"),
       To_Unbounded_String ("7768617420646f2079612077616e7420666f72206e6f7468696e673f"),
       To_Unbounded_String ("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"),
       To_Unbounded_String ("164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737"),
       To_Unbounded_String ("effcdf6ae5eb2fa2d27416d5f184df9c259a7c79"),
       To_Unbounded_String ("750c783e6ab0b503eaa86e310a5db738")),
      (To_Unbounded_String ("rfc4231-3"),
       To_Unbounded_String ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
       To_Unbounded_String ("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
       To_Unbounded_String ("773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"),
       To_Unbounded_String ("fa73b0089d56a284efb0f0756c890be9b1b5dbdd8ee81a3655f83e33b2279d39bf3e848279a722c806b485a47e67c807b946a337bee8942674278859e13292fb"),
       To_Unbounded_String ("125d7342b9ac11cd91a39af48aa17b4f63f175d3"),
       To_Unbounded_String ("2ab8b9a9f7d3894d15ad8383b97044b2")),
      (To_Unbounded_String ("rfc4231-4"),
       To_Unbounded_String ("0102030405060708090a0b0c0d0e0f10111213141516171819"),
       To_Unbounded_String ("cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"),
       To_Unbounded_String ("82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"),
       To_Unbounded_String ("b0ba465637458c6990e5a8c5f61d4af7e576d97ff94b872de76f8050361ee3dba91ca5c11aa25eb4d679275cc5788063a5f19741120c4f2de2adebeb10a298dd"),
       To_Unbounded_String ("4c9007f4026250c6bc8414f9bf50c86c2d7235da"),
       To_Unbounded_String ("697eaf0aca3a3aea3a75164746ffaa79")),
      (To_Unbounded_String ("rfc4231-5"),
       To_Unbounded_String ("0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c"),
       To_Unbounded_String ("546573742057697468205472756e636174696f6e"),
       To_Unbounded_String ("a3b6167473100ee06e0c796c2955552bfa6f7c0a6a8aef8b93f860aab0cd20c5"),
       To_Unbounded_String ("415fad6271580a531d4179bc891d87a650188707922a4fbb36663a1eb16da008711c5b50ddd0fc235084eb9d3364a1454fb2ef67cd1d29fe6773068ea266e96b"),
       To_Unbounded_String ("4c1a03424b55e07fe7f27be1d58bb9324a9a5a04"),
       To_Unbounded_String ("951726cea438b8e106e43b3d87a19c8e")),
      (To_Unbounded_String ("rfc4231-6"),
       To_Unbounded_String ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
       To_Unbounded_String ("54657374205573696e67204c6172676572205468616e20426c6f636b2d53697a65204b6579202d2048617368204b6579204669727374"),
       To_Unbounded_String ("60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"),
       To_Unbounded_String ("80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598"),
       To_Unbounded_String ("90d0dace1c1bdc957339307803160335bde6df2b"),
       To_Unbounded_String ("bfecaf4efff90a3a668f3922fec3762d")),
      (To_Unbounded_String ("rfc4231-7"),
       To_Unbounded_String ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
       To_Unbounded_String ("5468697320697320612074657374207573696e672061206c6172676572207468616e20626c6f636b2d73697a65206b657920616e642061206c6172676572207468616e20626c6f636b2d73697a6520646174612e20546865206b6579206e6565647320746f20626520686173686564206265666f7265206265696e6720757365642062792074686520484d414320616c676f726974686d2e"),
       To_Unbounded_String ("9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2"),
       To_Unbounded_String ("e37b6a775dc87dbaa4dfa9f96e5e3ffddebd71f8867289865df5a32d20cdc944b6022cac3c4982b10d5eeb55c3e4de15134676fb6de0446065c97440fa8c6a58"),
       To_Unbounded_String ("217e44bb08b6e06a2d6c30f3cb9f537f97c63356"),
       To_Unbounded_String ("09b8ae7b15adbbb243aca3491b51512b")),
      (To_Unbounded_String ("rfc2202-1"),
       To_Unbounded_String ("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"),
       To_Unbounded_String ("4869205468657265"),
       To_Unbounded_String ("492ce020fe2534a5789dc3848806c78f4f6711397f08e7e7a12ca5a4483c8aa6"),
       To_Unbounded_String ("7641c48a3b4aa8f887c07b3e83f96affb89c978fed8c96fcbbf4ad596eebfe496f9f16da6cd080ba393c6f365ad72b50d15c71bfb1d6b81f66a911786c6ce932"),
       To_Unbounded_String ("675b0b3a1b4ddf4e124872da6c2f632bfed957e9"),
       To_Unbounded_String ("9294727a3638bb1c13f48ef8158bfc9d")),
      (To_Unbounded_String ("rfc2202-2"),
       To_Unbounded_String ("4a656665"),
       To_Unbounded_String ("7768617420646f2079612077616e7420666f72206e6f7468696e673f"),
       To_Unbounded_String ("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"),
       To_Unbounded_String ("164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737"),
       To_Unbounded_String ("effcdf6ae5eb2fa2d27416d5f184df9c259a7c79"),
       To_Unbounded_String ("750c783e6ab0b503eaa86e310a5db738")),
      (To_Unbounded_String ("rfc2202-3"),
       To_Unbounded_String ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
       To_Unbounded_String ("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
       To_Unbounded_String ("7dda3cc169743a6484649f94f0eda0f9f2ff496a9733fb796ed5adb40a44c3c1"),
       To_Unbounded_String ("ad9b5c7de72693737cd5e9d9f41170d18841fec1201c1c1b02e05cae116718009f771cad9946ddbf7e3cde3e818d9ae85d91b2badae94172d096a44a79c91e86"),
       To_Unbounded_String ("d730594d167e35d5956fd8003d0db3d3f46dc7bb"),
       To_Unbounded_String ("56be34521d144c88dbb8c733f0e8b3f6")),
      (To_Unbounded_String ("rfc2202-4"),
       To_Unbounded_String ("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425"),
       To_Unbounded_String ("546573742057697468205472756e636174696f6e"),
       To_Unbounded_String ("9aa16e1b161d17a27c696a2249e3c219fb83d6974f08e790d3e03c11af3d829f"),
       To_Unbounded_String ("9c7f727cbb3042a8179d6a9d41ce8f65be7909f71bae0cd616fae7a3bf6e3efc62c6ad5e4df0083ab2150c0adc2cc05f99fef5612bb940cfe1d20da340e28d1e"),
       To_Unbounded_String ("285943c2be477a56c929fbf8b92ade4abd102dcf"),
       To_Unbounded_String ("b73bfd5c1235859bc3e31adacc465f32")),
      (To_Unbounded_String ("rfc2202-5"),
       To_Unbounded_String ("0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c"),
       To_Unbounded_String ("cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"),
       To_Unbounded_String ("48b1c997dd8d6084e0d47485d27aa5f9a72a25551488b56a814f1fa332bb327d"),
       To_Unbounded_String ("6e592449555ce3776796cd9111e1c6b37d97c95a1e3b4459972fa3713d3e65ed0c7f181864a0588b6ecbc15ccf180b197c90c9be9383b9e47bf3db8a8ccc00b1"),
       To_Unbounded_String ("2d64072959c7fb1213b4e16272226716fd481665"),
       To_Unbounded_String ("e8c148066036dd54fdd67e06155eceb4")),
      (To_Unbounded_String ("rfc2202-6"),
       To_Unbounded_String ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
       To_Unbounded_String ("54657374205573696e67204c6172676572205468616e20426c6f636b2d53697a65204b6579202d2048617368204b6579204669727374"),
       To_Unbounded_String ("6953025ed96f0c09f80a96f78e6538dbe2e7b820e3dd970e7ddd39091b32352f"),
       To_Unbounded_String ("132c9ebc32531071f6c4d9e8842291e9403e5940f813170a3ba3a0dd6c055c8b8ca587b24c56c47f3c1f2fb8ee8f9fbc8d92deed0f83426be3e8a2e9056778b3"),
       To_Unbounded_String ("aa4ae5e15272d00e95705637ce8a3b55ed402112"),
       To_Unbounded_String ("6b1ab7fe4bd7bf8f0b62e6ce61b9d0cd")),
      (To_Unbounded_String ("rfc2202-7"),
       To_Unbounded_String ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
       To_Unbounded_String ("54657374205573696e67204c6172676572205468616e20426c6f636b2d53697a65204b657920616e64204c6172676572205468616e20426c6f636b2d53697a652044617461"),
       To_Unbounded_String ("eaccca73969c3022bab7e604986273285369d37a21f976fb284cfb5d6a676cb1"),
       To_Unbounded_String ("c2812058819ba058e61f750450451258216c2a31f23b0db690a52ed2de710395079e7d315235d524a2c0683831aa8846d7acef33ac8473a4c39b6d4871e31f94"),
       To_Unbounded_String ("f5c11f3e9807c3d80c1bf81101f1ce0e87b3be88"),
       To_Unbounded_String ("945c4a3245e8a27d352529f75a91b197")));

   procedure Test_Rfc_Vectors (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for V of Vecs loop
         declare
            K : constant Byte_Slice := From_Hex (To_String (V.Key));
            D : constant Byte_Slice := From_Hex (To_String (V.Data));
            N : constant Natural := Natural (Byte_Vectors.Length (D));
            H : Gada.Std.Crypto.Hmac.Hmac :=
              Gada.Std.Crypto.Hmac.New_K (Gada.Std.Crypto.Hmac.Sha256, K);
         begin
            Gada.Std.Crypto.Hmac.Write (H, D);
            Assert
              (To_Hex (Gada.Std.Crypto.Hmac.Sum
                 (H, Byte_Vectors.Empty_Vector)) = To_String (V.Mac256),
               "hmac-sha256 " & To_String (V.Name));
            --  split Write equals one-shot, compared via hmac.Equal
            declare
               H2 : Gada.Std.Crypto.Hmac.Hmac :=
                 Gada.Std.Crypto.Hmac.New_K (Gada.Std.Crypto.Hmac.Sha256, K);
            begin
               Gada.Std.Crypto.Hmac.Write (H2, Sub (D, 1, N / 2));
               Gada.Std.Crypto.Hmac.Write (H2, Sub (D, N / 2 + 1, N));
               Assert
                 (Gada.Std.Crypto.Hmac.Equal
                    (Gada.Std.Crypto.Hmac.Sum (H2, Byte_Vectors.Empty_Vector),
                     Gada.Std.Crypto.Hmac.Sum (H, Byte_Vectors.Empty_Vector)),
                  "hmac-sha256 split " & To_String (V.Name));
            end;
            declare
               H512 : Gada.Std.Crypto.Hmac.Hmac :=
                 Gada.Std.Crypto.Hmac.New_K (Gada.Std.Crypto.Hmac.Sha512, K);
            begin
               Gada.Std.Crypto.Hmac.Write (H512, D);
               Assert
                 (To_Hex (Gada.Std.Crypto.Hmac.Sum
                    (H512, Byte_Vectors.Empty_Vector)) = To_String (V.Mac512),
                  "hmac-sha512 " & To_String (V.Name));
            end;
            declare
               H1 : Gada.Std.Crypto.Hmac.Hmac :=
                 Gada.Std.Crypto.Hmac.New_K (Gada.Std.Crypto.Hmac.Sha1, K);
            begin
               Gada.Std.Crypto.Hmac.Write (H1, D);
               Assert
                 (To_Hex (Gada.Std.Crypto.Hmac.Sum
                    (H1, Byte_Vectors.Empty_Vector)) = To_String (V.Mac1),
                  "hmac-sha1 " & To_String (V.Name));
            end;
            declare
               H5 : Gada.Std.Crypto.Hmac.Hmac :=
                 Gada.Std.Crypto.Hmac.New_K (Gada.Std.Crypto.Hmac.Md5, K);
            begin
               Gada.Std.Crypto.Hmac.Write (H5, D);
               Assert
                 (To_Hex (Gada.Std.Crypto.Hmac.Sum
                    (H5, Byte_Vectors.Empty_Vector)) = To_String (V.Mac5),
                  "hmac-md5 " & To_String (V.Name));
            end;
         end;
      end loop;
   end Test_Rfc_Vectors;

   procedure Test_Api (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      K  : constant Byte_Slice := From_Hex ("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b");
      D  : constant Byte_Slice := From_Hex ("4869205468657265");  --  "Hi There"
      H  : Gada.Std.Crypto.Hmac.Hmac :=
        Gada.Std.Crypto.Hmac.New_K (Gada.Std.Crypto.Hmac.Sha256, K);
      M  : Byte_Slice;
   begin
      Assert (Gada.Std.Crypto.Hmac.Size (H) = 32, "Size sha256");
      Assert (Gada.Std.Crypto.Hmac.Block_Size (H) = 64, "Block_Size sha256");
      Gada.Std.Crypto.Hmac.Write (H, D);
      M := Gada.Std.Crypto.Hmac.Sum (H, Byte_Vectors.Empty_Vector);
      Assert (Integer (Byte_Vectors.Length (M)) = 32, "mac length");
      --  Sum appends to B
      declare
         S : constant Byte_Slice := Gada.Std.Crypto.Hmac.Sum (H, To_Bytes ("xy"));
      begin
         Assert (Integer (Byte_Vectors.Length (S)) = 34, "Sum appends len");
         Assert (Byte_Vectors.Element (S, 1) = 'x'
                   and then Byte_Vectors.Element (S, 2) = 'y',
                 "Sum keeps prefix");
      end;
      --  Equal: self true, other algo false, truncated false
      Assert (Gada.Std.Crypto.Hmac.Equal (M, M), "Equal self");
      declare
         H5 : Gada.Std.Crypto.Hmac.Hmac :=
           Gada.Std.Crypto.Hmac.New_K (Gada.Std.Crypto.Hmac.Md5, K);
         M5 : Byte_Slice;
      begin
         Gada.Std.Crypto.Hmac.Write (H5, D);
         M5 := Gada.Std.Crypto.Hmac.Sum (H5, Byte_Vectors.Empty_Vector);
         Assert (not Gada.Std.Crypto.Hmac.Equal (M, M5), "Equal cross-algo");
         Assert (Gada.Std.Crypto.Hmac.Equal (M5, M5), "Equal md5 self");
         Assert (Gada.Std.Crypto.Hmac.Size (H5) = 16, "Size md5");
         Assert (Gada.Std.Crypto.Hmac.Block_Size (H5) = 64, "Block_Size md5");
      end;
      Assert (not Gada.Std.Crypto.Hmac.Equal (M, Sub (M, 1, 31)),
              "Equal length mismatch");
      --  Reset returns to the freshly-keyed state
      Gada.Std.Crypto.Hmac.Reset (H);
      Gada.Std.Crypto.Hmac.Write (H, D);
      Assert (Gada.Std.Crypto.Hmac.Equal
                (Gada.Std.Crypto.Hmac.Sum (H, Byte_Vectors.Empty_Vector), M),
              "Reset reproduces MAC");
      --  sha512 sizes
      declare
         H512 : Gada.Std.Crypto.Hmac.Hmac :=
           Gada.Std.Crypto.Hmac.New_K (Gada.Std.Crypto.Hmac.Sha512, K);
      begin
         Assert (Gada.Std.Crypto.Hmac.Size (H512) = 64, "Size sha512");
         Assert (Gada.Std.Crypto.Hmac.Block_Size (H512) = 128,
                 "Block_Size sha512");
      end;
      declare
         H1 : Gada.Std.Crypto.Hmac.Hmac :=
           Gada.Std.Crypto.Hmac.New_K (Gada.Std.Crypto.Hmac.Sha1, K);
      begin
         Assert (Gada.Std.Crypto.Hmac.Size (H1) = 20, "Size sha1");
         Assert (Gada.Std.Crypto.Hmac.Block_Size (H1) = 64, "Block_Size sha1");
      end;
   end Test_Api;

end Std_Crypto_Hmac_Suite;
