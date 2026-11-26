# Phase 6 — Stdlib wave 2: system wrappers

[← Phase 5](05-stdlib-wave1.md) · [Index](README.md) · Next: [Phase 7 →](07-stdlib-wave3-network.md)

**Status:** `IN_PROGRESS` (opened 2026-11-26)
**Prerequisites:** [Phase 3](03-concurrency.md) `DONE`, [Phase 5](05-stdlib-wave1.md) `DONE`
**Goal:** Port packages that wrap host services: `sync`, `time`, `os`,
`runtime`. These bridge to Ada equivalents (protected objects,
`Ada.Calendar`, `GNAT.OS_Lib`).
**Exit criterion:** transpile and run `examples/timer_pool` exercising
mutexes, `time.After`, `os.Args`, and `runtime.NumGoroutine`.

## Items

- [x] **Stdlib package: `sync`**
      *Files:* `runtime/src/gada-std-sync.{ads,adb}`, `runtime/tests/stdlib/sync_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=sync`
      *Done when:* `Mutex`, `RWMutex`, `WaitGroup`, `Once`, `Cond` all correct on top of Ada protected objects; coverage 100%.
      *Done 2026-11-26:* landed as `Gada.Std.Sync`. Mutex/RWMutex are
      protected types (entries with barriers for blocking Lock/RLock,
      procedures for Unlock/TryLock); misuse raises Constraint_Error
      where Go panics (unlock-of-unlocked, RUnlock with no readers,
      WaitGroup underflow). WaitGroup.Wait is an entry barrier on the
      counter; Once.Do_K runs f exactly once and marks done even when f
      raises (Go's defer). Cond is a Mutex_Access + unbounded channel +
      protected waiter counter, so Signal never leaves a stale token and
      Wait releases/reacquires L. Suite `stdlib.sync` (7 tests,
      goroutine-driven) all green; runtime coverage stays 100%.
      Compiler: "sync" joined StdlibPackages (Once.Do maps to Do_K —
      "do" is reserved, same _K rule as New_K/Is_K).

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
