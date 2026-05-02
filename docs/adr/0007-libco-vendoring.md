---
type: adr
title: "ADR-0007: libco is vendored in-tree under runtime/src/vendor/libco/, ISC licence preserved, amd64+arm64 hosted only for v1"
status: accepted
created: 2026-05-02
deciders: [gada-core]
tags: [runtime, scheduler, concurrency, libco, vendoring, license]
related:
  - "[[0000-record-architecture-decisions]]"
  - "[[0002-runtime-layered]]"
  - "[[0004-scheduler-libco-for-v1]]"
  - "[[0005-libgc-binding-via-pkgconfig]]"
  - "[[roadmap/03-concurrency]]"
---

# ADR-0007: libco is vendored in-tree under `runtime/src/vendor/libco/`, ISC licence preserved, amd64+arm64 hosted only for v1

## Context

[[0004-scheduler-libco-for-v1]] commits Phase 3 to libco
(byuu/higan-emu's userspace coroutine library) for context
switching on hosted targets. That ADR named the *what* but
deferred the *how*: where does the libco source come from, who
owns updating it, what licence obligations does the project
inherit, and which CPU architectures do we promise to support
on day one.

libco's distribution properties differ from libgc's:
- **No Alire crate** exists for libco. ([[0005-libgc-binding-via-pkgconfig]]
  could fall back to system packaging because every Linux/macOS
  distro ships libgc; libco does not.)
- **No system package** ships it. apt/dnf/brew have no libco
  package — it is too small (a few hundred lines per
  architecture) to justify packaging effort upstream.
- **Single source repo with no point releases.** Upstream is
  `https://github.com/higan-emu/libco`; the project tags rarely
  and consumers pin commit SHAs.
- **ISC licence** (a permissive licence that requires preserving
  the copyright/permission notice). Compatible with the project
  licence (TBD, but no current candidate is ISC-incompatible).

Phase 2 already established the vendor pattern for system
libraries with the libgc binding under
`Gada.Core.Memory.Libgc` — except libgc itself is *not*
vendored, only the bindings are. libco needs the inverse: the
bindings stay tiny, but the source lives in the tree.

We need a decision on: location, pinned version, licence
artefact placement, supported platform matrix, update workflow.

## Decision

We make six concrete choices:

1. **Vendor libco source in-tree under
   `runtime/src/vendor/libco/`.** No git submodule, no fetch at
   build time. The runtime crate is self-contained — `git clone
   gada && cd runtime && alr build` produces a working library
   without network access beyond the Alire toolchain download.

2. **Pin to a specific upstream commit.** The current pin is
   recorded in `runtime/src/vendor/libco/README.md` as a
   `[upstream]` block with the URL, commit SHA, and date. The
   pin is updated in a single commit titled
   `vendor: bump libco to <SHA>` whenever a real upstream change
   we want is identified, never as part of a feature commit.

3. **Reproduce the ISC licence verbatim** at
   `runtime/src/vendor/libco/LICENSE` and reference it from
   `runtime/src/vendor/libco/README.md`. The project's top-level
   `LICENSE` (when set, see [[roadmap/00-foundation]]) gains a
   "Third-party notices" section that points at the vendored
   copy.

4. **Supported platform matrix for v1: amd64 + arm64 hosted only.**
   Specifically: x86_64 Linux/macOS and aarch64 Linux/macOS.
   Other libco-supported architectures (PowerPC, x86 32-bit,
   ARM 32-bit, RISC-V) are not part of the v1 contract, even
   though the upstream sources are vendored. This matches the
   set of platforms the rest of the project (Go toolchain, CI
   runners) actively tests.

5. **Per-architecture source selection happens in the GPR**
   (sub-item (c) of the parent roadmap item), not via libco's
   own `#ifdef` cascade in `libco.c`. Compiling exactly one of
   `amd64.c` or `arm64.c` per build avoids the
   "wrong-architecture symbols leak into the static archive"
   class of bug. Detection driver: `external ("ARCH",
   $(uname -m))`-equivalent in the gpr scenario.

6. **The thin C wrapper named in the parent's roadmap line
   (`gada-async-context-thin.c`) is a no-op pass-through for v1.**
   We initially considered translating libco's `cothread_t`
   typedef into a stable Ada-friendly opaque pointer via a
   wrapper, but `cothread_t` is already `void*` in libco, so the
   indirection adds no value. The Ada-side `Gada.Async.Context`
   spec exposes a `Context` type backed by `System.Address`
   directly. The wrapper file remains in the file list as a
   placeholder for future per-arch shims (e.g., a fast-path
   inlined switch on amd64) and for any cross-cutting C-level
   instrumentation (TSan annotations, etc.). For v1 it contains
   a single comment explaining this.

## Consequences

- **What now becomes easier.**
  - Reproducible builds: the runtime crate has no
    network-fetched dependencies past the Alire toolchain. CI
    cache invalidation events do not surface as build
    failures.
  - Auditing: the exact libco source on disk *is* the source
    being shipped. No `go.sum`-equivalent to drift, no proxy to
    cache-poison, no submodule to forget to fetch.
  - Patching: if upstream regresses (or a security finding
    arrives) we can hold a fix in-tree until upstream catches
    up. The `vendor: bump libco` commit pattern makes the diff
    against upstream auditable.

- **What now becomes harder.**
  - Updating libco is a manual process: copy files, refresh
    LICENSE if the upstream version changed (it shouldn't —
    libco's licence is stable), update the README pin block,
    rebuild + run the AUnit suite, commit. No `dependabot`
    automation for it.
  - We carry an extra ~25 KB of C source in our repo. Acceptable
    given the alternative.
  - We cannot benefit from a system-package security update
    landing automatically. Mitigation: the vendoring ADR's
    "subscribe to upstream" line is a real subscription a
    maintainer holds.

- **What is now off-limits.**
  - **No system-package fallback for libco.** A PR proposing
    "use the apt-installed libco when present" is rejected: the
    package does not exist, and the bring-up cost of supporting
    both vendored and system in parallel is not paid for by any
    user benefit. If this changes (someone packages libco for
    Debian), this ADR can be superseded.
  - **No git-submodule pattern for libco.** The cost in
    contributor friction (`git clone --recurse-submodules`,
    fork visibility issues, CI submodule cache) is not paid
    for at this scale.
  - **No platforms beyond amd64 + arm64 in the v1 contract.**
    Phase 11 (real-world validation & 1.0) may widen this; until
    then a PR adding e.g., riscv64 is treated as out-of-scope
    for the milestone, not refused on principle but not allowed
    to gate any roadmap item.

## Alternatives considered

**System-package install (apt/brew/dnf).** The pattern used for
libgc per [[0005-libgc-binding-via-pkgconfig]]. Rejected because
no distribution packages libco. The cost of authoring + getting
upstream into Debian/Fedora/Homebrew is far larger than vendoring
a few hundred lines of C in-tree.

**Git submodule pointing at upstream.** Standard pattern for
in-source dependencies. Rejected because it adds a
network-fetch step at clone time (`git clone
--recurse-submodules`) that catches every contributor at least
once, and the contents we need (`libco.c`, two `.c` per arch,
one `.h`) are small enough that the in-tree copy costs less than
the submodule machinery.

**Single libco.c with `#ifdef` arch dispatch (libco's
default).** What upstream's `libco.c` does. Rejected because we
prefer the per-arch-source-file selection to live at the build-
system level, where `gprbuild`'s scenario-variable pattern is
already idiomatic. The build system is the right layer to know
which arch we're targeting; pushing that into preprocessor logic
just means `gprbuild`-driver flags have to be re-translated into
`-D` flags later.

**Custom Ada implementation of context switching.** Considered
in [[0004-scheduler-libco-for-v1]] and rejected there. Not
revisited: that ADR's reasoning still holds.

## ISC licence text (as vendored)

The exact text reproduced under
`runtime/src/vendor/libco/LICENSE` is:

```
ISC License

Copyright (c) 2006-2024 byuu et al.

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

The copyright year is updated mechanically to track the
upstream `LICENSE` file at each `vendor: bump libco` commit;
the rest of the text is invariant under the ISC licence.
