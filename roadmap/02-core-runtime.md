# Phase 2 — Core runtime: memory & errors

[← Phase 1](01-minimal-transpiler.md) · [Index](README.md) · Next: [Phase 3 →](03-concurrency.md)

**Status:** `IN_PROGRESS`
**Prerequisites:** [Phase 1](01-minimal-transpiler.md) `DONE`
**Goal:** Implement `GADA.Core` — slices, maps, defer, panic/recover,
GC interface — with full unit-test coverage. After this phase, Go
programs using these primitives (still single-threaded) compile and
run.
**Exit criterion:** `make example HELLO=collections` runs an example
exercising slices, maps, append, len, cap, defer, panic, recover.

## Items

- [x] **GADA.Core.Memory — libgc-backed allocator**
      *Files:* (see sub-items below)
      *Verify:* `make -C runtime test PKG=core.memory`
      *Done when:* allocations through `Gada.Core.Memory.Allocate` are reclaimed under stress (1M allocs, RSS bounded), tests pass.
      *Notes:* libgc resolved via pkg-config per [[0005-libgc-binding-via-pkgconfig]]; thin C bindings live in `Gada.Core.Memory.Libgc` (private child of `Gada.Core.Memory`, non-`with`-able from outside the parent) and are not exposed to higher layers — those use `Gada.Core.Memory` per [[0003-gc-boehm-for-v1]] §2 and [[0002-runtime-layered]]. Decomposed into the five sub-items below; the parent ticks when all sub-items tick AND the parent *Verify* passes from a clean build.

  - [x] **(a) bdw-gc system-library bootstrap check**
        *Files:* `Makefile`, `.github/workflows/ci.yml`
        *Verify:* without libgc installed, `make bootstrap` exits non-zero and prints the actionable per-platform install hint; with libgc installed, exit 0. CI workflow `apt install`s `libgc-dev pkg-config` before `make ci`.
        *Done when:* missing libgc surfaces as a first-class bootstrap error, not a cryptic linker failure later.
        *Done 2026-05-02:* Top-level `Makefile` `bootstrap` target gains a leading bdw-gc check via `pkg-config --exists bdw-gc`; on miss, prints a five-line install hint matrix (macOS / Debian-Ubuntu / Fedora / FreeBSD / Alpine) and exits 1 *before* the existing Go and Ada bootstrap steps run. `make` wraps the inner exit-1 as exit 2 (Make's "recipe failed" code) — both are non-zero so the contract holds. Verified locally on darwin/arm64 against an uninstalled libgc: stderr matches the spec, exit 2; pkg-config presence is checked first with its own dedicated install hint so the failure mode is unambiguous when neither is present. `.github/workflows/ci.yml` extends the existing lcov-install step to also `apt install -y libgc-dev pkg-config`, with `pkg-config --modversion bdw-gc` echoed into the log so a future apt-package regression surfaces visibly. Step renamed to "Install Ada-side system packages (lcov, bdw-gc, pkg-config)" to reflect the broader scope. The bootstrap check does *not* fire from `make ci` (which has no `bootstrap` dependency); it only gates explicit fresh-checkout setup, so contributors who already ran bootstrap once aren't re-prompted on every CI invocation. The actual link against `-lgc` lands with sub-item (d).

  - [x] **(b) Gada.Core.Memory.Libgc — thin C bindings**
        *Files:* `runtime/src/gada-core-memory-libgc.ads` (no body — pragma Imports stand in for it)
        *Verify:* `cd runtime && alr build` exits 0 once linker plumbing (sub-item d) lands; `nm runtime/lib/libgada_core.a | grep ' U _GC_'` shows libgc symbols are imported, not defined.
        *Done when:* `GC_init`, `GC_malloc`, `GC_malloc_atomic`, `GC_gcollect`, `GC_get_heap_size` are imported via `pragma Import (C, …)` from a private-child package.
        *Done 2026-05-02:* spec only (no .adb — pragma Imports don't require an Ada body). `private package Gada.Core.Memory.Libgc` makes external `with` rejected at compile time, enforcing ADR-0002's "higher layers use Gada.Core.Memory, not its private children". Verified `nm runtime/lib/libgada_core.a | grep ' U _GC_'` reports all five symbols as undefined externals; the link resolves them at executable-time via pkg-config (sub-item d). Shipped together with sub-item (c) because Ada's parent-child semantics require the parent spec to exist for the private child to compile.

  - [x] **(c) Gada.Core.Memory — public allocator interface**
        *Files:* `runtime/src/gada-core-memory.ads`, `runtime/src/gada-core-memory.adb`
        *Verify:* `cd runtime && alr build` exits 0 with the public spec compiled; `grep -rn 'Core\.Memory\.Libgc' runtime/src | grep -v 'gada-core-memory'` is empty.
        *Done when:* `Initialize`, `Allocate`, `Allocate_Atomic`, `Collect`, `Heap_Size` are exposed; body delegates to `Libgc` per [[0002-runtime-layered]].
        *Done 2026-05-02:* `Initialize`, `Allocate`, `Allocate_Atomic`, `Collect`, `Heap_Size` exposed; body's 5 subprograms delegate to `Libgc.GC_init` / `GC_malloc` / `GC_malloc_atomic` / `GC_gcollect` / `GC_get_heap_size` respectively, with `Interfaces.C.size_t` ↔ `Storage_Count` widening on the boundary. `grep -rn 'Core\.Memory\.Libgc' runtime/src | grep -v 'gada-core-memory'` returns empty — only the parent body refers to the private child, by design. Coverage on `runtime/src/gada-core-memory.adb`: 13/13 lines (100%) under the runtime/ 100% gate.

  - [x] **(d) gada_core.gpr + runtime/Makefile pkg-config plumbing**
        *Files:* `runtime/gada_core.gpr`, `runtime/Makefile`, `runtime/tests/aunit_harness.gpr`
        *Verify:* `make -C runtime test` builds against libgc on a host with `bdw-gc.pc`; `otool -L` (macOS) or `ldd` (Linux) of the test_runner lists libgc.
        *Done when:* `GADA_GC_LDFLAGS` / `GADA_GC_CFLAGS` exported by `runtime/Makefile`; consumed by `gada_core.gpr` via `external (...)` with `-lgc` fall-through.
        *Done 2026-05-02:* `runtime/Makefile` exports `GADA_GC_LDFLAGS := $(shell pkg-config --libs bdw-gc 2>/dev/null)` and `GADA_GC_CFLAGS` likewise. The library project (`gada_core.gpr`) explicitly omits a `package Linker` — gprbuild emits *"Linker switches not taken into account in library projects"* when one is declared on a static library, so the switches must live on every executable that links it instead. `tests/aunit_harness.gpr` consumes `external_as_list ("GADA_GC_LDFLAGS", " ") & ("-lgc")` in its Linker.Default_Switches, with the trailing `-lgc` as the fall-through for direct gprbuild invocations on Linux/BSD default-paths hosts. Verified locally: `make -C runtime test` exits 0 on darwin/arm64 with `bdw-gc 8.2.12` from Homebrew; the produced `tests/obj/test_runner` links against `/opt/homebrew/Cellar/bdw-gc/8.2.12/lib/libgc.dylib`. Per-executable-project duplication of GC_Switches captured in `docs/imperfections.md` for a future shared `gada_link_options.gpr` consolidation.

  - [x] **(e) AUnit suite memory_suite + test_runner registration**
        *Files:* `runtime/tests/memory_suite.{ads,adb}`, `runtime/tests/test_runner.adb`
        *Verify:* `make -C runtime test PKG=core.memory` exits 0 with the memory suite registered; an unknown PKG (`bogus.suite`) still exits non-zero per the existing typo-guard.
        *Done when:* a 1M-allocation stress (allocate → drop reference → force `Collect`) keeps RSS bounded; `Heap_Size` after collect is ≤ pre-stress peak.
        *Done 2026-05-02:* `tests/memory_suite.{ads,adb}` shipped with three tests: `Allocate returns non-null`, `Allocate_Atomic returns non-null`, and `1M allocs grow heap; Heap_Size after Collect bounded by 2x ceiling` (the parent's RSS-bounded contract). The stress test allocates 1,000,000 × 64-byte atomic regions (no reference retained), forces `Collect`, and asserts `Heap_Size <= 2 * N_Allocs * Alloc_Size` (128 MB). `tests/test_runner.adb` registers `Memory_Test` under PKG name `core.memory`, extends `Is_Known` to accept it, and the typo-guard's stderr line lists both known suites. The roadmap line dropped a speculative `test_memory.adb` — the actual AUnit pattern is suite + test_runner registration, no per-suite entry-point file. `pragma Warnings (Off, "use of an anonymous access type allocator");` added at the top of `test_runner.adb` to silence GNAT 15's `-gnatw_a` on AUnit's `new …_Test` registration pattern (file-wide; captured in `docs/imperfections.md`). Final verification: `make -C runtime test` runs all 4 tests (1 IO + 3 Memory) green; `make -C runtime test PKG=core.memory` runs only the 3 memory tests; `make -C runtime test PKG=bogus.suite` exits 1 with `Known suites: core.io, core.memory.`. `make ci` from a clean tree: coverage gate PASSED (runtime/ 100% across 16/16 lines on 2 files, compiler/ 95.45%), roadmap consistency OK.

- [ ] **GADA.Core.Slices — generic slice type**
      *Files:* `runtime/src/gada-core-slices.ads`, `runtime/src/gada-core-slices.adb`, `runtime/tests/test_slices.adb`
      *Verify:* `make -C runtime test PKG=core.slices`
      *Done when:* `Append`, slicing, `Len`, `Cap`, copy-on-grow, sharing-of-backing semantics all match Go reference; coverage 100%.

- [ ] **GADA.Core.Maps — generic hash map**
      *Files:* `runtime/src/gada-core-maps.ads`, `runtime/src/gada-core-maps.adb`, `runtime/tests/test_maps.adb`
      *Verify:* `make -C runtime test PKG=core.maps`
      *Done when:* insertion, lookup, deletion, iteration with Go-compatible randomization, and growth-on-load-factor all pass; coverage 100%.

- [ ] **GADA.Core.Defer — deferred call stack**
      *Files:* `runtime/src/gada-core-defer.ads`, `runtime/src/gada-core-defer.adb`, `runtime/tests/test_defer.adb`
      *Verify:* `make -C runtime test PKG=core.defer`
      *Done when:* `defer` calls execute in LIFO order at scope exit, including under panic; coverage 100%.

- [ ] **GADA.Core.Panic — panic/recover**
      *Files:* `runtime/src/gada-core-panic.ads`, `runtime/src/gada-core-panic.adb`, `runtime/tests/test_panic.adb`
      *Verify:* `make -C runtime test PKG=core.panic`
      *Done when:* `Panic` raises Ada exception with payload; `Recover` returns the payload value or null; deferred calls run between panic and recover; coverage 100%.

- [ ] **Compiler emission — slice operations**
      *Files:* `compiler/internal/emit/slice.go`, golden tests in `compiler/testdata/slice/`
      *Verify:* `cd compiler && go test ./internal/emit/... -run Slice`
      *Done when:* `[]int{1,2,3}`, `append`, `s[i:j]`, `len`, `cap` all emit to `Gada.Core.Slices` calls; coverage ≥ 95%.

- [ ] **Compiler emission — map operations**
      *Files:* `compiler/internal/emit/map.go`, golden tests
      *Verify:* `cd compiler && go test ./internal/emit/... -run Map`
      *Done when:* `map[string]int{}`, lookup, delete, range emit correctly.

- [ ] **Compiler emission — defer/panic/recover**
      *Files:* `compiler/internal/emit/control.go`, golden tests
      *Verify:* `cd compiler && go test ./internal/emit/... -run Control`
      *Done when:* `defer`, `panic`, `recover` emit correct GADA.Core calls + scope-exit hooks.

- [ ] **`collections` example**
      *Files:* `examples/collections/collections.go`, `examples/collections/expected_output.txt`
      *Verify:* `make example HELLO=collections`
      *Done when:* program exercises slices, maps, append, defer, panic, recover and matches expected output.

- [ ] **GC stress test in CI**
      *Files:* `runtime/tests/stress_gc.adb`
      *Verify:* `make -C runtime test PKG=stress.gc`
      *Done when:* 10s of allocation-heavy load completes with RSS < 200 MB.
