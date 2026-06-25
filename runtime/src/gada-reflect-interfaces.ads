--  Gada.Reflect.Interfaces — the interface-satisfaction registry
--  (Phase 4 item 4c-i).
--
--  Under the Hybrid interface model, native Ada tagged types carry the
--  actual method dispatch; this registry is the *introspection* half. It
--  records, for the (concrete type, interface) pairs the compiler proves
--  satisfied at compile time, a membership the runtime can answer in
--  O(1) — the data behind a `reflect`-style "does C implement I?" query.
--
--  The compiler emits one `Register` call per satisfied pair at module
--  init (item 4c-ii). Identity on both sides is the `Type_Id` the
--  compiler assigns (the same key the type registry uses). Lives in a
--  sibling child of Gada.Reflect.Types, like the type registry: an Ada
--  parent spec cannot `with` its own child.
--
--  The store is a hashed set of pairs behind a protected object, so
--  Satisfies is O(1) and concurrent goroutine reads are safe while
--  registration runs at single-threaded elaboration. Registering the
--  same pair twice is idempotent.

with Gada.Reflect.Types;

package Gada.Reflect.Interfaces is

   --  Record that the concrete type Concrete satisfies the interface
   --  Iface. Idempotent. A No_Type on either side is rejected
   --  (Constraint_Error) — the compiler never assigns Id 0, so it can
   --  only be a caller error, surfaced loudly as in the type registry.
   procedure Register
     (Concrete : Gada.Reflect.Types.Type_Id;
      Iface    : Gada.Reflect.Types.Type_Id);

   --  Does Concrete satisfy Iface? O(1). False for any pair never
   --  registered (Go's `_, ok := x.(I)` failing).
   function Satisfies
     (Concrete : Gada.Reflect.Types.Type_Id;
      Iface    : Gada.Reflect.Types.Type_Id) return Boolean;

end Gada.Reflect.Interfaces;
