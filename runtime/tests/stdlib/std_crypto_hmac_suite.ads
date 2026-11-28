--  AUnit suite for `Gada.Std.Crypto.Hmac` (the Go `crypto/hmac`
--  port, Phase 8 wave 4 item 3).
--
--  Vectors are the RFC 4231 (SHA-256/SHA-512) and RFC 2202
--  (MD5/SHA-1) HMAC test cases, pinned from Go 1.27 (`go run` over
--  crypto/hmac) — including keys longer than the block size (hashed
--  first) and multi-block messages. Every case is checked for all
--  four algorithms; the SHA-256 MAC is additionally produced through
--  a split Write and compared with hmac.Equal.

with AUnit;
with AUnit.Test_Cases;

package Std_Crypto_Hmac_Suite is

   type Std_Crypto_Hmac_Test is new AUnit.Test_Cases.Test_Case
     with null record;

   overriding procedure Register_Tests (T : in out Std_Crypto_Hmac_Test);
   overriding function  Name (T : Std_Crypto_Hmac_Test)
      return AUnit.Message_String;

   procedure Test_Rfc_Vectors (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Api (T : in out AUnit.Test_Cases.Test_Case'Class);

end Std_Crypto_Hmac_Suite;
