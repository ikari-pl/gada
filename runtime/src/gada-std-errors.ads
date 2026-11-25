--  Gada.Std.Errors — the Go `errors` package, ported (Phase 5 wave 1).
--
--  Go's `error` is an interface with a single `Error() string` method;
--  the idiomatic Ada model is a *tagged* type, so `err.Error()` keeps
--  working as a dispatching primitive and custom error types derive
--  from it (the Ada-native equivalent of Go's `type myErr struct{}` +
--  `func (e myErr) Error() string`). A Go `nil` error is the null
--  `Error_Access` (No_Error).
--
--  The unwrap chain is a simple linked cause: each error may carry one
--  Cause (Go 1.13's Unwrap() error), which is what Is/As walk.
--
--  Naming note: the compiler maps Go's exported names through
--  goNameToAdaMember, which appends `_K` to Ada reserved words — so
--  Go's errors.New / errors.Is are `New_K` / `Is_K` here (`new` and
--  `is` are reserved in Ada). errors.As and errors.Unwrap map unchanged.

with Ada.Strings.Unbounded;

package Gada.Std.Errors is

   --  The Go `error` interface as a tagged type. Components are private;
   --  construct via New_K / With_Cause.
   type Error is tagged private;

   --  Access-to-class-wide is the Ada spelling of Go's `error`
   --  interface value: nil error = null access.
   type Error_Access is access all Error'Class;

   --  Go's `nil` error.
   No_Error : constant Error_Access := null;

   --  errors.New(message) — a fresh error with no cause.
   function New_K (Message : String) return Error_Access;

   --  errors.WithCause — a GADA extension (Go builds these with
   --  fmt.Errorf("%w")): a fresh error whose Unwrap returns Cause.
   function With_Cause (Message : String; Cause : Error_Access)
     return Error_Access;

   --  Initializes a root Error value — the ancestor part for extension
   --  aggregates in derived types defined in other packages (Error's
   --  components are private to this package, so they cannot aggregate
   --  the parent directly). A procedure, not a function: a derived type
   --  inheriting a function that returns the parent type would have to
   --  override it.
   procedure Make_Base (E : out Error; Msg : String; Cause : Error_Access);

   --  Go's err.Error() method, as a primitive operation so both
   --  specific and class-wide calls dispatch. Named Message because
   --  a subprogram cannot share the type's name (homograph rule).
   function Message (E : Error) return String;

   --  errors.Unwrap(err) — the cause, or No_Error.
   function Unwrap (E : Error_Access) return Error_Access;

   --  errors.Is(err, target): true iff target is null and err is null,
   --  or some error in err's unwrap chain is the *same* error value as
   --  target (Go compares interface values; for pointer-backed errors
   --  that is identity, which is what access equality gives us — the
   --  sentinel pattern `var ErrX = errors.New(...)` works exactly as
   --  in Go).
   function Is_K (Err, Target : Error_Access) return Boolean;

   --  errors.As(err, &target): walks err's chain; the first error whose
   --  dynamic type equals target's pointee type is assigned to
   --  target.all and the result is true. Returns false when the chain
   --  is exhausted (Go panics on a non-pointer target; our `not null`
   --  access formal makes that a caller-side constraint instead).
   function As (Err : Error_Access; Target : not null access Error'Class)
     return Boolean;

private

   type Error is tagged record
      Message : Ada.Strings.Unbounded.Unbounded_String;
      Cause   : Error_Access;
   end record;

end Gada.Std.Errors;
