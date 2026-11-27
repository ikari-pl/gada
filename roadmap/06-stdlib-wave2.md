# Phase 6 — Stdlib wave 2: system wrappers

[← Phase 5](05-stdlib-wave1.md) · [Index](README.md) · Next: [Phase 7 →](07-stdlib-wave3-network.md)

**Status:** `DONE` (completed 2026-11-26; CI green on b1b24f1 — 260 AUnit tests, runtime 100%, all 6 examples incl. timer_pool)
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

- [x] **Stdlib package: `time`**
      *Files:* `runtime/src/gada-std-time.{ads,adb}`, `runtime/tests/stdlib/time_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=time`
      *Done when:* `Now`, `Since`, `After`, `Tick`, `NewTimer`, `Duration` arithmetic all correct; calendar conversions UTC + Local correct; coverage ≥ 95%.
      *Done 2026-11-26:* landed as `Gada.Std.Time`. Duration is a derived
      Long_Integer (ns) with Go unit constants; `*`/`/`/unary `-` come from
      the inherited predefined operators (mixed Long_Integer profiles
      would be ambiguous). To_String is pinned to Go 1.22 output. Time
      carries Mono (Real_Time) + Wall (Calendar) + Ns + a UTC display
      flag; Since/Until_K measure monotonic elapsed (To_Duration on the
      124-year span since Time_First would overflow Duration's range, so
      Now takes the sub-second part from the wall clock). Timers are Ada
      tasks sleeping in <=50ms slices so Stop is noticed promptly (a
      never-stopped Repeater would block its master); Stop_Channel is a
      v1 extension for After/Tick's bare channels. Suite `stdlib.time`
      (8 tests, delay-polled since Yield is a no-op in the main task) all
      green; runtime coverage stays 100% (4 lcov-terminator excludes).
      Compiler: "time" joined StdlibPackages.

- [x] **Stdlib package: `os`**
      *Files:* `runtime/src/gada-std-os.{ads,adb}`, `runtime/tests/stdlib/os_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=os`
      *Done when:* `Args`, `Getenv`, `Setenv`, `Open`, `Create`, `Stat`, `Mkdir` correct; coverage ≥ 90%.
      *Done 2026-11-26:* wave 2 landed in `Gada.Std.OS` (Read_File was
      wave 1). Args over Ada.Command_Line (Args(1) = program name);
      Lookup_Env/Get_Env/Set_Env over Ada.Environment_Variables with
      Go's invalid-key rejection (empty or containing '='). File is a
      limited record wrapping Stream_IO.File_Type behind a heap access
      (Go's *os.File); Open/Create return (handle, Err) out-params,
      Write raises Use_Error on a closed handle, Close nulls it. Stat
      reports size/dir via Ada.Directories; Mkdir errors on existing.
      Suite `stdlib.os` (10 tests) all green (257 total); runtime
      coverage stays 100% (10 documented excludes: untriggerable
      read-error arm, lcov terminators, argv loop body).

- [x] **Stdlib package: `runtime`** (introspection on GADA scheduler)
      *Files:* `runtime/src/gada-std-runtime.{ads,adb}`, `runtime/tests/stdlib/runtime_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=runtime`
      *Done when:* `NumGoroutine`, `GOMAXPROCS`, `GC`, `Gosched` map to GADA scheduler operations; coverage 100%.
      *Done 2026-11-26:* landed as `Gada.Std.Runtime`. The scheduler
      gained read-only Live_Goroutines/Live_Workers counters on the run
      queue; Num_Goroutine = live + 1 (Go counts the main goroutine).
      GOMAXPROCS resizes only from a non-goroutine context (Shutdown
      joins in-flight goroutines — a resize from inside one would
      self-deadlock), returning the previous count. Gosched is Yield,
      GC is a full Boehm collect (Gada.Core.Memory.Collect). Suite
      `stdlib.runtime` (3 tests, goroutine-driven) green, 260 total;
      runtime coverage stays 100% (1 terminator exclude; 2 scheduler
      excludes re-mapped after the line shift).
      Compiler: "runtime" joined StdlibPackages.

- [x] **`timer_pool` example**
      *Files:* `examples/timer_pool/main.go`, `examples/timer_pool/expected_output.txt`
      *Verify:* `make example HELLO=timer_pool`
      *Done when:* a worker pool processes jobs with timeouts and reports goroutine count; output matches expected.
      *Done 2026-11-26:* `examples/timer_pool` runs a 2-worker pool over
      a jobs channel with a time.After deadline, a sync.Mutex-guarded
      counter, len(os.Args), and runtime.NumGoroutine; expected_output
      pinned via `go run` (jobs: 4 / sum: 12 / goroutines: 3 /
      argc: 1). Needed four small emitter lowerings, each with a unit
      test: `var x T` DeclStmt -> bare decl via new ir.ZeroVal;
      qualified types (sync.Mutex) -> NamedType; `chan time.Time` rides
      Gada.Std.Time.Time_Channels (no per-file instantiation); sync
      method calls -> protected dot-calls (Mu.Lock;); len(os.Args) ->
      String_Vectors.Length (Gada.Std.OS.Args), with an auto
      `with Gada.Std.Strings;`. OS.Args now returns String_Slice.
      CI: new `make example HELLO=timer_pool` step in the examples job.

## Post-review fixes (PR #46)

Independent review of the phase PR found 17 issues; each fix carries a
regression test and is listed here so the item notes above stay the
historical record.

- **Program exit = Go main-return** (findings #1, #4; behaviour change,
  [ADR-0011](../docs/adr/0011-go-main-return-exit.md)). A generated main
  that owns runtime tasks (goroutine pool or the time service) ends via
  `Gada.Core.Process.Exit_Main` (flush + `OS_Exit (0)`) right after its
  body and defers; goroutines are **no longer joined** at exit and
  `Scheduler.Shutdown` / `Time.Stop_All` are no longer emitted. An
  escaping panic or runtime error prints GNAT's `raised NAME : msg` line
  and exits 2 (Go's status) instead of hanging on live tasks.
  *Verify:* `cd compiler && go test ./internal/emit -run 'TimeOnlyMain|ProcessExit|PlainMain'`
  and `make -C runtime test PKG=core.process`.

- **Goroutine-aware sync** (findings #3, #7). Mutex/RWMutex/WaitGroup/
  Once are tagged limited records over a protected core with a waiter
  list: a goroutine that must wait registers and `Scheduler.Park`s
  (its worker keeps running other goroutines) and the releasing call
  `Unpark`s it; only non-goroutine callers block on protected entries.
  Once is an Idle/Running/Done state machine — f runs outside any
  protected action, Done is set even if f raises, concurrent callers
  wait until f returns. TryLock/TryRLock are Boolean functions; Do_K
  takes an anonymous access-to-procedure.
  *Verify:* `make stdlib-test PKG=sync` (5 single-worker regressions).
