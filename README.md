# GADA — Go on Ada

> **GADA transpiles Go source to Ada source.** The output runs against a
> Go-runtime-shaped library written in Ada: goroutines on Ada tasks,
> channels on protected objects, slices and maps as Ada generics, GC via
> Boehm. Result: a Go program that builds with `gprbuild` and runs on
> any GCC-Ada target — including ones the Go reference compiler will
> never reach.

[![status](https://img.shields.io/badge/status-design%20%2B%20early%20development-orange)]()
[![coverage](https://img.shields.io/badge/coverage-target%20100%25%20runtime%20%2F%20%E2%89%A590%25%20compiler-blue)]()
[![license](https://img.shields.io/badge/license-TBD-lightgrey)]()

**Status: design + early development.** No shippable artifact yet. See
[`roadmap/`](./roadmap/) for phase-by-phase status.

---

## Why GADA exists

The macOS-bundle work that motivated this repo surfaced a recurring
question: *what would it take to make Go programs run on the Ada
toolchain?* Naive transpilation runs into Go-runtime semantics that
don't fit Ada (M:N goroutines, GC, channels, structural interfaces).
The honest answer is **port the Go runtime to Ada**. That's GADA.

The deliverable isn't a Go-compiler-replacement. It's an Ada-ecosystem
project that lets Ada developers, embedded engineers on tiny targets,
and certification-track teams use Go source code without leaving the
Ada world.

---

## What GADA wins at

This is the long section. Every win below is concrete, measurable, and
something stock Go cannot do.

### 1. Cross-compilation reach: Go on every GCC target

GCC's Ada frontend (the GNAT frontend, integrated into GCC since the
1990s) targets approximately **30 architecture/OS pairs**. Stock Go's
official toolchain targets approximately **15**. The delta is not
trivia — it includes platforms that *cannot run vanilla Go at all*
because no port exists or because the platform's calling convention is
incompatible with Go's runtime.

**Examples GADA reaches that vanilla Go does not:**

| Platform | Vanilla Go | GADA |
|---|---|---|
| AIX 7.2 / POWER9 | partial (gccgo only, ancient) | yes (current GCC Ada) |
| OpenVMS / Itanium | no | yes (GCC Ada cross-compile) |
| Solaris 11 / SPARC64 | very limited | yes |
| OpenBSD / SPARC64 | no | yes |
| Bare-metal ARM Cortex-M (Ravenscar) | no (TinyGo only, no goroutines) | yes (with GADA-Async profile) |
| QNX / various | community ports, often broken | yes via GCC Ada |
| z/OS (mainframe) | no | yes (GCC Ada s390x) |
| HP-UX / IA64 | no | yes |

For an Ada team that's already on one of these platforms (avionics
shops, industrial controllers, mainframe migration projects), GADA is
the *only* path to running modern Go libraries (e.g.,
`golang.org/x/crypto/curve25519`, `prometheus/client_golang`,
`google/uuid`) without first writing the bindings by hand or porting
the libraries to Ada.

The mechanism is simple: the GADA transpiler runs on any host that has
Go and produces Ada source. The Ada source compiles wherever GCC-Ada
runs. There is no per-platform porting work to do beyond what GNAT
already provides.

### 2. Real-time scheduling for goroutines

Stock Go's goroutine scheduler is GC-aware and work-stealing — excellent
for cloud workloads, useless for hard-real-time. There is no way in
vanilla Go to say "this goroutine has priority 90 and a deadline of
5 ms." The runtime simply doesn't have those concepts.

Ada's tasking model has had them for decades:

```ada
task type Hard_Realtime_Task
  with Priority => 90,
       CPU      => 2;
```

GADA wires these into the goroutine API as a graceful extension:

```go
//go:gada priority=90 deadline=5ms cpu=2
go controlSurfaceUpdateLoop()
```

The transpiler emits an Ada `task type` with the corresponding aspects
and dispatches to it via the Ada scheduler. On targets that compile
under the **Ravenscar profile** (DO-178C Level A certifiable, the ARINC
653 default for safety-critical avionics partitions), GADA goroutines
become Ravenscar tasks: bounded count, no dynamic spawn after
elaboration, ceiling-locking on protected objects, no blocking in
finalization. The Go program is now hard-real-time-suitable in a way
that no `gc`-built Go binary has ever been.

This is the win that motivates GADA's existence in industrial / aerospace
settings: **a Go program with the operational characteristics of an Ada
program.**

### 3. Embedded Go without a heavyweight runtime

TinyGo exists because the stock Go runtime is too heavy for
microcontrollers. TinyGo strips most of the runtime, kills goroutines on
bare-metal targets, and shrinks binaries by an order of magnitude — but
loses much of Go's concurrency model in the process.

GADA's runtime is *layered* (`GADA.Core` < `GADA.Async` < `GADA.Reflect`
< `GADA.Std`). On a Cortex-M4 with 64 KB RAM, you can compile against:

- `GADA.Core` only: slices, maps, GC, defer, panic/recover. No
  scheduler, no reflection, no stdlib. ~20–40 KB runtime overhead.
- `GADA.Core + GADA.Async (Ravenscar mode)`: + goroutines and channels,
  but with bounded task count and no dynamic creation. ~60–100 KB
  overhead.

The cost-of-features curve is fine-grained. A microcontroller target
that wants `select { case <-c: ... case <-time.After(1*time.Second): ... }`
can have it; one that doesn't can omit the entire async layer. Compare
TinyGo, where the choice is largely binary.

The runtime is built as a set of Alire crates with explicit feature
flags, so a build-time configuration like:

```toml
[gada-runtime]
profile = "ravenscar"
features = ["core", "async-bounded"]
gc      = "static-pool"   # or "boehm" for hosted targets
```

selects the runtime shape. This composes cleanly with Ada's build
system and produces statically linked binaries with no surprise
dependencies.

### 4. Bidirectional Ada/Go interop in one binary

Today, Ada-Go interop happens via cgo or via a Go process exposing
a network/IPC API to an Ada process. Both are awkward, runtime-heavy,
and impose ABI-level constraints on every type that crosses the
boundary.

GADA collapses the boundary. Once a Go module is transpiled, it is an
Ada library. An Ada program does:

```ada
with Gada.Std.Crypto.Sha256;
with Gada.Std.Encoding.Json;

procedure Demo is
   Hash : constant String :=
     Gada.Std.Crypto.Sha256.Sum_String ("hello");
   Doc  : Gada.Std.Encoding.Json.Value :=
     Gada.Std.Encoding.Json.Parse ("{""x"":1}");
begin
   ...
end;
```

— and the Go libraries are just packages, indistinguishable from
hand-written Ada from the call site. Calls are direct (no FFI marshaling),
types are mapped (Go `[]byte` → Ada `Stream_Element_Array`,
Go `string` → Ada `String` via UTF-8 decoder), errors propagate through
Ada exceptions or Go-style error returns at the user's choice.

The reverse direction is supported via a `gada-import` directive in
Go source:

```go
//go:gada import "Some_Ada_Package"
package myapp
```

— which exposes the named Ada package as a Go-callable namespace inside
the transpiled module.

The net effect: an Ada team can adopt `golang.org/x/crypto`,
`google/go-cmp`, `prometheus/client_golang`, or thousands of other Go
libraries as if they were Alire crates. This is the largest practical
ecosystem-expansion any Ada project has ever offered.

### 5. Formal verification of Go subsets

This is the most novel win. Stock Go has no formal verification story.
SPARK (the verifiable Ada subset) does, and it's the toolchain certified
for use in DO-178C, EN 50128, ISO 26262 contexts.

GADA's compiler can be invoked in `--mode=spark`:

```sh
$ gada build -mode=spark ./mypackage
$ gnatprove -P mypackage.gpr --level=2
```

For Go code that respects SPARK rules — no aliasing, no exceptions,
bounded data structures, no dynamic dispatch in verifiable contexts —
the transpiler emits SPARK source and `gnatprove` verifies it. The
output is a Go program with proofs of:

- absence of run-time errors (no nil deref, no out-of-bounds, no
  divide-by-zero, no integer overflow),
- adherence to user-supplied pre/postconditions,
- adherence to type invariants.

This is the only path that exists today for "verifiable Go." It will
not work for arbitrary Go programs (the Go subset that respects SPARK
rules is genuinely small — roughly: pure functions, fixed-size
structures, no goroutines except in Ravenscar configurations, no
reflection, no maps with dynamic keying). For the subset that *does*
respect those rules — which includes most algorithmic kernels, parsers,
serializers, cryptographic primitives — GADA delivers something the
Go ecosystem has no alternative for.

The compiler degrades gracefully: in `--mode=mixed`, modules that
respect SPARK rules emit SPARK and the rest emit plain Ada. The
verified portions become *islands of proof* inside an otherwise normal
program. That is genuinely useful for safety-critical teams that want
to verify the cryptographic core of a Go library while leaving the rest
of the program untouched.

---

## What GADA does NOT win at

In the spirit of honesty about tradeoffs:

- **Performance.** GADA-compiled binaries will be slower than `gc`-built
  ones on most workloads on most platforms. Goroutine context switches
  cost more (no userspace stack manipulation as fine-tuned as Go's
  runtime). GC throughput is Boehm's, which is solid but not Go's
  generational GC. Channel ops have a protected-object lock; Go's are
  lock-free in many fast paths. Expect 1.5x–3x slower for
  CPU-bound code, 2x–5x slower for goroutine-heavy code, in v1.0. This
  improves over time but will not match `gc` and isn't trying to.
- **Compile-time speed.** Adding an Ada compilation step on top of
  Go-front-end + transpilation makes builds slower than `go build`.
- **Runtime introspection.** Reflection works for the common cases
  (struct walk, type comparison, JSON encode/decode), but exotic uses
  (unmarshalling into arbitrary nested generic types, runtime code
  generation) lag stock Go.
- **`unsafe` package.** Supported but with a coarser model; some
  patterns that work in stock Go will fail GADA's transpiler.
- **`cgo`.** Out of scope for v1.0.

These limits are tracked in `docs/adr/` and are not silent. A user who
hits one will see a clear error pointing to the ADR that documents the
limitation.

---

## Architecture

```
                 ┌──────────────────────────┐
                 │  Go source (.go)         │
                 └────────────┬─────────────┘
                              │
                              ▼
        ┌────────────────────────────────────────┐
        │  GADA Compiler (Go binary)             │
        │  ┌──────────────────────────────────┐  │
        │  │ go/ast + go/types + packages     │  │  ← unchanged Go front-end
        │  └──────────────────────────────────┘  │
        │  ┌──────────────────────────────────┐  │
        │  │ IR transform                     │  │  ← typed AST → GADA-IR
        │  └──────────────────────────────────┘  │
        │  ┌──────────────────────────────────┐  │
        │  │ Ada emission                     │  │  ← GADA-IR → .ads/.adb
        │  └──────────────────────────────────┘  │
        └────────────────────┬───────────────────┘
                             │
                             ▼
            ┌──────────────────────────────┐
            │  Ada source (.ads / .adb)    │
            │  + project file (.gpr)       │
            └─────────────┬────────────────┘
                          │
                          ▼
        ┌────────────────────────────────────────┐
        │  GNAT (gprbuild + gcc Ada frontend)    │
        └────────────────────┬───────────────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │  Native binary       │
                  │  + GADA Runtime      │
                  └──────────────────────┘

GADA Runtime (Ada library, layered):

  ┌─────────────────────────────────────────────┐
  │ GADA.Std    fmt, errors, strings, net, ...  │
  ├─────────────────────────────────────────────┤
  │ GADA.Reflect   type metadata, TypeOf/ValueOf│
  ├─────────────────────────────────────────────┤
  │ GADA.Async   scheduler, channels, select    │
  ├─────────────────────────────────────────────┤
  │ GADA.Core    slices, maps, defer, panic, GC │
  ├─────────────────────────────────────────────┤
  │ GNAT runtime + Ada.Containers + System      │
  └─────────────────────────────────────────────┘
```

Each runtime layer is independently buildable and selectable. A
deployment for an embedded target may include only `GADA.Core`. A
verification target may include `GADA.Core` + `GADA.Async (Ravenscar)`.
A general-purpose deployment includes all four.

---

## Build and try it

*Not yet available.* See [`roadmap/`](./roadmap/) Phase 1 for the
"hello world" milestone. When complete, the workflow will be:

```sh
$ git clone <this-repo> gada && cd gada
$ make bootstrap            # fetch deps, build compiler
$ ./bin/gada build ./examples/hello
$ ./examples/hello/hello
hello, GADA
```

---

## Testing & coverage

GADA's quality gate is unconditional unit testing with measurable
coverage. The policy:

| Component | Coverage target | Tool |
|---|---|---|
| `runtime/` (Ada packages) | **100% executable lines** | `gcov` + `lcov` (or `gnatcoverage` where available) |
| `compiler/` (Go packages) | **≥ 90% lines, ≥ 95% in emit/types** | `go test -cover` + `go tool cover` |
| `stdlib/` (Go-shaped Ada) | **≥ 95% lines** | `gcov` + `lcov` |
| End-to-end (`examples/`) | every example runs in CI | shell-driven |

Deviations from a coverage target require an explicit `COVERAGE.md`
exception in the offending package, with rationale and reviewer sign-off.
A PR that drops coverage below the gate fails CI; there is no override.

Every public API has at least one direct unit test. Every fixed bug has
a regression test. There is no "I'll add tests later" register.

Coverage reports are published per-PR and rendered as a comment on the
PR description.

---

## Roadmap & contributing

[`roadmap/`](./roadmap/) is the canonical work tracker, organized by
phases with checklists and verification commands per item. It is
designed to be agent-consumable: subagents can pick up an unchecked
item, do the work, run the verification, and tick the box.

[`AGENTS.md`](./AGENTS.md) (also accessible as `CLAUDE.md`) holds the
project manifest, design principles, and the agent workflow contract.

To contribute:

1. Read `AGENTS.md`.
2. Open `roadmap/README.md` and find an unchecked item in the active phase.
3. Implement against the verification command.
4. Open a PR.

---

## License

TBD. Treat all code as unlicensed until the project owner sets a
license.
