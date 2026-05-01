--  Gada.Core — root of the runtime's "core" layer.
--
--  This package is currently a namespace placeholder. Concrete runtime
--  primitives (slices, maps, defer/panic plumbing, GC interface) land as
--  child packages of `Gada.Core` in subsequent phases. Phase 01 ships
--  `Gada.Core.IO` as the first such child; this declaration is what makes
--  that child name legal.

package Gada.Core is
   --  The playbook contract requires an accompanying body (`gada-core.adb`).
   --  Because this spec currently has no declarations that themselves
   --  *require* a body (no subprograms, no incomplete types, no nested
   --  package specs), GNAT would otherwise reject the body with
   --  "spec of this package does not allow a body". `pragma
   --  Elaborate_Body` is the standard escape hatch: it both permits
   --  the body and pins its elaboration order, which we want anyway
   --  once real runtime primitives land here.
   pragma Elaborate_Body;
end Gada.Core;
