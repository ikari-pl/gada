--  Gada.Reflect — GADA's port of Go's `reflect` package surface.
--
--  This is the namespace parent. It carries no declarations of its own;
--  the concrete surfaces live in child packages so a program that does
--  not use reflection links none of it (the GADA.Reflect layer sits
--  above GADA.Async / GADA.Core — see AGENTS.md §"The runtime is
--  layered"):
--
--    * Gada.Reflect.Types — the type-metadata schema (Phase 4 item 1):
--      the Type_Descriptor record (name, kind, fields, methods, element
--      / key links) that the compiler emits a Register_Type call for,
--      per defined Go type, and that the TypeOf / ValueOf entry points
--      (later Phase 4 items) hand back to user code.
--
--  Kept dependency-light on purpose: the schema needs only
--  Ada.Strings.Unbounded and Ada.Containers, no GADA runtime layers, so
--  the verifiable-subset and embedded builds can pull in reflection
--  metadata without dragging in the scheduler or the GC interface.

package Gada.Reflect is

end Gada.Reflect;
