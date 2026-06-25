--  Gada.Reflect.Registry — the process-wide type registry (Phase 4
--  item 2b).
--
--  The compiler emits one Register_Type call per defined Go type at
--  module init; TypeOf / ValueOf (a later item) read the registry back
--  via Lookup. Identity is the Type_Id the compiler assigns once per
--  defined type, and the registry is keyed by it.
--
--  Lives in a sibling child of Gada.Reflect.Types (not the Gada.Reflect
--  parent: an Ada parent spec cannot `with` its own child). Registering
--  the same Id twice is last-wins — a re-elaboration or a deliberate
--  override replaces the prior descriptor. Lookup of an unregistered Id
--  returns an Invalid_Kind descriptor, the analogue of Go's zero
--  `reflect.Type`. The store is a protected object so concurrent Lookup
--  from goroutines is safe while registration runs at single-threaded
--  elaboration.

with Gada.Reflect.Types;

package Gada.Reflect.Registry is

   --  Register_Type is called from client module-init elaboration; force
   --  this body to elaborate right after its spec so a client's call can
   --  never precede it (Access-Before-Elaboration).
   pragma Elaborate_Body;

   --  Add (or, for an Id already present, replace) T. Called once per
   --  defined type from module-init elaboration.
   procedure Register_Type (T : Gada.Reflect.Types.Type_Descriptor);

   --  The descriptor registered under Id, or an Invalid_Kind descriptor
   --  (Id => No_Type) if none is registered — Go's zero reflect.Type.
   function Lookup
     (Id : Gada.Reflect.Types.Type_Id)
      return Gada.Reflect.Types.Type_Descriptor;

end Gada.Reflect.Registry;
