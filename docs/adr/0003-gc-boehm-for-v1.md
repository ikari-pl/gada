---
type: adr
title: "ADR-0003: Use Boehm-Demers-Weiser as the v1 garbage collector"
status: accepted
created: 2026-05-01
deciders: [gada-core]
tags: [runtime, gc, memory, ada]
related:
  - "[[0000-record-architecture-decisions]]"
  - "[[0002-runtime-layered]]"
  - "[[0004-scheduler-libco-for-v1]]"
  - "[[0005-libgc-binding-via-pkgconfig]]"
  - "[[roadmap/00-foundation]]"
---

# ADR-0003: Use Boehm-Demers-Weiser as the v1 garbage collector

## Context

Go's memory model is garbage-collected and that is non-negotiable for
GADA: a transpiled Go program cannot ask the user to call `free`. The
runtime must reclaim memory on its own behalf. Ada's standard runtime
does not include a garbage collector — it offers controlled types,
storage pools, and `Ada.Finalization`, but not tracing GC.

We therefore have to ship a GC. The realistic options for a v1 are:

1. **Boehm-Demers-Weiser conservative GC (libgc).** A
   well-known, broadly-portable conservative tracing collector with
   30+ years of production use (the GCC Java front-end shipped it,
   Mono shipped it, dozens of Scheme implementations ship it).
   Ships as a system library on most Unix-likes and is available
   via Alire.
2. **A precise tracing GC of our own.** Requires the compiler to
   emit type maps for every stack frame and every heap object, and
   requires the runtime to walk those maps on every collection.
   Multi-person-year project. The Go reference compiler did this,
   and the v1 of Go (2009–2012) used a Boehm-style collector
   precisely because building the precise version takes time.
3. **Reference counting.** Lightweight, deterministic, but does
   not collect cycles without an additional cycle collector. Go
   programs routinely produce reference cycles (caches, doubly
   linked lists, observer patterns). Refcounting alone is not a
   credible Go GC.
4. **No GC, region-based or arena allocation only.** Would force
   a Go program to obey allocation patterns that Go programs do
   not obey. Not a credible v1.

We need to ship a v1.0 in finite time. We also need to leave room
for a precise GC later, because conservative scanning has known
limits (false retention, no stack-pointer rewriting for stack
shrinking, and well-documented pathologies on 32-bit address
spaces). This ADR picks the v1 GC and names what it forecloses.

This ADR is anchored in `AGENTS.md` non-goals ("Writing our own
GC. Boehm-Demers-Weiser is the v1 GC.") and the "What GADA does
NOT win at" section of `README.md` ("GC throughput is Boehm's,
which is solid but not Go's generational GC").

## Decision

We use Boehm-Demers-Weiser (`libgc`) as the GADA v1 garbage
collector for hosted targets. Concretely:

1. **Hosted targets use libgc.** The runtime allocates
   GC-managed objects via `GC_malloc` / `GC_malloc_atomic`
   (atomic for objects with no pointer-typed fields).
   Deallocation is implicit via `GC_collect` and the
   incremental collector.
2. **The GC interface lives in `Gada.Core`.** Per
   [[0002-runtime-layered]], `Gada.Core` exposes
   `Gada.Core.Memory.Allocate` /
   `Gada.Core.Memory.Allocate_Atomic` /
   `Gada.Core.Memory.Register_Finalizer`. The libgc-backed
   implementation lives behind that interface so the GC is
   replaceable without touching higher layers. Higher layers
   never call `GC_malloc` directly.
3. **Conservative scanning.** Stacks, registers, and
   non-atomic heap objects are scanned conservatively.
   Goroutine stacks (per
   [[0004-scheduler-libco-for-v1]]) are registered with libgc
   via `GC_register_my_thread` / `GC_unregister_my_thread`,
   and libco-managed coroutine stacks are registered as
   alternate roots when activated.
4. **Atomic allocation where types permit.** The compiler
   emits `Allocate_Atomic` for objects whose static type tree
   contains no pointer fields (Go `int`, `float64`, fixed-size
   arrays of those, structs of only those). This is a
   compile-time decision in the emit layer; it is not a
   runtime classification. Atomic allocation cuts scanning
   work proportionally and is the single largest hosted-GC
   tuning lever we get for free.
5. **Embedded targets do not require libgc.** Per
   [[0002-runtime-layered]] the runtime is layered; the
   build profile for an embedded target may select a
   `static-pool` allocator (a fixed-size storage pool with
   no collector) instead. `static-pool` is the right answer
   for Ravenscar targets where dynamic allocation after
   elaboration is itself prohibited.
6. **Finalizers run via Ada.Finalization on hosted targets.**
   Objects with finalizers register a libgc finalizer that
   trampolines into a `Gada.Core.Memory` callback, which
   then runs the user's `defer` chain or a Go-level finalizer
   (`runtime.SetFinalizer`). Finalizer ordering is libgc's,
   not Go's — see Consequences.

## Consequences

- **What now becomes easier.** GADA ships in finite time. We
  inherit 30+ years of libgc bug-fixes, platform ports, and
  performance tuning. Conservative scanning means the
  compiler does not have to emit per-frame stack maps or
  per-type pointer maps, which collapses a multi-person-year
  workstream out of the v1 schedule. libgc supports the
  threading models we need (POSIX threads on hosted targets,
  user-mode coroutines via the alternate-stack-roots API).
  Disabling the GC for SPARK / Ravenscar builds is the same
  mechanism we already use for layer omission.
- **What now becomes harder.** Conservative scanning has
  false retention: an integer that happens to look like a
  pointer keeps the pointed-at object alive. The pathology
  is well-known and bounded but real, and on 32-bit
  platforms it is large enough that we will discourage
  32-bit hosted targets in v1. Goroutine stacks must be
  conservatively traced, which means we cannot move them
  for stack shrinking — Go's stack-copy growth policy is
  out for v1; libco-managed stacks are fixed-size per
  goroutine, with size selectable per
  `//go:gada` annotation. GC throughput is Boehm's, which
  is competitive but not Go's generational collector;
  goroutine-heavy allocation-heavy workloads will see 2x–5x
  slower allocation paths than `gc`-built Go. Binary size
  on hosted targets includes libgc (~200–400 KB depending
  on platform). Finalizer ordering follows libgc's
  semantics, not Go's, and we will document the divergence
  rather than paper over it.
- **What is now off-limits.** Building a precise tracing GC
  for v1.0 — that work is explicitly post-1.0 and requires
  a follow-on ADR before any code lands. Emitting per-frame
  stack maps from the compiler — these are unused under
  conservative scanning and would be dead weight. Adding a
  refcount-only or region-only allocator path that user
  code can opt into without going through the
  `Gada.Core.Memory` interface — bypassing the interface
  defeats the layering. PRs that propose to write a custom
  GC for v1.0 are rejected unless they supersede this ADR.

## Alternatives considered

**Precise tracing GC (Go-style generational).** This is
where we want to be eventually. Rejected for v1.0 on
schedule grounds. The compiler-side cost (per-frame stack
maps, per-type pointer maps, write-barrier emission) is a
multi-person-year track on its own, and we would not ship
v1.0 if we took it on now. A future ADR can supersede this
one when the precise-GC track is funded.

**Reference counting (with cycle collector).** Used by
Swift, by CPython (with a cycle-collector adjunct), by
Nim. Rejected because Go programs produce cycles routinely
(channels with self-referential structures, doubly linked
lists, caches), and a credible cycle collector is roughly
the same engineering effort as a tracing GC. We would pay
the refcount overhead on every pointer assignment for no
schedule win.

**Ada controlled types (Ada.Finalization) only.** Ada's
deterministic finalization handles RAII patterns but does
not collect cycles, does not collect heap memory whose
liveness depends on stack roots, and does not handle the
actual hard problem (when does the heap collection happen?).
Rejected — controlled types are a complement to a GC, not a
replacement for one.

**MPS (Memory Pool System) from Ravenbrook.** A
mature, precise, segmented GC with strong production
credentials (Open Dylan, AHOY). Rejected for v1.0 because
its integration cost is non-trivial (it expects to control
the allocator surface) and it carries a more restrictive
license that we have not yet evaluated against TBD GADA
licensing. Reconsidering MPS for the post-1.0 precise-GC
track is sensible.

**Static-pool only (no collector).** Workable for
Ravenscar / embedded targets where dynamic allocation after
elaboration is forbidden anyway, and we already adopt this
as the embedded profile. Not a credible *general-purpose*
v1 — most Go programs allocate freely.

## See also

- [[0000-record-architecture-decisions]] — the ADR convention
  this file follows.
- [[0002-runtime-layered]] — the runtime layering. The GC
  interface lives in `Gada.Core`; this ADR fixes the v1
  implementation behind that interface.
- [[0004-scheduler-libco-for-v1]] — the scheduler ADR.
  Goroutine-stack registration with libgc is part of the
  scheduler/GC contract; both ADRs read together describe
  it end-to-end.
- [[0005-libgc-binding-via-pkgconfig]] — the implementation
  refinement. Picks pkg-config as the dep-resolution mechanism
  and names the measurable parity bar any future custom-GC
  successor must clear.
- [[roadmap/00-foundation]] — the foundation phase that
  ratifies this ADR. The runtime layering and GC choice are
  Phase 0 ratifications, not Phase 0 implementations; the
  libgc wiring is a later-phase deliverable.
