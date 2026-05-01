---
type: adr
title: "ADR-0004: M:N goroutine scheduler over Ada tasks + libco for hosted; one-task-per-goroutine for Ravenscar"
status: accepted
created: 2026-05-01
deciders: [gada-core]
tags: [runtime, scheduler, concurrency, goroutines, ravenscar]
related:
  - "[[0000-record-architecture-decisions]]"
  - "[[0002-runtime-layered]]"
  - "[[0003-gc-boehm-for-v1]]"
  - "[[roadmap/00-foundation]]"
---

# ADR-0004: M:N goroutine scheduler over Ada tasks + libco for hosted; one-task-per-goroutine for Ravenscar

## Context

Go's concurrency model is goroutines: extremely cheap units of
execution, with dynamic spawn (`go func() { ... }()`), an M:N
scheduler that multiplexes them onto a small pool of OS threads,
cooperative yielding at function-call boundaries, work stealing,
and stack growth via copy-on-grow. A single Go program routinely
creates millions of goroutines.

Ada's concurrency model is tasks: heavyweight units of execution,
mapped 1:1 to OS threads on hosted targets, with priorities,
deadlines, ceiling-locking on protected objects, and (under the
Ravenscar profile) bounded count and no dynamic spawn after
elaboration. A single Ada program routinely creates dozens of
tasks; thousands is unusual; millions is unimaginable.

GADA must run Go programs that spawn lots of goroutines, *and* it
must produce certifiable Ravenscar binaries for embedded /
safety-critical targets. The two constraints pull in opposite
directions. One-Ada-task-per-goroutine is too expensive on hosted
(no Go program survives that mapping). M:N scheduling with
unbounded dynamic spawn is illegal under Ravenscar.

We need a scheduler design that (a) is fast enough on hosted that
realistic Go programs run, (b) compiles under Ravenscar, and
(c) does not require two completely separate runtimes. This ADR
picks that design and names what it forecloses.

This ADR is anchored in `README.md` "Real-time scheduling for
goroutines" + "Embedded Go without a heavyweight runtime"
(Ravenscar mode for hard-real-time and bounded-task embedded
targets) and in "What GADA does NOT win at" ("goroutine context
switches cost more than Go's runtime — no userspace stack
manipulation as fine-tuned as Go's runtime").

## Decision

We ship a single scheduler with two compile-time profiles, both
in `Gada.Async`:

1. **Hosted profile (default): M:N over Ada tasks + libco.**
   - A pool of `Worker` Ada tasks is created at scheduler init,
     sized by default to `System.Multiprocessors.Number_Of_CPUs`.
     Each worker runs a Go-style fetch-and-execute loop.
   - Each goroutine gets a fixed-size stack allocated via libco
     (`co_create`) with a default size selectable per
     `//go:gada stacksize=...` annotation. The default is
     64 KB; programs that exceed it must annotate.
   - Goroutine context switches are libco swaps inside a worker
     task. The OS does not see goroutine-level switches; only
     worker tasks are visible to the kernel scheduler.
   - Yielding happens at: function-call entry (compiler-emitted
     `Maybe_Yield`), channel send/receive, `select`, and
     `time.Sleep`. We do **not** preempt at arbitrary
     instructions — preemption is cooperative, like Go ≤ 1.13.
   - Stacks are fixed-size per goroutine. A stack-overflow check
     is emitted at function entry (compiler decision in the
     emit layer); overflow raises a Go-level panic, not a
     hardware fault.
   - Goroutine stacks are registered with libgc as alternate
     scanning roots when the goroutine is suspended (per
     [[0003-gc-boehm-for-v1]]).

2. **Ravenscar profile (opt-in): one-task-per-goroutine.**
   - The M:N scheduler is compiled out. `Gada.Async` builds
     against `pragma Profile (Ravenscar)`.
   - Each `go func() { ... }()` in user code becomes a
     statically declared Ada `task type` instantiation. The
     count of such tasks is bounded — the user must declare
     a maximum at module level (`//go:gada max_goroutines=N`),
     and exceeding it at runtime is a panic.
   - Dynamic spawn after elaboration is illegal. Programs that
     compile under Ravenscar must declare all goroutines
     statically; this is a transpile-time check, not a runtime
     check.
   - Channels become protected objects with ceiling-priority
     locking. `select` lowers to a Ravenscar-legal entry-call
     pattern.
   - libco is not used. No userspace coroutines. Each goroutine
     is a real Ada task with all the Ada-task properties
     (priority, deadline, CPU affinity).

3. **The profile is a build-time choice, not a per-package
   choice.** A program is built either hosted-M:N or
   Ravenscar; mixing within one binary is not supported.

4. **The scheduler lives in `Gada.Async`.** Per
   [[0002-runtime-layered]], `Gada.Async` is a single layer
   above `Gada.Core`. The scheduler may use `Gada.Core`'s
   memory and panic primitives; it must not depend on
   `Gada.Reflect` or `Gada.Std`. A program that uses no
   goroutines can omit `Gada.Async` entirely.

5. **`//go:gada` annotations are the surface for Ada-side
   knobs.** Priority, deadline, CPU affinity, stacksize, and
   `max_goroutines` are exposed as `//go:gada` directives on
   the relevant `go` statement or at file scope. The compiler
   front-end ([[0001-go-frontend-via-go-ast]]) reads these as
   doc-comments via `go/ast` and lowers them to Ada aspects
   in the emit layer.

## Consequences

- **What now becomes easier.** Hosted Go programs run with
  goroutine costs in the same ballpark as Go's runtime —
  libco's context-switch cost is real but bounded and well
  understood. Ravenscar deployment becomes a build flag:
  programs whose goroutine usage fits the
  statically-declared model compile to certifiable binaries
  with no runtime surprises. The same `Gada.Async` source
  tree serves both worlds — there are not two schedulers
  to maintain. Real-time aspects (priority, deadline, CPU
  affinity) come for free on the Ravenscar profile because
  they are Ada-task properties; on hosted profile they are
  honored on a best-effort basis (worker-task priorities
  govern, not per-goroutine).
- **What now becomes harder.** Hosted-profile context
  switches are slower than Go's runtime — libco is
  general-purpose and not as tight as Go's
  `runtime.gosched`-and-friends. Expect 2x–5x slower
  goroutine-heavy workloads in v1.0; this is a known
  tax and is documented in `README.md`. Stack growth is
  not supported under either profile — every goroutine has
  a fixed-size stack, and overflow panics. Programs that
  rely on Go's "start small, grow as needed" stack
  semantics must annotate stack size up front. Preemption
  is cooperative; a tight loop with no function calls
  starves siblings (this matches Go ≤ 1.13 and is a
  documented v1.0 limit). Ravenscar profile loses
  unbounded `go func()` ergonomics — programs that
  routinely spawn one-shot goroutines must be restructured
  to a worker-pool pattern, and this is the single
  largest user-visible adaptation cost when porting a Go
  program to a Ravenscar target.
- **What is now off-limits.** Implementing a Go-runtime-fidelity
  M:N scheduler with userspace stack copy-on-grow — that is
  Go's runtime and we are not rebuilding it. PRs that propose
  it are rejected unless they supersede this ADR. Mixing
  M:N and Ravenscar in one binary. Pre-emptive scheduling
  (signal-based preemption) — the scheduler is cooperative
  in v1.0; a future ADR may add preemption with a runtime
  cost analysis. Bypassing `Gada.Async` to hand-write Ada
  tasks for Go-level concurrency in user code — the user
  surface is `go`, channels, and `select`, lowered through
  `Gada.Async`; if a program needs Ada-task-level control
  it should write Ada, not Go.

## Alternatives considered

**One Ada task per goroutine on all targets.** The
"easy" implementation. Rejected for hosted because it does
not survive realistic Go programs (a million Ada tasks on
Linux is not a thing). Adopted *only* for the Ravenscar
profile, where bounded task count is already mandatory.

**Custom userspace scheduler in Ada (no libco).** Write
our own coroutine swap. Rejected for v1.0 — context-switch
correctness is genuinely subtle (signal handling, TLS,
stack-pointer adjustment, GC interaction) and libco is a
small, well-tested, public-domain implementation that
already solves these problems on every platform we care
about. A future ADR can supersede this if libco's footprint
or licensing becomes an issue.

**M:N scheduler portable to Ravenscar via task-pool
recycling.** Build M:N over a fixed pool of Ada tasks that
are recycled, so the count is bounded but multiplexing is
preserved. Tempting because it would give us one scheduler
for both profiles. Rejected because Ravenscar prohibits
the kind of context-switch the multiplexing requires —
Ravenscar tasks are not designed to be hijacked, and the
verification properties Ravenscar exists to provide
(no priority inversion, no deadline miss, certifiable
scheduling) depend on the OS scheduler seeing each task
directly. Recycling defeats the point.

**Cooperative threading via Ada protected entries only
(no libco).** Use Ada's protected-entry mechanism as the
sole concurrency surface and lower goroutines onto it.
Rejected for hosted because protected entries do not
provide the semantics goroutines need (a goroutine
suspended on a channel send is not waiting on a protected
entry's barrier — it is waiting on a value-transfer
event). The semantic mismatch would surface as a chain
of subtle bugs.

**Channels as bare Ada rendezvous instead of protected
objects.** Considered. Rejected because Ada rendezvous is
synchronous; Go channels can be buffered. Buffered channels
require a state-bearing object, and that is a protected
object. Unbuffered channels could be rendezvous, but
having two channel implementations doubles the test
surface for marginal win. We use protected objects for
both buffered and unbuffered channels in v1.0.

## See also

- [[0000-record-architecture-decisions]] — the ADR
  convention this file follows.
- [[0002-runtime-layered]] — the runtime layering. The
  scheduler is `Gada.Async`'s reason to exist; this ADR
  fixes its shape and its allowed dependencies.
- [[0003-gc-boehm-for-v1]] — the GC ADR. Goroutine-stack
  registration with libgc (alternate scanning roots) is
  part of the scheduler/GC contract.
- [[0001-go-frontend-via-go-ast]] — the compiler ADR. The
  `//go:gada` annotations this ADR depends on are read
  through `go/ast`'s doc-comment infrastructure.
- [[roadmap/00-foundation]] — the foundation phase that
  ratifies this ADR. The libco wiring and Ravenscar
  profile are later-phase deliverables, not Phase 0
  implementations.
