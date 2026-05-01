--  Gada.Core body — empty in Phase 01.
--
--  Concrete runtime primitives (slices, maps, defer/panic plumbing, GC
--  interface) land as child packages of `Gada.Core` in subsequent phases.
--  This body exists only to satisfy the playbook's "empty body for now,
--  just the declaration" contract and to ensure `gprbuild` compiles a
--  body unit alongside the spec.

package body Gada.Core is
end Gada.Core;
