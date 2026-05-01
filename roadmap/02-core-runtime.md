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
      *Files:* `runtime/src/gada-core-memory.ads`, `runtime/src/gada-core-memory.adb`, `runtime/src/gada-gc.ads`, `runtime/src/gada-gc.adb` (thin C bindings to bdw-gc), `runtime/tests/test_memory.adb`, `runtime/Makefile` (pkg-config plumbing), `runtime/gada_core.gpr` (external linker switches)
      *Verify:* `make -C runtime test PKG=core.memory`
      *Done when:* allocations through `Gada.Core.Memory.Allocate` are reclaimed under stress (1M allocs, RSS bounded), tests pass.
      *Notes:* libgc resolved via pkg-config per [[0005-libgc-binding-via-pkgconfig]]; thin C bindings live in `Gada.GC` (internal sibling of `Gada.Core.Memory`) and are not exposed to higher layers — those use `Gada.Core.Memory` per [[0003-gc-boehm-for-v1]] §2 and [[0002-runtime-layered]].

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
