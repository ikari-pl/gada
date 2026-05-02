---
type: adr
title: "ADR-0006: 2× of Go runtime performance ceiling; Ada-2022-first; in-tree bench harness"
status: accepted
created: 2026-05-02
deciders: [gada-core]
tags: [runtime, performance, benchmarks, ada-2022, bar]
related:
  - "[[0000-record-architecture-decisions]]"
  - "[[0002-runtime-layered]]"
  - "[[0003-gc-boehm-for-v1]]"
  - "[[0005-libgc-binding-via-pkgconfig]]"
  - "[[roadmap/02-core-runtime]]"
---

# ADR-0006: 2× of Go runtime performance ceiling; Ada-2022-first; in-tree bench harness

## Context

[[0003-gc-boehm-for-v1]] named GADA's expected throughput as
"2x–5x slower than `gc`-built Go" on alloc-heavy workloads. The
5× ceiling was a deliberately permissive upper bound — libgc's
conservative tracing has structural costs over Go's generational
moving collector — but it was framed as "honest", not "committed
to". Six months from now a contributor reading ADR-0003 cannot
tell whether 4× is acceptable (ADR-0003 says yes) or unacceptable
(this ADR says no).

The same gap holds for the per-module design choices that move us
toward or away from the bar:

- Slices: linear-vs-geometric growth?
- Maps: separate-chaining buckets vs Swiss-table open addressing?
- Defer: heap-allocated linked list (Go pre-1.13) vs Ada
  controlled-type stack allocation?
- Atomic-vs-traced allocation: optional optimization or mandatory
  static analysis at every `new`?

Without a written bar each of these reads as a per-PR judgment
call. Cumulative drift on judgment calls is how runtimes end up at
10× slowdown nobody can later untangle.

This ADR sets the bar at **2× of Go's `gc` reference compiler** for
the runtime modules Phase 2 ships, names the Ada 2022 features the
bar implies, commits the per-module design choices the bar binds
us to, and locks the bench-harness shape — in-tree, lean, designed
to also back a future `testing.B` reimplementation.

## Decision

### The performance bar

For every runtime module shipped in Phase 2 and forward:

1. **Throughput on micro-benchmarks ≤ 2× a stock Go (`gc`-built)
   equivalent**, on the same hardware, same workload, same
   measurement methodology. "Throughput" means: ops/second for
   alloc-heavy workloads, p99 latency for synchronous request/
   response workloads.

2. **Named exceptions** are allowed but require explicit
   documentation in the module's `PERF.md` row plus a one-paragraph
   justification. The expected exceptions today:
   - workloads that stress libgc's conservative scanning (deeply
     nested traced-pointer structures): up to 5× allowed —
     structural cost cited in ADR-0003;
   - workloads exercising goroutine context-switch density (libco's
     M:N switch is ~3× a `gc` goroutine switch — Phase 3 will
     quantify; up to 5× allowed for the v1 scheduler).

3. **Non-bar, non-aspiration**: matching Go's GC throughput on
   alloc-only benchmarks. ADR-0003 explicitly ceded this; ADR-0005
   names the post-1.0 succession criteria for closing the gap.

### Ada 2022 features mandated for Phase 2 module surface

Every Phase 2 module that ships uses these where applicable, by
directive not preference. Reviewers reject new module surface that
introduces Ada-95-or-2005-shape patterns where a 2022 feature
would have been both more correct and more efficient.

- **`'Aggregate` aspect** for user-facing literal construction
  (Slices: `Of (1, 2, 3)`; Maps: `Of [(K1 => V1), …]`). The
  compiler-emit pass for Go's `[]T{…}` and `map[K]V{…}` literals
  targets these aggregates directly — no intermediate heap object,
  no per-element loop in the generated Ada.

- **`pragma Pre`/`Post` and Subtype Predicates** for runtime-
  invariant contracts. Slices: `Pre => Index in 0 .. Len(S) - 1`.
  Maps: `Post => (if Found then Lookup(M, K) = V)`. Compile to
  optimized runtime checks under `-gnata`; become SPARK-verifiable
  predicates under `-mode=spark` (Phase 9 leverage).

- **`Static` functions** for compile-time evaluation of pure
  utilities (hashes of constant keys, layout calculations).

- **`'Reduce` attribute** for parallel reductions over slices
  (sum, max, fold). Stays sequential under `-gnatp0`; auto-
  vectorizes under `-gnatp` on supported targets.

- **`@` redux operator** for compact accumulator updates
  (`Acc := @ + X` instead of `Acc := Acc + X`).

- **`Limited_Controlled`** for zero-allocation defer. The deferred
  call captures by value into a stack-allocated controlled record;
  `Finalize` runs it at scope exit, deterministically, including
  under exception unwind. **Better than Go's heap-allocated defer**
  for the common case (Go open-coded equivalent patterns starting
  in 1.13; Ada gives it for free from the language semantics).

- **Generic packages with formal package parameters** for type-safe
  Maps with hash-callback contracts.

Pre-Phase-2 code (`Gada.Core.IO`, `Gada.Core.Memory`) is grandfathered
until it naturally needs revision — we don't churn for churn's sake.

### Per-module design choices (binding for Phase 2)

The bar implies these. Listed here so the next agent does not
re-derive them; per-item roadmap notes elaborate as each ships.

- **Slices** (`Gada.Core.Slices`): 3-word header (ptr, len, cap),
  geometric growth (2× under 256 elements, 1.25× thereafter — same
  policy as `runtime/slice.go`), `Allocate_Atomic` for pointer-free
  element types decided at compile-emit time, `memmove` (libc) for
  realloc copy.
- **Maps** (`Gada.Core.Maps`): Swiss-table layout (control-byte
  array + parallel slot array, group-of-16 SIMD probe), SipHash-1-3
  for hashing, load factor 7/8 before rehash, cache-line aligned.
- **Defer** (`Gada.Core.Defer`): per-defer-site `Limited_Controlled`
  type, open-coded for the single-defer common case.
- **Panic / Recover** (`Gada.Core.Panic`): Ada exception with
  payload; recover via finalize-time exception inspection; defer
  chain runs through finalization order.

### Bench harness: in-tree, lean, lands with first Phase 2 module

A `runtime/bench/` directory carries Ada-native benchmarks
following the same suite-registration shape as `runtime/tests/`.
Methodology cribbed from Go's `testing.B`:

- Wall-clock via `Ada.Real_Time.Clock` (sub-microsecond
  resolution).
- Allocation tracking via libgc's `GC_get_total_bytes` delta around
  the inner loop.
- Warmup, N iterations scaled until measurement variance bounded,
  geometric-mean reporting.
- Output format compatible with `benchstat` so a `runtime/PERF.md`
  table tracks the GADA-vs-Go ratio per module per benchmark per
  phase.

We do **not** use `gnatcoll-benchmark` — too heavy for our needs
and adds an Alire dep without a clean wins-over-cost story.

The harness lands as the *zeroth* sub-item of the first Phase 2
module that would consume it (Slices). Until then the bar applies
but verification is by inspection (allocation patterns, growth
strategies, Ada-2022 feature use). This is a deliberate "build
the measuring stick once you have something to measure" sequencing
— not aspiration.

CI runs `make bench` on PR (~30s after the harness lands). Bar
enforcement: regressions of >10% fail CI the same way coverage
regressions do today. The 2× bar itself is checked at phase exit,
not per PR — optimization happens iteratively and a single PR
that lands a 1.8× module shouldn't be blocked because the next PR
makes it 1.9×.

### Reimplementing `testing.T` / `testing.B` is greenlit

When transpiled Go code starts importing `testing` (Phase 5 stdlib
wave 1, possibly earlier if a Go example needs `t.Run`), we
reimplement Go's `testing` package surface in Ada. The same
in-tree bench harness is the natural backend for `testing.B`;
AUnit (already in the runtime tests) is the natural backend for
`testing.T`. AUnit is **not** transitively exposed to transpiled
Go code; the transpiled side uses our reimplementation.

This ADR ratifies the direction. No separate decision is needed
when the work starts.

## Consequences

- **What now becomes easier.** Every module's perf is measurable,
  comparable across phases, and reviewable as a diff. Future
  contributors have a written bar to clear instead of a shifting
  reviewer judgment. Ada 2022 mandates collapse most "should we
  use feature X here" reviews into "yes, the ADR mandates it for
  new module surface". Per-module design choices (Swiss tables,
  controlled-type defer) are written down once instead of
  re-litigated per PR.

- **What now becomes harder.** Every Phase 2 module ships with
  bench numbers in `PERF.md` as a merge precondition (once the
  harness lands). Bench harness build adds ~30s to CI. PRs that
  introduce >10% regressions are blocked even when the regression
  looks small in isolation — the gate doesn't know engineering
  context. The Ada-2022 mandate means contributors who learned
  Ada-95 have a learning curve; CONTRIBUTING.md links the relevant
  LRM sections.

- **What is now off-limits.** Shipping a Phase 2 module *without*
  a `PERF.md` row and a bench-harness entry (once the harness
  exists). Citing ADR-0003's 5× ceiling as the bar — this ADR's
  2× supersedes it for Phase 2 modules forward, named exceptions
  aside. Adding `gnatcoll-benchmark` or any other heavy bench dep
  when the in-tree harness is the right call. Refusing to use
  Ada 2022 features on aesthetic grounds — if a 2022 feature is
  more correct or more efficient for the task, use it. Designing
  modules around a "we'll measure later" assumption.

## Alternatives considered

**Keep ADR-0003's 5× ceiling.** Looser, less binding, less
contributor pressure. Rejected because 5× is "we will be slower";
2× is "we will be competitive on commodity workloads". GADA's
audience (Ada developers using Go libraries; embedded engineers;
certification teams) is not throughput-blind. A 5× slowdown is
acceptable on availability-bound workloads; on alloc-heavy
workloads it's the difference between "usable" and "wrap your own
bdw-gc binding instead". 2× is the bar that keeps the choice
live.

**Leave the bar implicit; trust reviewer judgment.** What ADR-0003
does today; the result is exactly the drift the Context section
opens with. Rejected.

**Use `gnatcoll-benchmark` instead of an in-tree harness.**
Maintained by AdaCore, well-tested, integrates with GNATtest. Cost:
adds an Alire dep (one more thing every contributor installs); the
methodology is generic and not optimised for our (libgc-allocator,
libco-coroutine) workloads; Go's `testing.B` is the methodology Go
contributors recognise and we want our bench numbers comparable to
`go test -bench`. Rejected; revisit if the in-tree harness becomes
load-bearing maintenance.

**Require Go-equivalent benchmark code under `compiler/bench/`** —
a parallel Go corpus we transpile + run vs. native `gc`-built. Best
methodology by far. Cost: full Go toolchain in the bench loop, ~5–
10 min CI bench time, plus the comparison-harness engineering.
Defer to Phase 11 (validation & 1.0); per-module bench in
`runtime/` is the lean Phase 2 answer.

**Land the bench harness as a roadmap item *before* any Phase 2
module.** Cleanest dependency order. Rejected because we don't yet
know what shape the Slices benchmarks need — building the harness
first risks designing for hypothetical workloads. Build harness
+ first module together; second module reuses harness as-is.

## See also

- [[0003-gc-boehm-for-v1]] — sets the GC; this ADR tightens the
  perf bar from "2x–5x" to "2x except named cases".
- [[0005-libgc-binding-via-pkgconfig]] — the GC exit ramp; future
  custom-Ada-GC succession plan. The 2× bar here applies to *both*
  the libgc and any future GC; if a successor regresses below 2×
  it fails its own succession criterion.
- [[0002-runtime-layered]] — the layering. The bar applies layer
  by layer.
- [[roadmap/02-core-runtime]] — the active phase. Per-module
  design choices listed in §"Per-module design choices" land as
  roadmap-item notes when each item ships.
- [[../imperfections]] — bench-harness scaffolding deferred from
  this ADR's first commit; tracked there as an Active item with
  the resolution criterion (lands with first Slices benchmark).
