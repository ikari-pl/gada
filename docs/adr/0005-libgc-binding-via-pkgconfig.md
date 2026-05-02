---
type: adr
title: "ADR-0005: Bind libgc via pkg-config; succeed it post-1.0 only on measured parity"
status: accepted
created: 2026-05-01
deciders: [gada-core]
tags: [runtime, gc, build, dependencies, pkg-config]
related:
  - "[[0000-record-architecture-decisions]]"
  - "[[0002-runtime-layered]]"
  - "[[0003-gc-boehm-for-v1]]"
  - "[[0004-scheduler-libco-for-v1]]"
  - "[[0006-runtime-performance-bar]]"
  - "[[roadmap/02-core-runtime]]"
---

# ADR-0005: Bind libgc via pkg-config; succeed it post-1.0 only on measured parity

## Context

[[0003-gc-boehm-for-v1]] picked Boehm-Demers-Weiser (`libgc`, package
`bdw-gc`) as the v1 GC. It deliberately left two implementation
questions open, both of which surface immediately when Phase 2's
**GADA.GC** roadmap item starts.

1. **How does libgc reach the build?** The realistic options are:
   bare `pragma Linker_Options ("-lgc")` (relies on default linker
   paths), `pkg-config bdw-gc` driving the link/include flags,
   vendoring the source under `runtime/vendor/`, or wrapping libgc in
   an Alire external crate. Without a decision, every contributor's
   machine looks slightly different — Apple Silicon's Homebrew
   installs at `/opt/homebrew/`, FreeBSD ports at `/usr/local/`,
   Linux distros at `/usr/`, cross-compile sysroots at arbitrary
   paths. The default `-lgc` path-search succeeds on most Linux
   hosts and Intel macOS Homebrew, fails silently or cryptically
   elsewhere.

2. **What is the explicit exit ramp away from libgc?** ADR-0003's
   "post-1.0 follow-on ADR" wording is intentionally loose and that
   looseness has a cost: any future *let's write our own GC* PR has
   nothing concrete to argue against. Specifying the succession bar
   *now*, while libgc is still un-shipped, is cheap and freezes a
   measurable target.

These are refinements to ADR-0003, not supersessions. ADR-0003's
load-bearing decision (use Boehm; conservative scanning; goroutine-
stack registration; atomic allocation by static-type analysis)
stays. This ADR makes the libgc *integration* and the *exit-ramp
shape* concrete enough to land code against.

The user-facing concern that prompted this ADR was framed as "is
this a Homebrew dependency?" The honest answer is that libgc is a
*system library* on every Unix-like — `apt install libgc-dev`,
`dnf install gc-devel`, `pkg install boehm-gc`, `apk add gc-dev`,
NetBSD pkgsrc `boehm-gc`, etc. Homebrew is just the macOS-dev
path. Capturing that reality in writing is part of this ADR.

## Decision

### libgc resolution: pkg-config

The runtime build resolves libgc via `pkg-config bdw-gc`, with the
following propagation contract:

1. **`pkg-config` is a hard build-host requirement.** It joins
   `gprbuild`, `alr`, `lcov`, `golangci-lint`, and `gnatcheck` (where
   present) on the prerequisite list. Every supported platform ships
   it as a system package; CONTRIBUTING.md documents the install
   alongside the libgc install.

2. **`make bootstrap` verifies `bdw-gc.pc` is discoverable.** A
   missing `bdw-gc.pc` aborts bootstrap with the actionable
   per-platform install hint: `brew install bdw-gc` (macOS),
   `apt install libgc-dev` (Debian/Ubuntu), `dnf install gc-devel`
   (Fedora), `pkg install boehm-gc` (FreeBSD), `apk add gc-dev`
   (Alpine).

3. **`Makefile` exports `GADA_GC_LDFLAGS` and `GADA_GC_CFLAGS` for
   the project file.** Concretely:
   ```make
   GADA_GC_LDFLAGS := $(shell pkg-config --libs bdw-gc)
   GADA_GC_CFLAGS  := $(shell pkg-config --cflags bdw-gc)
   export GADA_GC_LDFLAGS GADA_GC_CFLAGS
   ```

4. **`runtime/gada_core.gpr` consumes those env-vars via `external`,
   with an `-lgc`-only fall-through.** The fall-through covers
   invocations bypassing the Makefile (a contributor running
   `gprbuild` directly, or an IDE driver). It works on Linux/BSD
   where libgc lives in default search paths, and fails clearly on
   Apple Silicon Homebrew (`/opt/homebrew/lib` not in default
   linker paths) — at which point the error message points the
   contributor at `make bootstrap`. We accept this asymmetry:
   "you used the project file directly, you own the consequences"
   is a legitimate footgun, not a silent miscompile.

5. **No vendored libgc source.** The repository does not carry libgc;
   cross-compile targets resolve via the cross-compile toolchain's
   `pkg-config` wrapper.

6. **CI installs via package manager.** `apt install libgc-dev
   pkg-config` on Ubuntu in `.github/workflows/ci.yml`. No vendoring,
   no manual build of libgc on CI runners. The same one-liner works
   on the GitHub-hosted runner and on a local Linux dev box.

### Succession criterion: when (not if) we replace libgc

A future ADR will supersede ADR-0003 with a custom Ada GC
implementation when *all four* of the following are demonstrably true:

1. **Pure Ada.** The replacement ships in pure Ada (no C dependency).
   "Imports a C inline like `setjmp` for register flush" is allowed;
   "links to a maintained C library" is not.
2. **Multi-threaded.** The replacement supports the goroutine-stack
   registration contract from [[0004-scheduler-libco-for-v1]] with at
   least the same correctness guarantees libgc gives us today.
3. **Measurable parity-or-better on the Phase 11 validation suite.**
   Equal-or-better on at least three of:
   - allocations / second (throughput),
   - p99 stop-the-world pause (ms),
   - resident set size at steady state on a 1M-allocation workload,
   - cross-compile target reach (count of GCC-Ada targets where the
     GC builds and the runtime suite passes).
4. **Gated rollout.** The replacement lands behind a build profile
   (e.g., `gada build -gc=ada-native`), with libgc remaining the
   default until the gated profile has been a CI default for one
   full release cycle.

Until *all four* clear, libgc is the runtime GC. PRs proposing a
custom GC without measurements clearing the Phase 11 bar are
rejected as premature optimization. ADR-0003's existing rejection
clause ("PRs that propose to write a custom GC for v1.0 are
rejected unless they supersede this ADR") stays in force; this ADR
adds the bar that the supersession must clear.

The criterion is intentionally numerical, not "when it feels right".
Conservative-scanning false retention and the Boehm allocation-
throughput penalty are real but bounded; replacing them with a
custom GC that is worse on either axis trades pain we already paid
for pain we have not yet paid.

## Consequences

- **What now becomes easier.** One install command per platform; no
  per-developer path hacking. Apple Silicon Homebrew installs work
  without `gada_core.gpr` knowing the path. Cross-compile picks up
  the target sysroot's libgc via the toolchain's `pkg-config`
  wrapper. A future contributor proposing a custom GC has a concrete
  bar to clear, not a moving target. The "is this a Homebrew dep"
  question has a written answer.
- **What now becomes harder.** `pkg-config` joins the mandatory
  build-host tooling list; a host without it cannot build the
  runtime. Two new public env-vars (`GADA_GC_LDFLAGS`,
  `GADA_GC_CFLAGS`) on the Makefile interface; renaming them later
  is a breaking change for anyone scripting against `make`. The
  default `-lgc` fall-through in `gada_core.gpr` produces a binary
  whose link includes paths can differ from `make`'s when invoked
  directly — accepted footgun.
- **What is now off-limits.** Vendoring libgc into the repository
  for v1.0; we rely on the system package, full stop. Hand-rolled
  path detection in `Makefile` that bypasses `pkg-config`; if
  `pkg-config` cannot find libgc, that is a contributor-fixable
  *install* problem, not a Makefile-fallback problem. Adding a
  custom Ada GC to `Gada.Core.Memory` *before* the four succession
  criteria above are met; PRs claiming to do so without the
  measurements are rejected on procedure grounds.

## Alternatives considered

**Bare `pragma Linker_Options ("-lgc")` (no pkg-config)**. Simplest
possible wiring; relies on the linker finding libgc in default
paths. Works on every Linux distro and on Intel macOS Homebrew.
Fails on Apple Silicon Homebrew (`/opt/homebrew` is not a default
linker search path), on cross-compile sysroots, and on any unusual
install. The failure mode is a cryptic `ld` error with no
actionable hint. Rejected because the project explicitly targets
cross-compile reach (AGENTS.md "Cross-compilation reach" pure goal).

**Vendor libgc into `runtime/vendor/bdw-gc/` and build as part of
`make bootstrap`**. Reproducibility win — every dev/CI/cross-compile
box gets bit-identical libgc. Cost: ~30s build added to bootstrap
on every contributor's first checkout, ~3 MB of vendored source,
plus the maintenance overhead of tracking upstream libgc releases.
Rejected because the system package works for every supported host
today and vendoring's wins do not justify the per-contributor cost.
Reconsiderable if a future libgc release breaks the binding.

**Alire external crate `bdw_gc_external`**. Cleanest from Alire's
perspective: declares libgc as a system dependency with platform-
specific install hints, and `alr build` verifies installation.
Cost: ~1 day to author, plus one new crate to maintain; not in the
community index, so we either GADA-vendor or community-publish.
Worth doing if the community index ever gets crowded with `bdw_gc`
candidates and we want to nail down ours. Not needed now.
Reconsiderable post-1.0.

**Alire native crate wrapping libgc source**. Publishing a binary
or build-from-source crate. Several months of packaging work for
marginal benefit over pkg-config. Rejected.

## See also

- [[0003-gc-boehm-for-v1]] — the parent decision. This ADR refines
  but does not supersede it. Its rejection of custom-GC-for-v1.0
  PRs stays in force; this ADR adds the measurable bar that any
  future supersession must clear.
- [[0002-runtime-layered]] — the layering this ADR's wiring respects.
  The libgc binding lives in `Gada.Core.Memory`, behind the layer's
  interface; higher layers never call `GC_malloc` directly.
- [[0004-scheduler-libco-for-v1]] — the scheduler ADR. Goroutine-
  stack registration is unaffected by the dep-resolution choice.
- [[0006-runtime-performance-bar]] — names the 2× perf ceiling and
  the parity-or-better successor criterion. A custom-Ada-GC
  successor that regresses below 2× fails this bar regardless of
  whether it clears the four criteria above.
- [[roadmap/02-core-runtime]] — the active phase that ratifies this
  ADR's pkg-config wiring as the GADA.GC item's implementation.
