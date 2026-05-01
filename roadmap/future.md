# Future / post-1.0

[← Phase 11](11-validation-1.0.md) · [Index](README.md)

These items are **not** part of the 1.0 roadmap. They are recorded so
the architecture leaves room for them and so contributors do not waste
energy resurrecting "but what about X?" questions during 1.0 work.

Each item below should, when picked up post-1.0, be promoted to a
proper phase file (e.g., `12-cgo.md`) with the same per-task contract
the rest of the roadmap uses. The notes below are scoping sketches,
not specifications.

## cgo support

Calling C from transpiled Go. Probably implemented via
`pragma Import (C, ...)` glue emitted by the compiler from `//#cgo`
directives, with `import "C"` resolving to a synthetic Ada package
that wraps the user's C declarations.

**Open questions:** memory ownership across the boundary; cgo's
goroutine-park-on-blocking-call semantics; how to represent C unions
that don't have a clean Ada analogue.

## Precise GC

Replace Boehm with a tracing GC that uses the type-metadata system
already built for `reflect`. Boehm is conservative, which is fine for
v1.0 but costs throughput on allocation-heavy workloads. A precise GC
can use the type metadata to walk roots accurately, enable generational
collection, and integrate with Ada's own controlled-types finalization.

**Open questions:** how to interleave precise sweeping with Ada's
existing storage pools; whether to keep Boehm available as an opt-in
runtime selection.

## WASM target

Emit Ada that compiles to WASM via GCC's wasm backend, or skip Ada
and emit WASM directly. Useful for sandboxed Go execution on the
JVM-equivalent of Ada targets, and for distributing GADA-compiled
plugins to runtimes that already host WASM modules.

**Open questions:** GADA-Async on WASM (the spec lacks first-class
threads in stable WASM 1.0); GC interop with the host runtime when
host has its own GC.

## Generics-heavy programs

Go 1.18+ generics fully working in the v1.0 transpiler is a target.
Truly exotic uses — constraints with embedded type sets, generic
methods on parameterized types with auto-derived instantiations,
generic recursion — may require post-1.0 work to model in Ada
generics, which have a more nominal flavor than Go's structural
type-set constraints.

## Hot-reload of transpiled modules

Aligned with the Erlang/OTP-influenced subset of the Ada Distributed
Systems Annex. The Distributed Annex already provides a model for
RCI (Remote Call Interface) packages; hot-reload of GADA modules
across a partition boundary is a research item worth exploring.

## SPARK-mode coverage of stdlib

Phase 9 verifies user-written Go in `-mode=spark`. Verifying the
*standard library* itself in SPARK mode is a separate, larger effort
— it would require rewriting the stdlib implementations to respect
SPARK's stricter rules, which may regress some pure-Ada idiomatic
choices made during Phases 5–8. Worthwhile for safety-critical
deployments, expensive in maintenance.

## TinyGo-style very-small embedded profile

A "GADA-Tiny" build profile that strips reflection, GC (replacing it
with arena allocation), and most of the stdlib. Targets bare-metal
microcontrollers with < 32 KB RAM. Composes with the existing layered
runtime; the work is mostly about defining a stable subset and testing
it on representative microcontroller hardware.

---

These are tracked as GitHub issues with the `post-1.0` label, not as
roadmap phases. When a post-1.0 item attracts enough interest to start
serious work, it becomes a new phase file in this directory.
