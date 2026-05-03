---
type: adr
title: "ADR-0008: SPARK opt-in per package, not whole-runtime"
status: accepted
created: 2026-05-02
deciders: [ikari]
tags: [spark, verification, runtime, layering]
related: [0002-runtime-layered, 0006-runtime-performance-bar]
---

# ADR-0008: SPARK opt-in per package, not whole-runtime

## Context

`CLAUDE.md` Pure Goal #4 commits the project to a real verification path:
"For Go code that respects SPARK rules, the compiler emits SPARK source,
and `gnatprove` verifies the program." That is a downstream promise. The
upstream question — which is open at the start of Phase 3 — is whether
the **runtime itself** should be SPARK.

The runtime cannot be uniformly SPARK. By design (`[[0002-runtime-layered]]`)
the layered runtime sits on top of:

- raw `System.Address` and `Ada.Unchecked_Conversion` (libco binding,
  registry trampolines in `Gada.Async.Context`),
- C bindings via `Interfaces.C` (libco, libgc) — `Convention => C`
  subprograms cannot be analysed by SPARK,
- `Limited_Controlled` finalisation for `Gada.Core.Defer` (SPARK
  excludes controlled types in subset profiles),
- task entries / protected objects for the Phase 3 scheduler (SPARK
  supports tasking only under the Ravenscar profile, which forecloses
  several scheduler designs we have not yet decided between).

Forcing the entire runtime under `SPARK_Mode => On` would either drop
those features or push them all behind `pragma SPARK_Mode (Off)`
escape hatches — at which point the SPARK label is decorative and
contributes no proof obligations. The opposite extreme — never running
gnatprove against the runtime — leaves Pure Goal #4 as a downstream
claim that is never tested upstream.

## Decision

1. **SPARK is opt-in per package, not whole-runtime.** Each runtime
   package declares its SPARK posture via `with SPARK_Mode => On|Off`
   on the spec and `pragma SPARK_Mode (On|Off);` on the body. Packages
   not annotated default to `Off` (gnatprove ignores them).

2. **The opt-in set is the **algorithmic core**, not the I/O perimeter.**
   First inclusions:
   - `Gada.Core.Hash` (this PR) — pure modular arithmetic.
   - `Gada.Core.Slices` (later) — bounded-aggregate semantics, no
     aliasing once the public API stabilises.
   - `Gada.Core.Maps` probe loop (stretch) — open-addressing
     termination is a textbook loop-variant exercise.

3. **The opt-out set is everything that touches the OS, C, or
   finalisation.** Permanent exclusions:
   - `Gada.Async.*` (libco, scheduler, channels) — `Convention => C`,
     raw addresses, tasking outside Ravenscar.
   - `Gada.Core.Defer` — `Limited_Controlled`.
   - `Gada.Core.IO` — wraps `Ada.Text_IO`, no proof value.
   - Anything binding C: libco, libgc.

4. **Proof is gated by `tools/prove.sh`, not `make ci`.** SPARK is
   slow (multi-prover dispatch, level-2 effort budget) and gnatprove
   is a multi-hundred-MB Alire toolchain dependency. Adding it to the
   PR-time `make ci` path is not worth the latency cost while the
   opt-in set is small. CI gains a `make prove` target only once the
   set is large enough that proof drift would be a regression risk.

5. **`runtime/PROOF.md` mirrors `runtime/COVERAGE.md`.** A table per
   package: SPARK posture (`On` / `Off` / `Mixed`), last-proven date,
   number of unproven VCs (target: 0). The file ships with this PR.

## Consequences

- **What now becomes easier.** Pure Goal #4 has a working upstream
  example: `tools/prove.sh` discharges every VC in `Gada.Core.Hash`
  with no human-written contracts. The same script extends to future
  opt-in packages with a one-line addition. The "verification path is
  real" claim in `CLAUDE.md` is now testable in CI as soon as the
  opt-in set warrants the prove-time cost.

- **What now becomes harder.** Every new public API in an opt-in
  package needs a SPARK-clean signature: no `access` types where
  `not null access constant` would do, no exception-raising contracts
  unless the exception is named in `Exceptional_Cases`. Authors of
  `Gada.Core.Slices` etc. inherit a constraint they did not have on
  Phase 2.

- **What is now off-limits.** A blanket `SPARK_Mode => On` at the
  runtime root is rejected — it would cascade `Off` overrides through
  `Gada.Async.*` and erode the value of the opt-in set. A PR proposing
  it must supersede this ADR. Likewise a PR that adds an opt-out
  package without a one-sentence rationale in `PROOF.md` is rejected:
  the opt-out set is enumerable on purpose, so a future SPARK-Pro
  upgrade can audit it.

## Alternatives considered

- **Whole-runtime SPARK.** Rejected: `Gada.Async.Context` and the
  upcoming scheduler need raw addresses, C bindings, and
  non-Ravenscar tasking. Whole-runtime SPARK would force `SPARK_Mode
  (Off)` on every body that matters, leaving the spec annotations as
  decoration with no VC discharge. The "verification" would be
  syntactic, not semantic.

- **No SPARK in the runtime; only in transpiled output.** Rejected:
  Pure Goal #4 is a property of the toolchain, and a toolchain that
  cannot prove its own primitives lacks credibility. Hash is the
  smallest possible upstream demonstration that the path works.

- **SPARK at the spec level only, with `SPARK_Mode (Off)` on every
  body.** Rejected for the same reason as whole-runtime SPARK:
  decorative. The spec annotations would not surface in CI failures
  and would drift out of sync with the bodies.

- **Wait until Phase 5+ when more of the runtime stabilises.**
  Rejected: the opt-in mechanism does not need a stable runtime, and
  shipping `Gada.Core.Hash` as proven now establishes the pattern
  before the runtime grows past the point where retrofitting is cheap.
