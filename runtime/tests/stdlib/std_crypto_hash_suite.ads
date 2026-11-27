--  AUnit suite for `Gada.Std.Crypto.*` (Go `crypto/sha256`,
--  `crypto/sha512`, `crypto/sha1`, `crypto/md5` ports, Phase 8 wave 4
--  item 2).
--
--  Every expected digest is pinned from Go 1.27 (`go run`), including
--  the FIPS/RFC check values: SHA-256("abc") = ba7816bf..., SHA-1
--  ("abc") = a9993e36..., MD5("abc") = 90015098..., and the empty
--  message digests. Boundary lengths 55/56/63/64/65 exercise the
--  padding paths (one block vs two), 1000 crosses several blocks,
--  and every input is also hashed via a split Write to prove the
--  streaming path equals the one-shot path.

with AUnit;
with AUnit.Test_Cases;

package Std_Crypto_Hash_Suite is

   type Std_Crypto_Hash_Test is new AUnit.Test_Cases.Test_Case
     with null record;

   overriding procedure Register_Tests (T : in out Std_Crypto_Hash_Test);
   overriding function  Name (T : Std_Crypto_Hash_Test)
      return AUnit.Message_String;

   procedure Test_Sha256 (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Sha512 (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Sha1 (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Md5 (T : in out AUnit.Test_Cases.Test_Case'Class);

end Std_Crypto_Hash_Suite;
