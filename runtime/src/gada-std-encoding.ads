--  Gada.Std.Encoding — parent of the Go `encoding/*` ports
--  (Phase 8 wave 4, items 5-6).
--
--  One child package per Go package, mirroring the import paths:
--    encoding/base64 → Gada.Std.Encoding.Base64
--    encoding/hex    → Gada.Std.Encoding.Hex
--    encoding/binary → Gada.Std.Encoding.Binary
--    encoding/csv    → Gada.Std.Encoding.Csv   (item 6)
--    encoding/xml    → Gada.Std.Encoding.Xml   (item 6)
--
--  The parent itself carries no declarations; it exists so the child
--  units have a legal ancestor.

package Gada.Std.Encoding is
end Gada.Std.Encoding;
