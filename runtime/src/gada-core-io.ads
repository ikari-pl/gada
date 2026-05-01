--  Gada.Core.IO — minimal Println surface for the GADA runtime.
--
--  This is the very first user-visible runtime primitive: a thin wrapper
--  over `Ada.Text_IO.Put_Line` that the transpiler will eventually emit
--  for `fmt.Println(s)` calls when the argument is a single string.
--
--  Phase 01 ships only `Println (Text : String)`. Subsequent phases add
--  the variadic and typed forms (`Println (V : Any)`, `Printf`, etc.) as
--  the type-system layer of the compiler grows up to support them.
--
--  Layering: `Gada.Core.IO` lives strictly in the *Core* layer (see
--  `AGENTS.md` §"The runtime is layered"), so it must not pull in
--  `Gada.Async` or `Gada.Reflect`. Standard-library `Ada.Text_IO` is
--  the only dependency.

package Gada.Core.IO is

   procedure Println (Text : String);
   --  Write `Text` followed by a single line terminator (LF on Unix,
   --  whatever the host runtime considers `New_Line` on other targets)
   --  to the current default output. Equivalent to Go's
   --  `fmt.Println(text)` for a single string argument.

end Gada.Core.IO;
