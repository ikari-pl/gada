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

- [ ] **GADA.Core.Memory — libgc-backed allocator**
      *Files:* (see sub-items below)
      *Verify:* `make -C runtime test PKG=core.memory`
      *Done when:* allocations through `Gada.Core.Memory.Allocate` are reclaimed under stress (1M allocs, RSS bounded), tests pass.
      *Notes:* libgc resolved via pkg-config per [[0005-libgc-binding-via-pkgconfig]]; thin C bindings live in `Gada.Core.Memory.Libgc` (private child of `Gada.Core.Memory`, non-`with`-able from outside the parent) and are not exposed to higher layers — those use `Gada.Core.Memory` per [[0003-gc-boehm-for-v1]] §2 and [[0002-runtime-layered]]. Decomposed into the five sub-items below; the parent ticks when all sub-items tick AND the parent *Verify* passes from a clean build.

  - [ ] **(a) bdw-gc system-library bootstrap check**
        *Files:* `Makefile`, `.github/workflows/ci.yml`
        *Verify:* without libgc installed, `make bootstrap` exits non-zero and prints the actionable per-platform install hint; with libgc installed, exit 0. CI workflow `apt install`s `libgc-dev pkg-config` before `make ci`.
        *Done when:* missing libgc surfaces as a first-class bootstrap error, not a cryptic linker failure later.

  - [ ] **(b) Gada.Core.Memory.Libgc — thin C bindings**
        *Files:* `runtime/src/gada-core-memory-libgc.ads`, `runtime/src/gada-core-memory-libgc.adb`
        *Verify:* `cd runtime && alr build` exits 0 once linker plumbing (sub-item d) lands; `nm runtime/lib/libgada_core.a | grep ' U _GC_'` shows libgc symbols are imported, not defined.
        *Done when:* `GC_init`, `GC_malloc`, `GC_malloc_atomic`, `GC_gcollect`, `GC_get_heap_size` are imported via `pragma Import (C, …)` from a private-child package.

  - [ ] **(c) Gada.Core.Memory — public allocator interface**
        *Files:* `runtime/src/gada-core-memory.ads`, `runtime/src/gada-core-memory.adb`
        *Verify:* `cd runtime && alr build` exits 0 with the public spec compiled; `grep -rn 'Core\.Memory\.Libgc' runtime/src | grep -v 'gada-core-memory'` is empty.
        *Done when:* `Initialize`, `Allocate`, `Allocate_Atomic`, `Collect`, `Heap_Size` are exposed; body delegates to `Libgc` per [[0002-runtime-layered]].

  - [ ] **(d) gada_core.gpr + runtime/Makefile pkg-config plumbing**
        *Files:* `runtime/gada_core.gpr`, `runtime/Makefile`, `runtime/tests/aunit_harness.gpr`
        *Verify:* `make -C runtime test` builds against libgc on a host with `bdw-gc.pc`; `otool -L` (macOS) or `ldd` (Linux) of the test_runner lists libgc.
        *Done when:* `GADA_GC_LDFLAGS` / `GADA_GC_CFLAGS` exported by `runtime/Makefile`; consumed by `gada_core.gpr` via `external (...)` with `-lgc` fall-through.

  - [ ] **(e) AUnit suite test_memory + test_runner registration**
        *Files:* `runtime/tests/test_memory.adb`, `runtime/tests/memory_suite.{ads,adb}`, `runtime/tests/test_runner.adb`
        *Verify:* `make -C runtime test PKG=core.memory` exits 0 with the memory suite registered; an unknown PKG (`bogus.suite`) still exits non-zero per the existing typo-guard.
        *Done when:* a 1M-allocation stress (allocate → drop reference → force `Collect`) keeps RSS bounded; `Heap_Size` after collect is ≤ pre-stress peak.

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
