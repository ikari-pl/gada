--  Gada.Std.Crypto — parent of the Go `crypto/*` ports (Phase 8 wave 4).
--
--  One child package per Go package, mirroring the import paths:
--    crypto/sha256 → Gada.Std.Crypto.Sha256
--    crypto/sha512 → Gada.Std.Crypto.Sha512
--    crypto/sha1   → Gada.Std.Crypto.Sha1
--    crypto/md5    → Gada.Std.Crypto.Md5
--    crypto/hmac   → Gada.Std.Crypto.Hmac   (item 3)
--    crypto/aes    → Gada.Std.Crypto.Aes    (item 4)
--
--  The parent itself carries no declarations; it exists so the child
--  units have a legal ancestor.

package Gada.Std.Crypto is
end Gada.Std.Crypto;
