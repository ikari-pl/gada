--  Gada.Reflect — GADA's port of Go's `reflect` package surface.
--
--  This is the namespace parent. It carries no declarations of its own
--  (and can carry none that mention the schema: an Ada parent spec may
--  not `with` its own child, so anything referring to
--  Gada.Reflect.Types must live in a sibling child, not here). The
--  concrete surfaces are child packages, so a program that uses no
--  reflection links none of it (the GADA.Reflect layer sits above
--  GADA.Async / GADA.Core — see AGENTS.md §"The runtime is layered"):
--
--    * Gada.Reflect.Types    — the type-metadata schema (Type_Descriptor:
--      name, kind, fields, methods, element / key links).
--    * Gada.Reflect.Registry — the process-wide type registry the
--      compiler populates with one Register_Type per defined type at
--      module init, and that TypeOf / ValueOf read back via Lookup.
--
--  Kept dependency-light: the children need only Ada.Strings.Unbounded
--  and Ada.Containers, no GADA runtime layers, so the verifiable-subset
--  and embedded builds can carry reflection metadata without dragging
--  in the scheduler or the GC interface.

package Gada.Reflect is

end Gada.Reflect;
