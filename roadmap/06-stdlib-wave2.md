# Phase 6 — Stdlib wave 2: system wrappers

[← Phase 5](05-stdlib-wave1.md) · [Index](README.md) · Next: [Phase 7 →](07-stdlib-wave3-network.md)

**Status:** `NOT_STARTED`
**Prerequisites:** [Phase 3](03-concurrency.md) `DONE`, [Phase 5](05-stdlib-wave1.md) `DONE`
**Goal:** Port packages that wrap host services: `sync`, `time`, `os`,
`runtime`. These bridge to Ada equivalents (protected objects,
`Ada.Calendar`, `GNAT.OS_Lib`).
**Exit criterion:** transpile and run `examples/timer_pool` exercising
mutexes, `time.After`, `os.Args`, and `runtime.NumGoroutine`.

## Items

- [ ] **Stdlib package: `sync`**
      *Files:* `stdlib/sync/`
      *Verify:* `make stdlib-test PKG=sync`
      *Done when:* `Mutex`, `RWMutex`, `WaitGroup`, `Once`, `Cond` all correct on top of Ada protected objects; coverage 100%.

- [ ] **Stdlib package: `time`**
      *Files:* `stdlib/time/`
      *Verify:* `make stdlib-test PKG=time`
      *Done when:* `Now`, `Since`, `After`, `Tick`, `NewTimer`, `Duration` arithmetic all correct; calendar conversions UTC + Local correct; coverage ≥ 95%.

- [ ] **Stdlib package: `os`**
      *Files:* `stdlib/os/`
      *Verify:* `make stdlib-test PKG=os`
      *Done when:* `Args`, `Getenv`, `Setenv`, `Open`, `Create`, `Stat`, `Mkdir` correct; coverage ≥ 90%.

- [ ] **Stdlib package: `runtime`** (introspection on GADA scheduler)
      *Files:* `stdlib/runtime/`
      *Verify:* `make stdlib-test PKG=runtime`
      *Done when:* `NumGoroutine`, `GOMAXPROCS`, `GC`, `Gosched` map to GADA scheduler operations; coverage 100%.

- [ ] **`timer_pool` example**
      *Files:* `examples/timer_pool/main.go`
      *Verify:* `make example HELLO=timer_pool`
      *Done when:* a worker pool processes jobs with timeouts and reports goroutine count; output matches expected.
