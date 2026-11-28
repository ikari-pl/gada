--  Gada.Std.Hash — parent of the Go `hash/*` ports (Phase 8 wave 4).
--
--  One child package per Go package, mirroring the import paths:
--    hash/crc32   → Gada.Std.Hash.Crc32
--    hash/crc64   → Gada.Std.Hash.Crc64
--    hash/fnv     → Gada.Std.Hash.Fnv
--    hash/adler32 → Gada.Std.Hash.Adler32
--
--  The parent itself carries no declarations; it exists so the child
--  units have a legal ancestor.

package Gada.Std.Hash is
end Gada.Std.Hash;
