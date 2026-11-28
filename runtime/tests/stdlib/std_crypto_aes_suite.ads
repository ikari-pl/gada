--  AUnit suite for `Gada.Std.Crypto.Aes` + `Gada.Std.Crypto.Cipher`
--  (the Go `crypto/aes` and `crypto/cipher` ports, Phase 8 wave 4
--  item 4).
--
--  Vectors pinned from Go 1.27 (`go run`): FIPS-197 ECB examples for
--  AES-128/192/256, the NIST SP 800-38A CBC and CTR 4-block vectors
--  for all three key sizes, and NIST-style GCM cases (empty, one
--  block, 64-byte plaintext with 20-byte AAD, AES-256) including
--  Seal/Open round-trips. Error paths (bad key size, bad IV, partial
--  block, GCM tag mismatch) are checked via CONSTRAINT_ERROR, which
--  stands in for Go's error returns in v1.

with AUnit;
with AUnit.Test_Cases;

package Std_Crypto_Aes_Suite is

   type Std_Crypto_Aes_Test is new AUnit.Test_Cases.Test_Case
     with null record;

   overriding procedure Register_Tests (T : in out Std_Crypto_Aes_Test);
   overriding function  Name (T : Std_Crypto_Aes_Test)
      return AUnit.Message_String;

   procedure Test_Ecb_Kat (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Cbc (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Ctr (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Gcm (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Errors (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Out_Call_Forms (T : in out AUnit.Test_Cases.Test_Case'Class);

end Std_Crypto_Aes_Suite;
