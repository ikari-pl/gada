# Phase 3 — Concurrency runtime: goroutines, channels, select

[← Phase 2](02-core-runtime.md) · [Index](README.md) · Next: [Phase 4 →](04-interfaces-reflection.md)

**Status:** `NOT_STARTED`
**Prerequisites:** [Phase 2](02-core-runtime.md) `DONE`
**Goal:** Implement `GADA.Async` — M:N goroutine scheduler, bounded and
unbounded channels, Go's `select` statement — with full coverage. After
this phase, Go programs using `go`, channels, and `select` compile and
run with semantics matching the Go reference.
**Exit criterion:** `make example HELLO=ping_pong` runs a 2-goroutine
ping-pong over a channel for 1 million iterations and exits cleanly.

## Items

- [ ] **ADR — scheduler design (libco vs CPS)**
      *Files:* `docs/adr/0010-scheduler-libco.md`
      *Verify:* ADR is `accepted` with consequences enumerated.
      *Done when:* design choice is recorded with the alternatives explicitly considered.

- [ ] **GADA.Async.Context — userland context switching via libco**
      *Files:* `runtime/src/gada-async-context.ads`, `runtime/src/gada-async-context.adb`, `runtime/src/gada-async-context-thin.c`, `runtime/tests/test_context.adb`
      *Verify:* `make -C runtime test PKG=async.context`
      *Done when:* `Switch_To (Other)` round-trips between two contexts 1M times; coverage 100%.

- [ ] **GADA.Async.Scheduler — M:N over a fixed pool of Ada tasks**
      *Files:* `runtime/src/gada-async-scheduler.ads`, `runtime/src/gada-async-scheduler.adb`, `runtime/tests/test_scheduler.adb`
      *Verify:* `make -C runtime test PKG=async.scheduler`
      *Done when:* `Spawn (Body)` schedules a goroutine; `GOMAXPROCS`-equivalent fairness, work-stealing, blocking-syscall hand-off; coverage 100%.

- [ ] **GADA.Async.Channels.Bounded — bounded channels**
      *Files:* `runtime/src/gada-async-channels-bounded.ads`, `runtime/src/gada-async-channels-bounded.adb`, `runtime/tests/test_channels_bounded.adb`
      *Verify:* `make -C runtime test PKG=async.channels.bounded`
      *Done when:* send/receive block correctly, close semantics match Go (panic on send-after-close, zero-value on receive-after-close), coverage 100%.

- [ ] **GADA.Async.Channels.Unbounded — unbounded channels**
      *Files:* `runtime/src/gada-async-channels-unbounded.ads`, `runtime/src/gada-async-channels-unbounded.adb`, `runtime/tests/test_channels_unbounded.adb`
      *Verify:* `make -C runtime test PKG=async.channels.unbounded`
      *Done when:* send never blocks, receive blocks when empty, close semantics correct, coverage 100%.

- [ ] **GADA.Async.Select — Go select statement runtime**
      *Files:* `runtime/src/gada-async-select.ads`, `runtime/src/gada-async-select.adb`, `runtime/tests/test_select.adb`
      *Verify:* `make -C runtime test PKG=async.select`
      *Done when:* select with N cases (send/recv/default/timeout) picks a ready case fairly; pseudo-random tie-breaking matches Go's behavior; coverage 100%.

- [ ] **Compiler emission — `go` statement**
      *Files:* `compiler/internal/emit/goroutine.go`, golden tests
      *Verify:* `cd compiler && go test ./internal/emit/... -run Goroutine`
      *Done when:* `go f(x, y)` emits `Gada.Async.Scheduler.Spawn (...)` correctly capturing locals.

- [ ] **Compiler emission — channel operations**
      *Files:* `compiler/internal/emit/channel.go`, golden tests
      *Verify:* `cd compiler && go test ./internal/emit/... -run Channel`
      *Done when:* `make(chan T, N)`, `c <- v`, `<-c`, `close(c)` all emit correctly.

- [ ] **Compiler emission — select statement**
      *Files:* `compiler/internal/emit/select.go`, golden tests
      *Verify:* `cd compiler && go test ./internal/emit/... -run Select`
      *Done when:* multi-case select with default emits correct `Gada.Async.Select` invocation.

- [ ] **`ping_pong` example**
      *Files:* `examples/ping_pong/ping_pong.go`, `examples/ping_pong/expected_output.txt`
      *Verify:* `make example HELLO=ping_pong` (must complete in < 5s wall-clock)
      *Done when:* 1M-iteration ping-pong completes with no deadlock and correct iteration count.

- [ ] **Race detector integration (best-effort)**
      *Files:* `runtime/src/gada-async-race.ads`
      *Verify:* `make -C runtime test PKG=async.race`
      *Done when:* an intentional data race is detected and reported (or documented as a known limitation in an ADR).

- [ ] **Goroutine leak test**
      *Files:* `runtime/tests/stress_goroutines.adb`
      *Verify:* `make -C runtime test PKG=stress.goroutines`
      *Done when:* spawning + completing 100k goroutines leaves runtime task count back at baseline.
