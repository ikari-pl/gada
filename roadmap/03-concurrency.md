# Phase 3 — Concurrency runtime: goroutines, channels, select

[← Phase 2](02-core-runtime.md) · [Index](README.md) · Next: [Phase 4 →](04-interfaces-reflection.md)

**Status:** `IN_PROGRESS` (opened 2026-05-02)
**Prerequisites:** [Phase 2](02-core-runtime.md) `DONE`
**Goal:** Implement `GADA.Async` — M:N goroutine scheduler, bounded and
unbounded channels, Go's `select` statement — with full coverage. After
this phase, Go programs using `go`, channels, and `select` compile and
run with semantics matching the Go reference.
**Exit criterion:** `make example HELLO=ping_pong` runs a 2-goroutine
ping-pong over a channel for 1 million iterations and exits cleanly.

## Items

- [x] **ADR — scheduler design (libco vs CPS)**
      *Files:* `docs/adr/0004-scheduler-libco-for-v1.md`
      *Verify:* ADR is `accepted` with consequences enumerated.
      *Done when:* design choice is recorded with the alternatives explicitly considered.
      *Done 2026-05-01:* Already shipped during Phase 0 foundation work — predates Phase 3 opening. ADR-0004 records the M:N-over-Ada-tasks-plus-libco scheduler design for hosted targets and the one-Ada-task-per-goroutine fallback for Ravenscar. Alternatives explicitly considered and rejected in the ADR: pure CPS transformation (compiler-only, no native stack — rejected for `cgo` interop and stack-trace fidelity), pure Ada-task-per-goroutine (too expensive on hosted), pure threads-on-libco (no fallback for Ravenscar). Roadmap item originally projected number 0010; the existing 0004 supersedes — ADR numbering is monotonic, not phase-aligned.

- [ ] **GADA.Async.Context — userland context switching via libco**
      *Files:* (see sub-items below)
      *Verify:* `make -C runtime test PKG=async.context`
      *Done when:* `Switch_To (Other)` round-trips between two contexts 1M times in < 1 s wall-clock; coverage 100%.
      *Notes:* libco is the userspace-coroutine library named in [[0004-scheduler-libco-for-v1]]. It has no Alire crate and no apt package, so it is vendored in-tree. Decomposed into the six sub-items below; the parent ticks when all sub-items tick AND the parent *Verify* passes from a clean build.

  - [x] **(a) ADR — libco bring-up (vendor in-tree, ISC licence, platform matrix)**
        *Files:* `docs/adr/0007-libco-vendoring.md`
        *Verify:* ADR is `accepted` with consequences enumerated and the licence text reproduced.
        *Done when:* design records (1) why vendor vs. system package vs. submodule, (2) ISC licence reproduction + attribution, (3) supported platform matrix for v1 (amd64 + arm64 hosted, others as future work), (4) which upstream commit/tag is pinned and how to update.
        *Done 2026-05-02:* ADR-0007 records the six-part decision: (1) in-tree vendor under `runtime/src/vendor/libco/` (not submodule, not system package — neither apt nor Alire packages libco; submodules add contributor friction for ~25 KB of source); (2) commit-pinned with the SHA recorded in `runtime/src/vendor/libco/README.md` and bumped via dedicated `vendor: bump libco` commits; (3) ISC licence reproduced verbatim at `runtime/src/vendor/libco/LICENSE` and referenced from the README; (4) v1 platform matrix is amd64 + arm64 hosted only (x86_64 / aarch64, Linux + macOS) — other libco-supported arches (PowerPC, x86 32-bit, ARM 32-bit, RISC-V) are vendored but not contracted until Phase 11; (5) per-arch source selection happens at gpr scenario level rather than libco's `#ifdef` cascade so wrong-arch symbols cannot leak into the static archive; (6) the parent's `gada-async-context-thin.c` collapses to a near-empty placeholder for v1 because `cothread_t` is already `void*` — no value in indirection, file kept for future per-arch shims and TSan annotations. Alternatives considered + rejected: system package (does not exist), git submodule (network fetch + clone friction), single-source-with-ifdef (build-system layer is the right place), custom Ada implementation (already rejected by ADR-0004).

  - [x] **(b) Vendor libco source (header + per-arch implementations)**
        *Files:* `runtime/src/vendor/libco/libco.h`, `…/libco.c`, `…/settings.h`, `…/amd64.c`, `…/aarch64.c`, `…/valgrind.h`, `…/LICENSE`, `…/README.md`
        *Verify:* `clang -c runtime/src/vendor/libco/aarch64.c` exits 0 on macOS/arm64; equivalent for `amd64.c` on Linux/x86_64. `nm <obj>` reports `co_create`, `co_active`, `co_switch`, `co_delete` as `T` (defined text symbols).
        *Done when:* Verbatim copy of the upstream source pinned to the commit named in (a); README points at the upstream and the ADR; LICENSE preserves the ISC notice.
        *Done 2026-05-02:* Pinned to upstream `e18e09d634d612a01781168ad4d76be10a7e3bad` (2024-09-09, "Fix all 'declaration after statement' warnings, for greater C89 compatibility"). Eight files vendored: `libco.h` (public API + LIBCO_C-gated settings macros), `libco.c` (dispatcher), `settings.h` (thread_local/alignas portability shims), `amd64.c` + `aarch64.c` (the two v1 architectures from ADR-0007 §4), `valgrind.h` (BSD-licensed, used by both arch files for stack-register hints — separate notice flagged in README), `LICENSE` (ISC, verbatim from upstream), `README.md` (custom — pin block, vendored-files table with per-file licence, NOT-vendored exclusion list rationalising why arm.c/x86.c/ppc*.c/fiber.c/sjlj.c/ucontext.c are skipped per ADR-0007's platform matrix). The bump workflow (`vendor: bump libco to <SHA>`) is documented in the README so a future maintainer can refresh without rediscovering the procedure. Compile verification on macOS/arm64: `clang -c aarch64.c` produces a 6 KB object with `_co_active`, `_co_create`, `_co_delete`, `_co_switch` defined — gate passes. Linux/x86_64 `gcc -c amd64.c` left to CI (sub-item (c) wires the build, then CI exercises both arches).

  - [x] **(c) Build wiring — gada_core.gpr + runtime/Makefile compile the C side**
        *Files:* `runtime/gada_core.gpr`, `runtime/Makefile`, `runtime/src/vendor/libco/README.md` (revised for new design)
        *Verify:* `cd runtime && alr build` exits 0; `nm runtime/lib/libgada_core.a | grep co_create` reports the libco symbols are *defined*, not undefined externals.
        *Done when:* Languages = ("Ada", "C") in the gpr; libco's source dir on the C side; per-arch source selection so a fat binary doesn't try to link both implementations.
        *Done 2026-05-02:* Three concrete changes. **(1) gada_core.gpr** gains `Languages use ("Ada", "C")`, an `Arch_Type` scenario variable defaulting to `external ("ARCH", "amd64")`, `src/vendor/libco` added to `Source_Dirs`, an `Excluded_Source_Files` case that drops `libco.c` (the upstream dispatcher — see ADR-0007 §5) plus the wrong arch's `.c` per `Arch`, and a `C_Switches := ("-O2", "-g", "-Wall", "-Wno-parentheses")` block under `package Compiler`. C-side opt level is -O2 (libco's per-arch file is hand-written assembly wrapped in C; -O0 produces noticeably worse code) while Ada stays -O0 for stack-trace readability — a cross-language opt-level split is unusual but justified here because the libco source is upstream-stable and the Ada side is still actively iterated. `-Wno-parentheses` honours libco's C89-pedantic style (bit-and inside equality without parens) rather than patching the vendored source. **(2) runtime/Makefile** derives `ARCH` from `uname -m` with a normalisation table (`x86_64`/`amd64`/`i386` → `amd64`, `arm64`/`aarch64` → `aarch64`), gates against the supported set, falls back to `amd64` on unrecognised hosts so a build attempt still happens (with a clear wrong-arch link error rather than a silent gpr crash), and `export ARCH` so the gpr's `external` call picks it up. **(3) runtime/src/vendor/libco/README.md** — the "Per-architecture source selection" section was revised to reflect the actual design: libco.c is excluded entirely (not "compiled but empty"), and the rationale for keeping it on disk despite never compiling it (clean diff against upstream, no per-file bump deviations) is explicit. **Verification on macOS/aarch64:** clean `alr build` produces `libgada_core.a` in 1.35 s; `nm libgada_core.a | grep -E "co_(create|switch|active|delete|derive)"` reports all five as `T` (defined); full AUnit suite passes 52/52 across all Phase 2 packages, confirming the new C-compile path doesn't disturb the existing Ada build.

  - [x] **(d) Gada.Async.Context.Libco — thin Ada bindings**
        *Files:* `runtime/src/gada-async.ads` (umbrella), `runtime/src/gada-async-context.ads` (skeleton), `runtime/src/gada-async-context-libco.ads` (no body — pragma Imports stand in)
        *Verify:* `cd runtime && alr build` exits 0; private-child rule rejects external `with`-ing.
        *Done when:* `co_create`, `co_active`, `co_switch`, `co_delete` imported via `pragma Import (C, …)` from a private-child package, mirroring the `Gada.Core.Memory.Libgc` pattern from Phase 2.
        *Done 2026-05-02:* Three new specs land. `gada-async.ads` is the empty Pure umbrella for the Async layer (matches the existing `gada-core.ads` pattern). `gada-async-context.ads` declares `type Context is private` (derived from `System.Address` in the private part) plus `Null_Context` — the skeleton needed for Libco to be a child unit while sub-item (e) stages the user-facing Make/Active/Switch_To/Free surface. `gada-async-context-libco.ads` is the private-child binding layer: `subtype Cothread is System.Address`, `type C_Entry is access procedure with Convention => C` (the convention is load-bearing — Ada's default `access procedure` ABI may pass a hidden context parameter for nested procedures, which would make libco call the entry with stale registers), and pragma Imports for `co_active`, `co_create`, `co_switch`, `co_delete`. The body-less spec mirrors `Gada.Core.Memory.Libgc` from Phase 2 (no .adb needed because pragma Import provides the implementation). Comments call out the single-thread caveat (libco's default build is per-OS-thread; cross-thread switching belongs to the scheduler in Phase 3 item 3) and the Free precondition (must not be called on the active cothread; libco would free its own stack). Build verified on macOS/aarch64: `alr -n build` succeeds in 0.65 s after a clean nuke; libgc + libco + new specs all link into `libgada_core.a` without warnings.

  - [x] **(e) Gada.Async.Context — public spec + body**
        *Files:* `runtime/src/gada-async-context.ads`, `runtime/src/gada-async-context.adb`
        *Verify:* `cd runtime && alr build` exits 0; `grep -rn 'Async\.Context\.Libco' runtime/src | grep -v 'gada-async-context'` is empty.
        *Done when:* `Context`, `Make`, `Switch_To`, `Active`, `Free` exposed at the public layer; body delegates to the Libco child per [[0002-runtime-layered]].
        *Done 2026-05-02:* Public spec exposes `type Context is private`, `Null_Context`, `type Entry_Procedure is access procedure`, plus `Make / Active / Switch_To / Free` with Pre/Post contracts (`Make` requires non-null Entry_Point, posts non-null result; `Switch_To` requires non-null Target; `Free` requires C is null *or* not the active context — libco's `co_delete` cannot run on the active cothread without freeing its own stack mid-execution). Body uses the **registry + trampoline pattern**: a process-local `Entry_Maps.Map` keyed on `System.Address` stores the user-supplied entry per cothread, a C-convention `Trampoline` rediscovers itself via `Libco.Co_Active` and dispatches. The map is *one-shot*: `Trampoline` removes its entry on first run so a stack-recycled cothread address cannot pick up a stale procedure (libco does not recycle today, but the one-shot is cheap insurance). `Hash_Address` uses `Ada.Containers.Hash_Type'Mod (To_Int (A))` — the modular-reduction attribute is the right tool to truncate from `System.Storage_Elements.Integer_Address` (typically 64-bit) to the container's hash width without an explicit mask. `Make` raises `Storage_Error` when `co_create` returns NULL (the documented libco failure mode for stack-mapping exhaustion) so callers — eventually the scheduler — can choose to recover rather than crash. The body imports only `Gada.Async.Context.Libco`, never libco directly: `grep -rn 'Async\.Context\.Libco' runtime/src | grep -v 'gada-async-context'` is empty (the layering invariant from ADR-0002 holds). Build verified on macOS/aarch64: full `alr -n build` from clean succeeds; AUnit harness builds against the new spec without conflict (52/52 still pass).

  - [ ] **(f) AUnit suite — round-trip test, 1M iterations**
        *Files:* `runtime/tests/context_suite.{ads,adb}`, `runtime/tests/test_runner.adb` (registration), `roadmap/03-concurrency.md` (tick item)
        *Verify:* `make -C runtime test PKG=async.context`
        *Done when:* Suite has at least three tests — Make/Free round-trip without leaks, two-context ping-pong (basic), 1M-iter ping-pong asserting wall-clock < 1 s. Per-arch coverage 100% on `gada-async-context.adb` (the .ads has no executable lines).

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
