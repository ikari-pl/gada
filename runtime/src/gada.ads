--  Top-level umbrella package for the GADA runtime.
--
--  All runtime units live under this root as child packages:
--    * Gada.Core         — slices, maps, defer, panic, GC interface
--    * Gada.Core.IO      — minimal Println surface (Phase 01)
--    * Gada.Async        — scheduler, channels, select  (later phase)
--    * Gada.Reflect      — type metadata + reflect.*    (later phase)
--    * Gada.Std          — Go-stdlib-shaped wrappers    (later phase)
--
--  This package itself is intentionally empty: it is a namespace, not a
--  module. See AGENTS.md §"The runtime is layered" for the layering
--  contract.

package Gada is
   pragma Pure;
end Gada;
