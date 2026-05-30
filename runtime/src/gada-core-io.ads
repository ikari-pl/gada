--  Gada.Core.IO — minimal print surface for the GADA runtime.
--
--  This is the very first user-visible runtime primitive: a thin wrapper
--  over `Ada.Text_IO` that the transpiler emits for `fmt.Println` calls.
--
--  Phase 01 shipped only `Println (Text : String)` for the single-string
--  case. Phase 03 (multi-arg `fmt.Println`) adds the per-argument
--  building blocks `Print` (string and integer) plus `New_Line`, so the
--  compiler can lower `fmt.Println(a, b, …)` to a space-separated run of
--  `Print` calls terminated by `New_Line` — matching Go's variadic
--  `Println` spec. The typed variadic form (`Println (V : Any)`, Printf)
--  arrives with the reflection layer in a later phase.
--
--  Layering: `Gada.Core.IO` lives strictly in the *Core* layer (see
--  `AGENTS.md` §"The runtime is layered"), so it must not pull in
--  `Gada.Async` or `Gada.Reflect`. Standard-library `Ada.Text_IO` (and
--  `Ada.Strings.Fixed` for integer trimming) are the only dependencies.

package Gada.Core.IO is

   procedure Print (Text : String);
   --  Write `Text` to the current default output with no trailing line
   --  terminator. The building block for one string operand of a
   --  multi-argument `fmt.Println`.

   procedure Print (Item : Integer);
   --  Write `Item`'s decimal representation with no trailing line
   --  terminator and — crucially — no leading space. Ada's
   --  `Integer'Image` (and the Ada 2022 `Item'Image` object form) both
   --  prepend a blank in the sign position for non-negative values; Go's
   --  `fmt.Println` prints bare digits, so this trims that blank.
   --  Negative values keep their `-` (there is no leading blank to
   --  trim).

   procedure New_Line;
   --  Write a single line terminator (LF on Unix) to the current
   --  default output. Terminates a `fmt.Println` after its operands.

   procedure Println (Text : String);
   --  Write `Text` followed by a single line terminator. Equivalent to
   --  `Print (Text); New_Line;`. Retained as the direct lowering of the
   --  common single-string `fmt.Println(s)` and as a stable public API.

end Gada.Core.IO;
