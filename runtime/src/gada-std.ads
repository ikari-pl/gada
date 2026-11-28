--  Gada.Std — root of the stdlib layer: GADA's ports of the Go
--  standard library packages (Phase 5+). This is the namespace parent;
--  concrete packages are children:
--
--    * Gada.Std.Errors   — the `errors` package (New/Is/As/Unwrap)
--    * Gada.Std.Strings  — the `strings` package
--    * Gada.Std.Strconv  — the `strconv` package
--    * Gada.Std.Bytes    — the `bytes` package
--    * Gada.Std.IO       — the `io` package
--    * Gada.Std.Bufio    — the `bufio` package
--    * Gada.Std.Fmt      — the `fmt` package
--
--  Layering: Gada.Std sits above Gada.Core / Gada.Async / Gada.Reflect
--  and may `with` them, never the reverse.

package Gada.Std is
   --  See Gada.Core's spec for why the umbrella carries Elaborate_Body.
   pragma Elaborate_Body;
end Gada.Std;
