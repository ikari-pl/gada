---
type: adr
title: "ADR-0002: Layer the runtime as Gada.Core / Gada.Async / Gada.Reflect / Gada.Std with strict no-upward-dependency"
status: accepted
created: 2026-05-01
deciders: [gada-core]
tags: [runtime, ada, architecture, layering, embedded]
related:
  - "[[0000-record-architecture-decisions]]"
  - "[[0001-go-frontend-via-go-ast]]"
  - "[[0003-gc-boehm-for-v1]]"
  - "[[0004-scheduler-libco-for-v1]]"
  - "[[roadmap/00-foundation]]"
  - "[[style_ada]]"
---

# ADR-0002: Layer the runtime as Gada.Core / Gada.Async / Gada.Reflect / Gada.Std with strict no-upward-dependency

## Context

The GADA runtime is a Go-runtime-shaped library written in Ada.
Its scope is broad: slices and maps, garbage collection, defer/panic,
goroutines, channels, `select`, reflection, and a meaningful subset of
the Go standard library (`fmt`, `errors`, `strings`, `bytes`,
`encoding/json`, `net`, etc.). If we ship that as one monolithic
package, three things break.

First, **embedded targets cannot pay for what they do not use.** A
Cortex-M4 with 64 KB of RAM cannot afford to link in `encoding/json`
to print a sensor reading. The runtime must permit a build that
includes only the absolute minimum (slices, GC, defer) and excludes
everything else.

Second, **the verifiable-subset compiler mode (SPARK) cannot tolerate
all runtime features.** Reflection, exceptions, dynamic allocation,
and unbounded scheduling each violate SPARK rules in different ways.
For SPARK builds we need to omit specific layers of the runtime
without surgical extraction.

Third, **the dependency graph between runtime concerns is asymmetric.**
The scheduler needs to allocate and the GC needs to know what is
reachable, but reflection should not be a transitive dependency of
the scheduler, and the standard library should not be a transitive
dependency of GC. Without a stated layering, casual cross-imports
turn the runtime into a knot.

This ADR resolves the layering once. It is anchored in `AGENTS.md`
design principle #3 (the four-layer stack with strict no-upward
dependency) and in the architecture diagram in `README.md`.

## Decision

The GADA runtime is split into four layers, each a separate Alire
crate / GPR project, with a strict downward-only dependency rule:

```
Gada.Std       fmt, errors, strings, bytes, encoding/*, net, ...
Gada.Reflect   type metadata + reflect.TypeOf / ValueOf
Gada.Async     scheduler, channels, select, time
Gada.Core      slices, maps, defer, panic/recover, GC interface
```

The rules are:

1. **Strict downward dependency.** A higher layer may `with` any
   lower layer. A lower layer must not `with` any higher layer.
   `Gada.Core` has zero dependencies on `Gada.Async`,
   `Gada.Reflect`, or `Gada.Std`. `Gada.Async` may use
   `Gada.Core`. `Gada.Reflect` may use `Gada.Core` and
   `Gada.Async`. `Gada.Std` may use everything below it.
2. **No sibling dependencies.** `Gada.Async` does not `with`
   `Gada.Reflect`, and `Gada.Reflect` does not `with`
   `Gada.Async`. The scheduler does not depend on the type-info
   table; the type-info table does not depend on the scheduler.
   Cross-cutting needs (e.g., the scheduler needing to know a
   type's size) are met via a downward interface defined in
   `Gada.Core`.
3. **One Alire crate per layer.** `gada_core.gpr`,
   `gada_async.gpr`, `gada_reflect.gpr`, `gada_std.gpr`. A
   build that needs only `Gada.Core` links only
   `gada_core.gpr` and the GNAT runtime. The compiler driver
   (`compiler/cmd/gada`) selects layers from a build profile;
   on hosted targets the default profile is all four, on
   embedded and SPARK targets the user picks a subset.
4. **Naming.** Every package name is rooted at `Gada` and uses
   the `Gada.X.Y` form (e.g., `Gada.Async.Channels`,
   `Gada.Std.Encoding.Json`). The package-name root is reserved
   for the runtime; transpiled user code lives under
   `Gada.User.<module-path>` so it cannot collide with the
   runtime namespace. The Ada style guide
   ([[style_ada]]) makes this rule lint-enforceable.
5. **Tested independently.** Each layer's AUnit suite runs
   without any higher layer present. `Gada.Core` tests do not
   depend on `Gada.Async`. The CI matrix runs each layer's
   tests in isolation as well as together.
6. **Layer boundary is the unit of supersession.** When a
   higher-layer feature wants something from a lower layer, the
   answer is to extend the lower layer's downward interface, not
   to short-circuit the layering. Boundary changes require a
   commit message that names the affected layers explicitly so
   reviewers can spot a layering break.

## Consequences

- **What now becomes easier.** Embedded targets get a
  fine-grained cost-of-features curve: a Cortex-M4 build with
  `Gada.Core` only links roughly 20–40 KB of runtime overhead;
  adding `Gada.Async (Ravenscar)` brings it to 60–100 KB. SPARK
  builds drop `Gada.Reflect` and `Gada.Std` and gain
  verifiability without surgery. Reasoning about the runtime
  becomes tractable: a bug in the GC has a known blast radius
  (everything above `Gada.Core` is a consumer); a bug in
  `Gada.Std` cannot break `Gada.Async`. The build matrix
  parallelizes naturally — four GPRs build independently, four
  test suites run independently.
- **What now becomes harder.** Cross-cutting features cost
  more to design. A feature that wants reflection-aware
  scheduling is not a one-file commit; it requires defining a
  downward interface in `Gada.Core` that both `Gada.Async` and
  `Gada.Reflect` can implement against. `defer`'s interaction
  with the GC (see [[0003-gc-boehm-for-v1]]) is constrained by
  this layering: `defer` lives in `Gada.Core`, so it cannot
  appeal to scheduler state when ordering its execution.
  Channel-typed reflection (e.g.,
  `reflect.ChanDir`) requires the type-info table in
  `Gada.Reflect` to mirror channel kinds defined in
  `Gada.Async` without a back-edge — a small but real piece
  of design work.
- **What is now off-limits.** Adding a `with` clause from a
  lower layer to a higher layer. Adding a sibling-to-sibling
  `with` clause between `Gada.Async` and `Gada.Reflect`.
  Putting reflection types in `Gada.Core` to "make scheduling
  easier." Putting `fmt.Println` in `Gada.Core` because
  printing is convenient. Inventing a new top-level package
  outside the `Gada.*` namespace. PRs that violate the
  layering are rejected even when they shrink line count;
  the layering is the architecture.

## Alternatives considered

**Single monolithic runtime crate.** One `gada_runtime.gpr`
covering everything. Rejected. Embedded users cannot opt out
of `Gada.Std`'s footprint; SPARK users cannot opt out of
`Gada.Reflect`'s exception-throwing patterns; the dependency
graph internally becomes unmanageable.

**Two-layer split (core vs. stdlib).** Drop the
`Async` / `Reflect` distinction and bundle them into a
`gada_runtime` crate, with only `gada_core` and `gada_stdlib`
as separate units. Rejected because the SPARK build still
needs to omit reflection without omitting the scheduler (or
vice versa, on a Ravenscar-without-reflection profile), and a
two-layer split forces "all or nothing" on the middle.

**Per-package crates (every Go-stdlib package its own crate).**
Maximally granular. Rejected for v1.0 — produces a build matrix
that is impractical to test, and the cost-of-features benefit
plateaus once you can already drop `Gada.Std` as a unit.
Future work may further subdivide `Gada.Std` (`gada_std_fmt`,
`gada_std_net`, etc.); that is a follow-on ADR, not v1.0.

**Three layers (no Reflect).** Push reflection into `Gada.Std`
because most uses of reflection are stdlib-driven (JSON
encoding, fmt.Sprintf with `%v`). Rejected because it makes
SPARK builds harder — SPARK can tolerate parts of `Gada.Std`
(e.g., a `Gada.Std.Strings` subset) but cannot tolerate
`Gada.Reflect`. Keeping reflection at its own layer makes the
SPARK profile a clean cut.

## See also

- [[0000-record-architecture-decisions]] — the ADR convention
  this file follows.
- [[0001-go-frontend-via-go-ast]] — the compiler-side decision
  that pairs with this runtime-side decision. Together they
  define the input/output of the GADA toolchain.
- [[0003-gc-boehm-for-v1]] — the GC ADR. The GC interface
  lives in `Gada.Core`; the layering rules in this ADR
  constrain what the GC may know about higher layers.
- [[0004-scheduler-libco-for-v1]] — the scheduler ADR. The
  scheduler lives in `Gada.Async`; this ADR fixes the
  scheduler's place in the stack and its allowed dependencies.
- [[style_ada]] — the Ada style guide that makes the
  `Gada.X.Y` naming rule and the no-upward-`with` rule
  lint-enforceable via `tools/gnatcheck.rules`.
