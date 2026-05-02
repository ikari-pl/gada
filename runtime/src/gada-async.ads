--  Top-level umbrella package for GADA's concurrency runtime.
--
--  All concurrency units live under this root as child packages:
--    * Gada.Async.Context  — userspace context switching via libco
--    * Gada.Async.Scheduler — M:N goroutine scheduler over Ada tasks
--    * Gada.Async.Channels  — bounded + unbounded channels
--    * Gada.Async.Select    — Go's select statement runtime
--
--  The layered policy is set by docs/adr/0002-runtime-layered.md:
--  Gada.Async sits above Gada.Core (it uses memory, slices, etc.) and
--  below Gada.Std (which uses scheduler primitives via Goroutine.go,
--  channels via chan, ...).
--
--  This package itself is intentionally empty: it is a namespace, not a
--  unit of behaviour. Adding declarations here would force every
--  importer of any child to also see them.

package Gada.Async with Pure is
end Gada.Async;
