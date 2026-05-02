--  Gada.Core.Panic — Go-style `panic` / `recover`.
--
--  Go's contract:
--    - `panic(v)` halts normal execution, then unwinds the stack
--      running deferred calls along the way. If no deferred call
--      recovers, the program terminates with a stack trace.
--    - `recover()` is meaningful only inside a deferred call. If
--      a panic is in flight, `recover` returns the panic value
--      and stops the unwind — the panicking function returns
--      normally (i.e. its caller sees a normal return). Outside
--      a deferred call, or with no panic in flight, `recover`
--      returns `nil`.
--
--  This package provides the data-plane half of that contract:
--  the panic-payload stack and the runtime entry points.
--
--  The control-plane half — converting "we recovered" into "the
--  function returns normally" — is the *compiler-emit* layer's
--  job (Phase 2 item 8). Each transpiled Go function is wrapped
--  with a catch-all that re-raises only if Recover was *not*
--  called inside a deferred call. The runtime side exposes
--  `Is_Panicking` so the wrapper can make that decision.
--
--  Generic over Payload_Type so the per-program "panic value
--  type" stays statically typed. A real-world Go program panics
--  with `interface{}` (Go's Any); the compiler-emit layer picks
--  one Payload_Type per program (typically `Gada.Reflect.Any` once
--  Phase 4 lands) and instantiates this generic once at the
--  runtime layer for that program.
--
--  Per docs/adr/0006-runtime-performance-bar.md: zero-alloc on
--  the panic and recover paths (the pending-stack is a fixed
--  bounded array; v1 single-threaded runtime, one global stack;
--  Phase 3 promotes this to a per-task TLS slot when goroutines
--  arrive).

generic
   type Payload_Type is private;
   Default : Payload_Type;
package Gada.Core.Panic is

   --  The Ada exception we raise. Compiler-emit's per-function
   --  wrapper catches this name.
   Panicking : exception;

   --  Push Value onto the panic stack and raise Panicking. Never
   --  returns; the `with No_Return` aspect tells GNAT (and the
   --  caller) the control-flow guarantee.
   procedure Do_Panic (Value : Payload_Type)
     with No_Return;

   --  Inspect-and-pop the top panic payload.
   --
   --  - If a panic is in flight, returns the most recent
   --    Do_Panic argument and clears that frame so subsequent
   --    Is_Panicking returns False (assuming no nested panic).
   --  - Otherwise returns Default — same shape as Go's `nil`.
   --
   --  Calling Recover *outside* a deferred call (i.e. not during
   --  exception unwind) is a Go-defined no-op: it returns
   --  Default. We do not enforce the deferred-call calling
   --  context — the compiler-emit layer does.
   function Recover return Payload_Type;

   --  True iff a Do_Panic call has not yet been balanced by a
   --  Recover. Compiler-emit's per-function wrapper consults this
   --  to decide whether to re-raise on its way out.
   function Is_Panicking return Boolean;

end Gada.Core.Panic;
