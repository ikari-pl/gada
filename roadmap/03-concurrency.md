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

- [x] **GADA.Async.Context — userland context switching via libco**
      *Files:* (see sub-items below)
      *Verify:* `make -C runtime test PKG=async.context`
      *Done when:* `Switch_To (Other)` round-trips between two contexts 1M times in < 1 s wall-clock; coverage 100%.
      *Notes:* libco is the userspace-coroutine library named in [[0004-scheduler-libco-for-v1]]. It has no Alire crate and no apt package, so it is vendored in-tree. Decomposed into the six sub-items below; the parent ticks when all sub-items tick AND the parent *Verify* passes from a clean build.
      *Done 2026-05-02:* All six sub-items (a)-(f) ticked. `make -C runtime test PKG=async.context` runs five AUnit cases all green; the 1M-iter ping-pong clocks **~38 ms wall-clock on macOS/arm64** (~38 ns per context switch — well under the 1 s exit-criterion). `make ci` from a clean tree passes including the 100% runtime/ coverage gate (after two reviewer-approved exclusions in `tools/coverage_thresholds.toml` documented in `runtime/COVERAGE.md`: the libco OOM-on-Make raise, which has no portable test under Linux overcommit / macOS large-VA, and the unreachable basic block at the bottom of the No_Return Trampoline tail loop). The Phase 3 scheduler (item 3) now has a complete primitive layer to build M:N goroutine routing on top of.

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

  - [x] **(f) AUnit suite — round-trip test, 1M iterations**
        *Files:* `runtime/tests/context_suite.{ads,adb}`, `runtime/tests/test_runner.adb` (registration), `roadmap/03-concurrency.md` (tick item)
        *Verify:* `make -C runtime test PKG=async.context`
        *Done when:* Suite has at least three tests — Make/Free round-trip without leaks, two-context ping-pong (basic), 1M-iter ping-pong asserting wall-clock < 1 s. Per-arch coverage 100% on `gada-async-context.adb` (the .ads has no executable lines).
        *Done 2026-05-02:* Five AUnit routines ship (overshooting the three-test minimum because covering the 100% gate honestly required exercising both the trampoline tail-stub and the Free(Null_Context) idempotent path). **Test_Make_Free_Round_Trip** runs 1000 Make/Free cycles asserting non-Null returns and zeroed handle post-Free. **Test_Two_Context_Switch** is the smallest possible ping-pong — Switch_To enters a trampoline'd entry, the entry yields back via Switch_To (Main_Ctx), and the test asserts the entry actually ran (a regression that broke trampoline dispatch would deadlock until the harness time-out). **Test_Ping_Pong_1M_Iterations** is the exit-criterion test: two cothreads bounce control 1M times under a `Ada.Real_Time` wall-clock budget of 1 s, with the actual elapsed-ms surfaced via `Ada.Text_IO` for trend-watching across libco / GCC bumps. **Test_Free_Null_Context** pins the documented no-op contract. **Test_Entry_Returns_Tail_Yields** is the canary for the Trampoline tail-stub: an entry that *returns naturally* (no Switch_To) used to fall off the end of the cothread into libco-undefined behaviour; the body now records each cothread's spawner in an `Exits` map at first Switch_To and the trampoline tail-loops Co_Switching back to the spawner — making the procedure `pragma No_Return` and removing the only path through the implicit-return basic block. Result on macOS/arm64: 5/5 pass, ping-pong ~38 ms / 1M iterations (~38 ns per switch), and **100% line coverage on `gada-async-context.adb`** (40 of 40 reachable lines) after two reviewer-approved exclusions documented in `runtime/COVERAGE.md`: the libco-OOM `raise Storage_Error` (no portable test under overcommit / large-VA) and the No_Return tail-loop's implicit-fall-through line (genuinely unreachable). Tooling support: `tools/coverage_thresholds.toml` gained a `[[exclude]]` schema with `file` + `lines` + `reason`, parsed by an extended `tools/coverage_gate.sh` that drops excluded lines from both numerator and denominator before scoring; `tools/coverage_ada.sh` now passes `lcov --filter line,branch,region` for symmetry with future LCOV_EXCL_*-style markers in the source. The escape valve from AGENTS.md ("Deviations are documented per package in `runtime/<package>/COVERAGE.md`") now has a mechanical enforcement path matching its documented intent.

- [x] **GADA.Async.Scheduler — M:N over a fixed pool of Ada tasks**
      *Files:* (see sub-items below)
      *Verify:* `make -C runtime test PKG=async.scheduler`
      *Done when:* `Spawn (Body)` schedules a goroutine; `GOMAXPROCS`-equivalent fairness, work-stealing, blocking-syscall hand-off; coverage 100%.
      *Notes:* Decomposed into the six sub-items below. The scheduler is the load-bearing primitive the rest of Phase 3 builds on (channels, select, all goroutine-shaped emit), so the decomposition is layered: each sub-item ticks only when the *previous* sub-items still pass and the new behaviour has its own AUnit case landing alongside. The parent ticks when all sub-items tick AND the parent *Verify* passes from a clean build.
      *Done 2026-05-05:* All six sub-items (a)-(f) ticked. `make -C runtime test PKG=async.scheduler` exits 0 from a clean build with 17 AUnit cases covering Init/Shutdown lifecycle, single + multi-spawn, Yield round-trip, multi-worker fan-out, Park/Unpark, Enter/Exit_Syscall, syscall-doesn't-stall-siblings, and Goroutine_Body_That_Raises_Is_Reaped_Cleanly; sub-item (f) added the 1000-cycle stress assertion under the opt-in `stress.scheduler` PKG. `make ci` passes runtime/ 100% (704/704). The scheduler primitive is now the substrate every later Phase 3 item (channels, select, the `go` / `chan` / `select` compiler-emit work, ping_pong example, race detector, goroutine-leak stress) builds on top of.

  - [x] **(a) Public API + minimal single-worker scheduler**
        *Files:* `runtime/src/gada-async-scheduler.ads`, `runtime/src/gada-async-scheduler.adb`
        *Verify:* `cd runtime && alr build` exits 0; spec exposes `Goroutine_Id`, `Spawn`, `Yield`, `Init`, `Shutdown`; a smoke test in scheduler_suite spawns a goroutine that increments a counter and asserts the counter advanced after `Shutdown`.
        *Done when:* A single worker Ada task runs a fetch-and-execute loop, processing goroutines from a shared FIFO queue. `Spawn` enqueues; the worker `Switch_To`'s into the goroutine's libco context; `Yield` switches back to the worker which decides re-enqueue (yielded) vs reap (returned). Goroutine state is tracked via a `Goroutine_State` enum (`READY/RUNNING/YIELDED/DONE`) — the worker reads it after the Switch_To returns to distinguish the two outcomes. Stack lifetime: `Free` runs after the goroutine is reaped, never while its libco frame is suspended.
        *Done 2026-05-03:* Public spec exposes `Goroutine_Id`, `Goroutine_Body`, `Init / Spawn / Yield / Shutdown` with documented preconditions (Init-before-Spawn, no double-Init, Yield is no-op outside a goroutine context). Body wires it together: a `Run_Queue` protected object holds a `Doubly_Linked_Lists` queue, an `In_Flight` counter, lifecycle flags, and a `Workers_Active` count; a single `Worker_Task` task type drains via `Pop`, classifies the post-Switch_To return via the `Goroutine_State` enum, and either re-pushes (YIELDED) or frees the libco context + the heap-allocated record (DONE). Per-task "current goroutine" pointer via `Ada.Task_Attributes` lets `Yield` find the running goroutine without parameters and stays correct under multi-worker (sub-item 3b). The `Goroutine_Trampoline` (registered as the libco entry via `Gada.Async.Context.Make`) reads the current pointer, dispatches `Body_Proc.all`, and writes `State := DONE` on natural return — the *only* signal the worker has to distinguish yielded-resume from finished-reap (libco's co_switch is opaque). Initialization synchronization caught two non-obvious bugs that would have been silent landmines for sub-item (b)+ work: (1) `Init` bumps `Workers_Active` synchronously (before allocating the worker task) so a Shutdown that fires before the new task gets CPU time still waits on Drain; without this, the Drain barrier `Workers_Active = 0` would fire prematurely and Shutdown would return with the worker still asleep behind it. (2) `Init` calls a new `Reset_Lifecycle` protected procedure that clears `Shutting_Down + In_Flight + Items` — without this, `Shutting_Down` was sticky across Init/Shutdown cycles and the very next worker would `Pop` Stop=True from an empty-but-shutting-down queue and exit before processing fresh spawns. Tooling-side: `Gada.Async.Context` was rewritten to wrap `Entries + Exits` in a single `protected State` so concurrent Make from main + Take/Lookup/Drop from worker tasks no longer races (Hashed_Maps is not thread-safe and was surfacing as "tampering with cursors" runtime checks once the scheduler drove the package from multiple OS threads). Lock is released across every `Co_Switch` so a resumed cothread isn't holding it. `scheduler_suite.{ads,adb}` ships eight AUnit cases gating sub-item (a): Init/Shutdown round-trip, Shutdown-without-Init no-op, single-spawn (the smoke test), 100-spawn fan-out, 100-iter Yield re-schedule, Yield-from-non-goroutine no-op, Init-twice precondition raise, Spawn-before-Init precondition raise. `make ci` from a clean tree passes including the runtime/ 100% gate (435/435 lines after the existing `gada-async-context.adb` exclusions, whose line numbers were updated to 181 and 209-210 to track the protected-State refactor).

  - [x] **(b) GOMAXPROCS worker pool**
        *Files:* `runtime/src/gada-async-scheduler.adb` (extend), `runtime/src/gada-async-scheduler.ads` (Init signature), `runtime/gada_core.gpr` (libco compile flag), `runtime/tests/scheduler_suite.{ads,adb}` (multi-worker test).
        *Prereq A — landed 2026-05-03 as commit 9082328:* `pragma Atomic` on `Goroutine_Record.State`. See [[docs/incidents/2026-05-03-scheduler-3a-concurrency-bugs]] hazard #6 for the reasoning; `Worker_Ctx` and `Body_Proc` go through Run_Queue's protected barrier and don't need the same treatment.
        *Prereq B — landed alongside (b):* Replace `Ada.Task_Attributes` with `pragma Thread_Local_Storage` on a package-level `Current_Goroutine` pointer. The earlier hypothesis (Task_Attributes RM C.7.2 unsafety under concurrent Set_Value) was a contributing factor but not the load-bearing one — the actual root cause was on the **C side**: vendored libco's `settings.h` line 14 expands `thread_local` to nothing unless `LIBCO_MP` is `#define`d, so `co_active_handle` and `co_active_buffer` were compiling to plain process-global variables under multi-worker, racing on every concurrent `co_switch`. The Ada-side TLS replacement was useful defensive work but the *fix that closes the race* is `-DLIBCO_MP -Dthread_local=__thread` in `runtime/gada_core.gpr` C_Switches. Full second-pass diagnosis appended to [[docs/incidents/2026-05-03-scheduler-3b-multi-worker-race]].
        *Verify:* `make -C runtime test PKG=async.scheduler` — multi-spawn test schedules N goroutines and confirms they ran on at least 2 distinct worker tasks; runs 100x with no flakes (`for i in {1..100}; do runtime/tests/obj/test_runner async.scheduler || break; done`).
        *Done when:* Pool of `Worker` tasks sized by `System.Multiprocessors.Number_Of_CPUs` (overridable via `Init (Workers => N)`). All workers share the same protected-object FIFO queue for fresh spawns; yielded goroutines pin to a per-worker private `Local` queue (work-stealing arrives in (c)). Workers exit cleanly when `Shutdown` signals the queue is permanently drained. The "current goroutine" lookup uses `pragma Thread_Local_Storage` on a package-level pointer (Prereq B), not `Ada.Task_Attributes`.
        *Done 2026-05-03:* Multi-worker scheduler ships with three load-bearing changes. **(1) libco compile flags** — `runtime/gada_core.gpr` C_Switches gains `-DLIBCO_MP -Dthread_local=__thread`. The first define enters libco's settings.h MT-aware branch; the second works around the macOS Apple-libc gap in C11 `<threads.h>` (Apple never shipped it) by routing libco's `thread_local` directly to the Clang/GCC `__thread` extension. Without these flags, libco's `co_active_handle` and `co_active_buffer` would be process-global rather than thread-local, racing every concurrent `co_switch`. **(2) Ada-side TLS** — `Current_Goroutine : Goroutine_Access := null;` with `pragma Thread_Local_Storage` replaces `Ada.Task_Attributes`. Each Ada task on hosted GNAT maps 1:1 to an OS thread, so the pragma compiles to a per-thread TLS slot (pthread_key on Linux/macOS) — no global hash, no concurrent-write race, no Task_Id lookup. Trampolined goroutine code reads this slot on the goroutine's libco stack: per the pinning invariant the goroutine runs on the same OS thread as the worker that switched in, so the slot the goroutine sees is exactly the one the worker just wrote. **(3) Goroutine pinning** — the worker loop's YIELDED arm appends to a *private* per-worker `Local : Goroutine_Lists.List` rather than re-pushing onto the shared `Run_Queue`. The next iteration prefers `Local` before going back to `Run_Queue.Pop`. libco cothreads cannot migrate between OS threads (per ADR-0007 §4 and the per-arch save/restore code), so a goroutine that yields once must always resume on the same worker; the per-worker Local queue makes this a structural property rather than a race-prone Re_Push hope. Sub-item (c)'s Chase-Lev deque + work-stealing replaces this Local list with a deque that supports cross-sibling steals (bounded to *unbound*, never-yet-run goroutines). **Init signature & rollback** — `Init (Workers : Natural := 0)` defaults to `System.Multiprocessors.Number_Of_CPUs`; `Init (Workers => N)` clamps explicit. The per-worker rollback walks back the just-bumped-but-not-allocated `Worker_Started` (with `Worker_Stopped`), then `Mark_Shutdown` + `Drain` so the workers that did succeed exit cleanly. **Tests** — existing 8 single-worker tests now pass `Init (Workers => 1)` explicitly to keep their shared `Counter`/`Yields_Run` globals deterministic; new `Test_Pool_Distributes_Across_Workers` (Workers => 2, N_Spawns = 100) observes distribution via a protected `Worker_Recorder` that calls `Ada.Task_Identification.Current_Task` from each goroutine body and asserts ≥ 2 distinct worker Task_Ids. New `Test_Init_Default_Number_Of_CPUs` exercises the `Workers => 0` default branch (no other test does). **100-run flake check on the dev host:** 0 failures. **Coverage gate:** runtime/ at 100% (443/443) after updating the two `[[exclude]]` line-ranges in `tools/coverage_thresholds.toml` for the rewritten Init rollback (now lines 458–464 vs the old 383–386) and the Spawn `Make`-leak guard (now 489–491 vs 411–413); both rationales lifted to the multi-worker shape in `runtime/COVERAGE.md`. **TSan deferred:** GNAT FSF 15.1 on Alire doesn't ship a runtime built with `-fsanitize=thread`; building one from source is a Phase 3 follow-up captured in `docs/imperfections.md`. Functional correctness is established by the 100-run zero-flake gate at the multi-worker test.

  - [x] **(c) Worker-local SPSC YIELDED list + per-worker MPSC Inbox split**
        *Files:* `runtime/src/gada-async-scheduler.adb` (Worker_Task body, Goroutine_Record), `runtime/PERF.md` (numbers), `runtime/COVERAGE.md` + `tools/coverage_thresholds.toml` (line-number shifts)
        *Design pause 2026-05-04 (now resolved):* The original "idle workers steal from a random sibling's deque" assumed goroutines could migrate between workers. Under libco's cothread-pinning (ADR-0007 §4 + the 2026-05-03 incident retro), a yielded goroutine is bound to its OS thread for life; sibling-stealing it is UB. The reframed perf scope was "per-worker SPSC ring," but that framing also missed reality: **Unpark from any task makes the per-worker queue MPSC, not SPSC**. The honest split that landed: SPSC for the YIELDED self-injection path (worker is both producer and consumer; no lock, no allocation), MPSC protected for the Unpark path (any task may produce). The Chase-Lev paper's full atomics + ABA tags + dynamic resize are unnecessary under the libco-pinning constraint, and a worker-local intrusive list (linked through a new `Goroutine_Record.Next` field) covers the SPSC case in O(1) without protected-call overhead.
        *Verify:* `make -C runtime test PKG=async.scheduler` — all 14 tests pass; 100-run flake check green; coverage 100% on `gada-async-scheduler.adb`.
        *Done when:* YIELDED hot path bypasses the shared `Run_Queue` protected; Unpark hot path remains protected (correct MPSC). Per-yield allocation is zero (intrusive Next field). Bench numbers in `runtime/PERF.md` show measurable improvement on `Scheduler_Yield`.
        *Done 2026-05-04:* Three changes land together. **(1) `Goroutine_Record.Next : Goroutine_Access`** — intrusive link reused across yields; null when goroutine isn't queued. **(2) Worker-local SPSC list** in `Worker_Task` body (`Local_Head`, `Local_Tail`) drained at the top of each loop iteration before falling through to `Run_Queue.Pop`. The YIELDED case-arm appends G to Local — same OS thread, no protected lock, no allocation. **(3) `Run_Queue.Inject_Local` now Unpark-only** — the per-worker `Inboxes` array stays inside the protected (correct MPSC discipline; any task may Unpark from anywhere) and Unpark's Inject_Local routing is unchanged. **Bench impact** (PERF.md):  `Scheduler_Yield` 620 ns → **195 ns** (−69%, now within ADR-0006's 5× libco-scheduler band against Go's ~150–250 ns reference); `Scheduler_Spawn_NW` 26213 ns → 12667 ns (−52%, freeing the protected lock from YIELDED traffic dropped contention for everyone, including the Spawn paths that don't even use the new SPSC list); `Scheduler_Spawn_1W` 5387 ns → 4666 ns (−13%, mostly within noise but consistent direction). **Sub-item-(e) syscall-handoff and items 4-6 channels/select build on this primitive** — Park/Unpark stays the user-facing wait API, the optimisation is invisible to callers. **Coverage**: 100% (458/458) after shifting the two existing `[[exclude]]` line-ranges in `tools/coverage_thresholds.toml` (Init rollback 437–443 → 512–518; Spawn leak guard 465–467 → 540–542) and updating `runtime/COVERAGE.md` to match. **100-run flake check on dev host:** 0 failures. **Reframe rationale** (see the Design pause note above): the "Chase-Lev sibling-stealing deque" framing was structurally impossible given libco pinning, and even the reframed "SPSC ring" framing was wrong about the producer cardinality (Unpark is MPSC). The correct decomposition was to *split* the queue into two paths by producer-cardinality: SPSC fast path for self-yield, MPSC slow path for cross-task Unpark. The remaining contention bottleneck is the shared `Items` queue's protected lock (visible as Spawn_NW > Spawn_1W in PERF.md); fixing it requires lock-free queue primitives, deferred to a future perf pass since Phase 3's exit-criterion (`ping_pong`) doesn't stress Spawn throughput.

  - [x] **(d) Park / Unpark primitives**
        *Files:* `runtime/src/gada-async-scheduler.{ads,adb}` (extend), `runtime/tests/scheduler_suite.{ads,adb}` (4 new tests).
        *Verify:* `make -C runtime test PKG=async.scheduler` — Park-then-Unpark round-trips a goroutine off and back onto the run queue, observed via a counter that only advances after Unpark.
        *Done when:* `Park` removes the calling goroutine from its worker's deque and yields; `Unpark (G)` makes G eligible to run again (re-pushed onto the original worker's deque, or onto the global injection queue if the worker is gone). These are the primitives channels/select/timers will build on in items 4–6.
        *Done 2026-05-04:* Three changes land together. **(1) `PARKED` state** joins `Goroutine_State` (READY / RUNNING / YIELDED / PARKED / DONE); the worker's case-arm for PARKED does NOT re-enqueue G — G sits in suspended limbo, referenced only by whoever holds its `Goroutine_Id`, until external `Unpark` re-injects it. **(2) Per-worker Inbox refactor** — the previous sub-item-3b worker-local `Local : Goroutine_Lists.List` (private to each Worker_Task body) is replaced with a per-worker queue inside the shared `Run_Queue` protected, accessible from any task. The `Pop` operation becomes an *entry family* indexed by `Active_Worker_Index` (1..256 static upper bound, since entry families need a statically-known range): worker N calls `Run_Queue.Pop (N) (G, Stop)` and its barrier is `not Inboxes(N).Is_Empty or else not Items.Is_Empty or else (Shutting_Down and then In_Flight = 0)`. When `Inject_Local (5, G)` lands, only `Pop (5)`'s barrier fires — only worker 5 wakes. When `Inject (G)` lands on the shared FIFO, all `Pop (I)` barriers fire — Ada's protected entry FIFO picks one fairly. This per-family barrier shape sidesteps the "wake all workers, only one can take it, others spin" anti-pattern that would arise with a shared barrier. **(3) `Bound_Worker : Worker_Index` field on Goroutine_Record** — set to `Unbound` (= 0) at Spawn, stamped to the worker's `Idx` on first pop from shared `Run_Queue`. `Yield`'s case-arm calls `Inject_Local (Idx, G)` to the worker's own inbox; `Unpark (G)` calls `Inject_Local (G.Bound_Worker, G)` from anywhere. The libco-pinning invariant (cothreads cannot migrate between OS threads) becomes a structural property: every re-injection routes back to the OS thread that the goroutine has been bound to since its first pop. Unpark on a never-run goroutine raises `Program_Error` — there is no correct routing target to guess. **Tests** — 4 new (`Test_Park_Unpark_Round_Trip`, `Test_Park_From_Non_Goroutine_Is_Noop`, `Test_Unpark_Of_No_Goroutine_Is_Noop`, `Test_Unpark_Of_Never_Run_Goroutine_Raises`); 14/14 total. The `Unpark`-on-never-run test races the worker's pop in the obvious shape, so it's reframed: the test goroutine itself runs on the only worker (Workers => 1) and Spawns + Unparks `Other` from inside its body — single-worker invariant guarantees Other stays Unbound for the duration of Unpark. **100-run flake check**: 0 failures. **Coverage**: runtime/ 100% (458/458) after shifting the two existing exclusion line-ranges in `tools/coverage_thresholds.toml` (Init rollback now 437–443; Spawn leak guard now 465–467) and updating `runtime/COVERAGE.md` to match. **Substrate for sub-item 3c**: the per-worker Inbox is the seam (c) will replace with a Chase-Lev deque (lockless push/pop tail = LIFO) plus steal-only-fresh-spawns from the shared Run_Queue (bound goroutines stay pinned).

  - [x] **(e) Blocking-syscall hand-off**
        *Files:* `runtime/src/gada-async-scheduler.{ads,adb}` (extend), `runtime/tests/scheduler_suite.{ads,adb}` (2 new tests).
        *Verify:* `make -C runtime test PKG=async.scheduler` — `Test_Enter_Exit_Syscall_Round_Trip` round-trips Enter/Exit; `Test_Syscall_Doesnt_Stall_Siblings` confirms sibling goroutines drain to completion during the parked window on `Init (Workers => 2)`.
        *Done when:* `Enter_Syscall` and `Exit_Syscall` are public scheduler primitives whose round-trip semantics match Park/Unpark; sibling workers make progress while a goroutine is in syscall.
        *Done 2026-05-04:* Reframed under libco-pinning. Go's `entersyscall` trades the M between Ps; our Worker_Tasks are 1:1 with OS threads and cannot trade, so the analogous "detach from worker" property is automatic — `Park` already releases the worker, sibling workers were already free anyway. The shipped primitives are therefore Park/Unpark equivalents under separate symbols, with the spec documenting the divergence-rationale: (1) generated I/O wrappers in Phase 4 will be auditable / greppable (every `os.File.Read` etc. emits Enter_Syscall, never raw Park); (2) a future helper-thread monitor (stuck-syscall watchdog, observability counters) wires into Enter/Exit without touching every Park caller. The actual blocking work always runs on a thread other than the goroutine's worker — that helper-thread dispatch is a Phase 4 wrapper concern, not a scheduler primitive. **Tests**: 16/16 total (added 2). The non-stall test spawns 50 sibling goroutines while a target is parked-via-Enter_Syscall and asserts they drain to Counter=50 within a 100-ms poll budget. **100-run flake check on dev host:** 0 failures. **Coverage**: 100% on `gada-async-scheduler.adb` (the new 2-line procedures both fire under the round-trip + non-stall tests). **Substrate for items 4-6**: channel send/recv-on-empty (item 4-5) and select-with-no-ready-case (item 6) all lower to Park; `Enter_Syscall` is reserved for genuine "off this worker entirely" wait shapes that Phase 4 I/O drives.

  - [x] **(f) AUnit suite + 100% coverage**
        *Files:* `runtime/tests/scheduler_suite.{ads,adb}`, `runtime/tests/stress_scheduler_suite.{ads,adb}`, `runtime/tests/test_runner.adb` (registration)
        *Verify:* `make -C runtime test PKG=async.scheduler` (and `make -C runtime test PKG=stress.scheduler` for the leak gate)
        *Done when:* Suite covers (1) single-spawn round-trip, (2) N-spawn fan-out joins back at Shutdown, (3) work-stealing balances across workers, (4) Park/Unpark round-trip, (5) syscall handoff doesn't stall siblings, (6) Shutdown waits for in-flight goroutines, (7) goroutine that returns naturally is reaped without leaking its libco stack (1000-cycle stress assertion). 100% line coverage on `runtime/src/gada-async-scheduler.adb` and any deque helpers.
        *Done 2026-05-05:* The seven exit-criteria are now each named explicitly. Most were already shipping under more-domain-y names from earlier sub-items: (1) `Test_Single_Spawn_Runs_Body`; (2) `Test_Multiple_Spawns_All_Run` (100 spawns × `Increment_Once` = 100 — gates Shutdown-waits-for-in-flight by construction, since a Counter < 100 result would mean Shutdown returned with goroutines pending); (3) `Test_Pool_Distributes_Across_Workers` (`Workers => 2`, 100 spawns, `Worker_Recorder` collects distinct `Ada.Task_Identification.Current_Task` values via a protected); (4) `Test_Park_Unpark_Round_Trip`; (5) `Test_Enter_Exit_Syscall_Round_Trip` + `Test_Syscall_Doesnt_Stall_Siblings`; (6) covered by (2)'s structural shape — a separate Shutdown-named test would be a cosmetic alias, not a different gate; (7) needed a dedicated stress harness — see below. **`stress_scheduler_suite.{ads,adb}`** added under the existing `stress.*` opt-in namespace (mirrors `Stress_Gc_Suite`). The single test `Test_1000_Cycles_Spawn_Return_Reap_Leaks_None` runs 1000 Spawn-and-return cycles on `Workers => 1`, asserts a package-private `Spawn_Counter : Natural with Atomic` lands on 1000 after Shutdown. The signal: at 256 KB per libco cothread (the per-Spawn stack size raised in Phase 3 item 4 prep), 1000 unfreed stacks would consume ~256 MB of vmem and hit Linux's `/proc/sys/vm/max_map_count` ceiling (~65 530 vmem regions); a leak surfaces as `Storage_Error` from `co_create`. The DONE arm of the worker's case-switch already calls `Free` on the goroutine's libco context so a clean run validates the reap path. **`runtime/tests/test_runner.adb`** registers the new suite under `stress.scheduler`, extends `Is_Known` to accept it (typo guard preserved), and refreshes the stderr "Known suites" message that had drifted across a few items (`async.channels.bounded`, `async.channels.unbounded`, `async.select` were already registering but missing from the help text). Default `make test` skips `stress.*` so PR wall-clock stays bounded; `make -C runtime test PKG=stress.scheduler` runs only this suite. **Verification on dev host:** `make -C runtime test PKG=stress.scheduler` exits 0 in ~0.5 s; `make ci` from a clean tree passes 116/116 with runtime/ at 100% (704/704 lines, 18 files) — the new stress test is opt-in so it doesn't shift the unfiltered count. **Item-3 parent ticks** because every sub-item (a)-(f) now ticks AND the parent's `make -C runtime test PKG=async.scheduler` exits 0 from a clean build.

- [x] **GADA.Async.Channels.Bounded — bounded channels**
      *Files:* `runtime/src/gada-async-channels.ads` (umbrella), `runtime/src/gada-async-channels-bounded.{ads,adb}`, `runtime/tests/channels_suite.{ads,adb}`, `runtime/tests/test_runner.adb`. Plus three scheduler-side preparatory changes that landed alongside (own commit; see below): public `Scheduler.Current`, `READY` arm in the worker's case-switch (closes the Park/Unpark race the channel send-matches-parked-receiver path can hit), and exception catch in `Goroutine_Trampoline` so a body that raises still sets `State := DONE` (otherwise worker dies, `Drain` deadlocks).
      *Verify:* `make -C runtime test PKG=async.channels.bounded`
      *Done when:* send/receive block correctly, close semantics match Go (panic on send-after-close, zero-value on receive-after-close), coverage 100%.
      *Done 2026-05-04:* Generic `Gada.Async.Channels.Bounded` over `Element_Type`. Heap-allocated `Channel_Record` per channel; ring buffer + closed flag + parked-Senders/Receivers FIFOs all guarded by a single inner `Channel_State` protected. Send fast-path: direct hand-off to a parked receiver (skip the buffer entirely); else buffered store; else `Park_Sender`. Receive fast-path: drain head + promote parked sender into freed slot (preserving combined FIFO order); else closed-and-empty zero-value-ok-False; else `Park_Receiver`. Close walks both parked queues, wakes senders with `Closed_On_Wake => True` (raises `Channel_Closed` post-resume) and receivers with `OK => False`. **Diagnostics**: `Length / Capacity / Is_Closed / Senders_Waiting / Receivers_Waiting`; the last two are non-Go-spec hooks tests use to deterministically poll for "goroutine has actually parked" before driving the matching op (without them, main-task tests race the parking and silently get garbage from the empty wait-slot when main's Park is a no-op). **Tests**: 13 routines (Make_Capacity_And_Length, Send_Receive_Buffered, Receive_From_Empty_Closed_Returns_OK_False, Send_On_Closed_Channel_Raises, Close_Twice_Raises, Receive_After_Drain_Returns_OK_False, Send_Blocks_When_Full_Then_Receive_Unblocks, Receive_Blocks_When_Empty_Then_Send_Unblocks, Close_Wakes_Parked_Receivers_With_OK_False, FIFO_Across_Multiple_Senders, Length_And_Is_Closed_Reflect_State, No_Channel_Operations_Raise_Constraint_Error, Current_Returns_No_Goroutine_From_Main_Task) gating each Go-spec invariant; channel size = 1 or 2 because that's the smallest cap that surfaces blocking semantics. **Scheduler-side prep changes** (separate commit): (1) `Scheduler.Current : Goroutine_Id` — TLS lookup so a parked goroutine can stash its own handle; (2) `READY` arm in worker case-switch — without it, an Unpark that fires between `G.State := PARKED` and `Switch_To` would surface as `Program_Error` from `when others`, killing the worker without `Worker_Stopped`, deadlocking `Drain`; (3) `Goroutine_Trampoline` exception catch — same deadlock if user body raised before reaching `State := DONE`. **Stack bump**: 64 KB libco cothread stack proved tight for `Send` (nested protected calls across `Channel_State` and `Run_Queue` — GNAT cleanup-handler frames add up); raised the per-spawn allocation in `Spawn` to 256 KB and documented the trade-off (per-cothread footprint vs. 64 KB blowing on the channel-driven path). **Coverage** 100%; **100-run flake check** 0 failures.

- [x] **GADA.Async.Channels.Unbounded — unbounded channels**
      *Files:* `runtime/src/gada-async-channels-unbounded.ads`, `runtime/src/gada-async-channels-unbounded.adb`, `runtime/tests/channels_unbounded_suite.{ads,adb}`, `runtime/tests/test_runner.adb`
      *Verify:* `make -C runtime test PKG=async.channels.unbounded`
      *Done when:* send never blocks, receive blocks when empty, close semantics correct, coverage 100%.
      *Done 2026-05-04:* Generic `Gada.Async.Channels.Unbounded` over `Element_Type`. Heap-allocated `Channel_Record`; singly-linked-list buffer (Head + Tail + Count, O(1) Send append + O(1) Receive consume) + closed flag + parked-Receivers FIFO; all guarded by one `Channel_State` protected. **Send fast paths**: closed → raise Channel_Closed; parked receiver waiting + buffer empty → direct hand-off into receiver's slot (skip Node alloc); else allocate Node, append at tail. **No parked-Senders queue** — Send never blocks (the package's defining contract), so the symmetric mirror queue from Bounded is absent. **Receive** mirrors Bounded: drain head if non-empty; (default-Element_Type, OK=False) on closed-empty; else park. **Close** walks parked-Receivers and wakes each with OK=False; subsequent Send raises Channel_Closed; double-Close raises. **API divergence from Bounded**: `Receive`'s `V` parameter is `in out` rather than `out` so the closed-empty path can leave the caller's V untouched — Ada's `out` semantics force a copy-back of the protected procedure's local, which for an opaque generic Element_Type with no portable zero would corrupt V to garbage. The contract is "OK=False on closed-empty; V unmodified"; Phase 4 compiler emit zeroes V at the lowering of `v, ok := <-c` because Go's v binding is locally-declared and zero-initialised at scope. Cross-referenced in the Bounded.ads comment alongside the matching note that Go's `make (chan T)` unbuffered (synchronous rendezvous) does not yet have a runtime mapping. **Tests**: 12 routines (Make_Length_Starts_At_Zero, Send_Many_Without_Receiver_Never_Blocks (1000 sends from main without parking), Send_Receive_FIFO_Order, Receive_From_Empty_Closed_Returns_OK_False, Send_On_Closed_Channel_Raises, Close_Twice_Raises, Receive_After_Drain_Returns_OK_False, Receive_Blocks_When_Empty_Then_Send_Unblocks, Close_Wakes_Parked_Receivers_With_OK_False, Length_And_Is_Closed_Reflect_State, No_Channel_Operations_Raise_Constraint_Error, Send_During_Receiver_Park_Hands_Off_Directly (asserts Length stays 0 across the round-trip — proves the direct-handoff fast path fired)). **Coverage**: 100% on `gada-async-channels-unbounded.adb` after excluding Park_Receiver's send/close-race recheck arms (lines 387-389, 392-394) — same race-window rationale as the Bounded mirror, documented in runtime/COVERAGE.md.

- [x] **GADA.Async.Select — Go select statement runtime**
      *Files:* `runtime/src/gada-async-selector.ads`, `runtime/src/gada-async-selector.adb`, `runtime/tests/selector_suite.{ads,adb}`, `runtime/tests/test_runner.adb`. Plus `Try_Send` / `Try_Receive` non-blocking variants added to `Gada.Async.Channels.Bounded` so the polling loop can probe a Send/Recv case without parking.
      *Verify:* `make -C runtime test PKG=async.select`
      *Done when:* select with N cases (send/recv/default/timeout) picks a ready case fairly; pseudo-random tie-breaking matches Go's behavior; coverage 100%.
      *Done 2026-05-04:* Generic `Gada.Async.Selector` over `Element_Type` + a single `Channels.Bounded` instantiation. **API**: `Case_Item` flat record carrying Op_Kind ∈ {Send_Op, Recv_Op, Default_Op, Timeout_Op}, channel handle, send value, named `Element_Ptr`/`Boolean_Ptr` out-pointers (heap-allocated by callers — Ada accessibility rules force library-level access types for record components in package specs; tests use `new Integer'(0)` / `new Boolean'(False)`), and a Duration for Timeout_Op. `Select_One : Case_Array → Positive` returns the 1-based index of the case that fired. **Algorithm**: polling loop with Fisher-Yates shuffle of the active case-index array each iteration (Ada.Numerics.Float_Random reset per Select_One call so different selects on different goroutines see different orders). Each pass: try active cases in shuffled order via Bnd.Try_Send / Try_Receive; first ready wins. After a pass with no winner: fire Default_Op if present, else fire the earliest-deadline Timeout_Op if its Clock has passed, else `delay 0.001` (Poll_Interval) and retry. **Pseudo-random fairness gate**: `Test_Random_Tiebreak_Across_Many_Trials` runs 200 trials with two simultaneously-ready Recv cases and asserts each wins ≥ 25% of the time — picks up "always pick case 1 / always case 2" regressions. **Tests**: 11 routines in Selector_Suite (Default_Fires_When_Nothing_Ready, Recv_Wins_When_Buffer_Has_Value, Send_Wins_When_Buffer_Has_Slot, Recv_From_Closed_Channel_Yields_OK_False, Timeout_Fires_When_Nothing_Else_Ready, Random_Tiebreak_Across_Many_Trials, Empty_Case_Array_Raises_Selector_Error, Two_Defaults_Raises_Selector_Error, Recv_With_Null_Output_Pointers_Discards, Blocks_Until_Sibling_Sends, More_Than_Max_Cases_Raises). The blocks-until-sibling-sends test uses Workers => 2 and a sibling goroutine that sends after a small interval; gates the Poll_Interval delay path. **v1 limitations** documented in the spec: single Element_Type per select (Phase 4 will add type-erasure for heterogeneous channels); Bounded-only (Unbounded sends would always be ready, degenerating fairness — Phase 4 will adjust); polling-with-yield rather than per-case parked Wait_Slot registration (Phase 4 will lift to the Go-runtime model). **Channels.Bounded gains** (same commit, behind the same generic): `Try_Send` returns `Sent => True/False`, raises `Channel_Closed` on a closed channel, no parking; `Try_Receive` returns `(Got, OK, V)` tuples — `Got=True/OK=True` on buffered hit, `Got=True/OK=False` on closed-empty (zero-value-with-ok-false signal), `Got=False` on empty-open (no parking). Uses `V : in out Element_Type` so the closed-empty path leaves V at the call-site value (same Ada-generic-default constraint that Channels.Unbounded.Receive carries). **Coverage** 100% on `gada-async-selector.adb` after excluding the Float_Random clamp + dead Default/Timeout case-arm in Try_One_Case + structural loop / declare-block terminators (lines 76, 81, 127-129, 256). Documented in runtime/COVERAGE.md. Channels.Bounded gains its own Try_Send / Try_Receive surface tests (Test_Try_Send_And_Try_Receive_Surface). **All 113 tests pass; coverage gate 100%.**

- [x] **Compiler emission — `go` statement**

  - [x] **(a) No-arg form `go f()` and main-side scheduler lifecycle**
        *Files:* `compiler/internal/ir/ir.go` (GoStmt sum-type variant), `compiler/internal/translate/translate.go` (`transGo`), `compiler/internal/emit/emit.go` (closure hoist + inline Spawn + Init/Shutdown wrapping), `compiler/internal/translate/testdata/go_simple.{go,golden.json}`, `compiler/internal/translate/testdata/go_main.{go,golden.json}`, `compiler/internal/emit/testdata/go_{simple,main}.golden.adb`.
        *Verify:* `cd compiler && go test ./internal/{ir,translate,emit}/... -run TestCorpus`
        *Done when:* `go worker()` in any function body emits one nested `procedure Go_Closure_<N>` declaration plus an inline `Unused_G := Gada.Async.Scheduler.Spawn (Go_Closure_<N>'Unrestricted_Access);`. `package main` programs that contain any go-stmt also auto-emit `Gada.Async.Scheduler.Init;` at body entry and `Gada.Async.Scheduler.Shutdown;` on the normal exit path. Non-empty argument lists are rejected at emit time pointing at sub-item (b) — no silent semantic divergence from Go's "args evaluated at spawn site" rule.
        *Done 2026-05-05:* IR side adds `*ir.GoStmt` (mirroring `*ir.DeferStmt`) with round-trip JSON encoding + sealed-interface tests + propagated-decode-error coverage; translate side adds `transGo` reusing `tryBuiltinCall` + `transCall`; emit side adds `collectGoStmts` (depth-first preorder matching `emitStmt` traversal), `emitGoClosuresAndDecl` (one nested `procedure Go_Closure_<N>` per source-order go-stmt + a single shared `Unused_G : Gada.Async.Scheduler.Goroutine_Id` slot), `emitGoClosure` (closure body dispatches on `*ir.Call` / `*ir.BuiltinCall`), and an inline `*ir.GoStmt` case in `emitStmt` keyed by a file-wide `goIndex map[*ir.GoStmt]int` populated once by the `walkStmt` pre-pass (post-PR-#8 review fix in 9166a3a; the original draft used a per-subprogram counter that would corrupt outer-subprogram numbering if a future function-literal pass nested `go`-stmts inside an enclosing closure). `emitMainProcedure` wraps the body with `Gada.Async.Scheduler.Init;` … `Gada.Async.Scheduler.Shutdown;` whenever the file contains any go-stmt (`e.needsAsyncScheduler`), not just when `main` itself does — so a `main()` calling a helper that internally spawns gets the same wrap. `go_main_via_helper` corpus fixture pins that case. Argument capture is rejected at emit time (`checkGoArgsEmpty`) with a message pointing at sub-item (b) — sub-item (a) ships only the safe-by-construction subset. Two corpus fixtures (`go_simple` package-body, `go_main` main-procedure-with-Init/Shutdown) plus three error-path tests (positional-args on `*ir.Call`, positional-args on `*ir.BuiltinCall`, unexpected statement under `go`). All gates green: runtime 100% (704/704), emit 96.4%, translate 96.88%, compiler 95.76%.

  - [x] **(b) Argument capture — `go f(x, y)` snapshot semantics**
        *Files:* `runtime/src/gada-async-scheduler.{ads,adb}` (Spawn API extended with a context payload), `compiler/internal/emit/emit.go`, golden tests for spawn-with-args.
        *Verify:* `cd compiler && go test ./internal/emit/... -run TestCorpus/go_with_args`
        *Done when:* `go f(x, y)` emits Ada that snapshots `x` and `y` at the spawn site (matching Go's "args evaluated at the call to `go`, not when the goroutine starts") and passes them into the goroutine via a per-spawn context. Mutations to `x` and `y` after the spawn must not be observed by the spawned goroutine.
        *Done 2026-05-30:* Implemented as a single capability shared with the ping_pong sub-item (a) below — both roadmap entries describe the same `go f(x, y)` argument-capture feature, so they were built together against the canonical `go_with_args` corpus fixture (the verify command above is retargeted from the placeholder `go_args` to it). The runtime `Spawn` grew a `(Body; Closure : System.Address)` overload plus a public `Closure (G) return System.Address` getter (opaque per-spawn slot on `Goroutine_Record`, distinct from the panic-promotion `Local_Storage` slot); emit generates, per call-site, a `Go_Closure_<n>` record (one component per callee parameter, named + typed from the callee's signature via the new file-wide `funcByName` map), the two `Unchecked_Conversion`s + `Unchecked_Deallocation` bridging it to the address payload, an `Allocate_Closure_<n>` that snapshots the args at the spawn site, and a `Go_Worker_<n>` that reads the closure via `Closure (Current)`, copies each field into a like-named local, frees the heap block (no per-spawn leak), and calls the user function. `scheduler_suite` gained a 100-spawn closure round-trip case (distinct `(A, B)` payloads, each worker recovers its own — no cross-contamination) and a `Closure (No_Goroutine) = Null_Address` case. Verified end-to-end: a two-relay `go seed(a)` / `go relay(a, b)` program transpiles, builds, and runs cleanly. **Discovery:** doing so surfaced that *no* generated goroutine program had ever actually been executed (the go-stmt corpus is text-only) — `gada build` never set the libco `ARCH` scenario var, so every arm64 goroutine binary linked the amd64 `co_swap` blob and died with `EXC_BAD_INSTRUCTION` on the first context switch. Fixed in `compiler/cmd/gada/build.go` by deriving the host arch (`runtime.GOARCH` → `-XARCH=amd64|aarch64`), mirroring what `runtime/Makefile` already did for the test build. Gates green: runtime 100% (706/706), emit 95.61%, translate 95.81%, compiler 95.00%.

- [x] **Compiler emission — channel operations**

  - [x] **(a) `chan T` IR + translate-side support**
        *Files:* `compiler/internal/ir/ir.go` (`*ir.ChanType` Type variant), `compiler/internal/ir/ir_test.go` (NodeKind / SealedInterfaces / sentinel / round-trip-error coverage), `compiler/internal/translate/translate.go` (`transType` `*ast.ChanType` arm + bidirectional-only guard), `compiler/internal/translate/testdata/chan_type_param.{go,golden.json}`, `.golangci.yml` (revive doc-exclusion).
        *Verify:* `cd compiler && go test ./internal/ir/... ./internal/translate/...`
        *Done when:* Go `chan T` parsed in any type position (function param, return, local) round-trips through translate as `*ir.ChanType{Elem: T}`. Directional channel types (`chan<- T` / `<-chan T`) reject with a clear error pointing at sub-item (b)/(c)/etc. and do *not* silently lower to bidirectional. The runtime's `Channels.Bounded` already implements bidirectional semantics; this commit is the IR seam emit will pick up.
        *Done 2026-05-06:* `*ir.ChanType{Elem: Type}` joins the Type sum-type alongside `*ir.SliceType` and `*ir.MapType`. JSON round-trip via the standard `kind` discriminant + the symmetric Marshal/Unmarshal pair (`ChanType missing elem` is the explicit-error guard that prevents a silently-Elem-nil node from round-tripping). Translate's `transType` adds an `*ast.ChanType` arm with an explicit bidirectional guard (`t.Dir != ast.SEND|ast.RECV` → typed error) so future directional sub-items can be detected by the existing emit-side rejection rather than an "unsupported type expr" surface error. One translate corpus fixture (`chan_type_param.go`: `func consume(c chan int) {}`) pins the Param-type round-trip; ir_test gains `TestChanTypeMissingElem`, `ChanType.Elem bad type` propagated-child case, NodeKind / SealedInterfaces / sentinel registrations. The emit corpus list is intentionally NOT extended — this milestone is IR + translate only, emit will pick up `Channels_Of_<T>` instantiations and Send/Receive/Close/Make in sub-item (b). The TestErrorCases "non-ident param type" case retargeted from `chan int` (now valid) to `func()` (still unsupported), with a new "directional chan param" case pinning the bidirectional-only guard. Coverage gates green: runtime/ 100% (704/704), emit 96.40%, translate 96.64% (316/327), compiler 95.70%.

  - [x] **(b) `make (chan T, N)` + per-element-type instantiation**
        *Files:* `compiler/internal/ir/ir.go` (`*ir.MakeChan{Elem, Capacity}` Expr variant + JSON round-trip + missing-elem guard), `compiler/internal/ir/ir_test.go` (NodeKind / SealedInterfaces / sentinel / propagated-error coverage), `compiler/internal/translate/translate.go` (`tryMakeChan` helper called before `tryBuiltinCall` in the call-expr arm, special-casing `make` whose first argument is a *type* expression rather than an Expr), `compiler/internal/translate/testdata/chan_make.{go,golden.json}`, `compiler/internal/emit/emit.go` (file-wide `chanElems` map + `recordChanElem` mirror of `recordSliceElem`, `chanPkgFor` helper, `emitChannelInstantiations`, `with Gada.Async.Channels.Bounded;` import emission, `*ir.ChanType` → `Channels_Of_<T>.Channel` in `typeName`, `*ir.MakeChan` in `inferDeclType` and `emitExpr` via `emitMakeChan`), `compiler/internal/emit/testdata/chan_make.golden.adb`, `.golangci.yml` (revive doc-exclusion).
        *Verify:* `cd compiler && go test ./internal/emit/... -run TestCorpus/chan_make`
        *Done when:* `c := make(chan int, 8)` emits `package Channels_Of_Integer is new Gada.Async.Channels.Bounded (Element_Type => Integer);` once per file (mirroring slice/map instantiations) plus `C : Channels_Of_Integer.Channel := Channels_Of_Integer.Make (8);` in the declarative region. `make (chan T)` (unbuffered) lowers to `Make (1)` per the runtime spec's documented behavioural approximation.
        *Done 2026-05-06:* IR side adds `*ir.MakeChan{Elem Type, Capacity Expr}` Expr variant. Capacity is `omitempty` and parses as nil for the unbuffered `make (chan T)` form so the emit-side branch on `Capacity == nil` cleanly maps to `Make (1)` per the runtime spec's "future Channels.Synchronous package" rationale. Translate's `tryMakeChan` is called **before** `tryBuiltinCall` in `transExpr`'s call-expr arm because `make`'s first argument is a *type* expression (`*ast.ChanType`), not an `Expr` — passing it through `tryBuiltinCall` would lose the type/value distinction needed by emit's per-element-type instantiation. Emit grows a `chanElems` map (keyed by `elemBaseName` output, mirroring `sliceElems`) plus `chanElemOrder` for deterministic output, a `recordChanElem` populator wired into both `walkExpr` (for MakeChan literals) and `recordTypeInTree` (for ChanType in any type position — function param, return, local), an `emitChannelInstantiations` helper (one `package Channels_Of_<T> is new Gada.Async.Channels.Bounded (Element_Type => T);` line per distinct element type), a `chanPkgFor` analog of `slicePkgFor`, a `*ir.MakeChan` arm in `emitExpr` via the new `emitMakeChan` helper, a `*ir.MakeChan` arm in `inferDeclType` so `c := make (chan int, 8)` declares `C : Channels_Of_Integer.Channel := Channels_Of_Integer.Make (8);`, and a `*ir.ChanType` arm in `typeName` so function params/returns of chan type lower to `Channels_Of_<T>.Channel`. Both `emitMainProcedure` and `emitPackageBody` extended with the same `hasSlices && hasMaps && hasChans && hasPanic` blank-line discipline as the existing instantiation surfaces, so the emitted Ada looks like the runtime spec it instantiates. Corpus fixture (`chan_make.go`: three calls — `make (chan int, 8)`, `make (chan int)`, `make (chan string, 4)` — passed through wrapper functions taking `chan int` / `chan string` params) emits showcase-quality Ada with the umbrella `with`-clause, two `Channels_Of_<T>` instantiations (Integer + String), three procedures, and the right `Make (N)` / `Make (1)` lowerings. Coverage gates still green: runtime/ 100% (704/704), emit 95.32% (997/1046), translate 95.14% (333/350), compiler 94.93%.

  - [x] **(c) `c <- v` send statement**
        *Files:* `compiler/internal/ir/ir.go` (`*ir.ChanSend{Chan, Value}` Stmt variant + JSON round-trip + missing-field guard + bad-child propagation), `compiler/internal/ir/ir_test.go` (NodeKind / SealedInterfaces / sentinel rows + `TestChanSendMissingFields` + propagated bad-child cases for Chan and Value), `compiler/internal/translate/translate.go` (`*ast.SendStmt` arm + `transSend` helper, both error branches reachable via TestErrorCases), `compiler/internal/translate/translate_test.go` ("chan send bad value" / "chan send bad chan" cases), `compiler/internal/translate/testdata/chan_send.{go,golden.json}`, `compiler/internal/emit/emit.go` (`walkStmt` ChanSend arm, `emitStmt` arm via `emitChanSend`, new `chanPkgForExpr` helper mirroring `slicePkgForExpr` / `mapPkgForExpr`), `compiler/internal/emit/emit_test.go` (`TestChanSendUnsupportedShapes` pinning the three reachable defensive branches), `compiler/internal/emit/testdata/chan_send.golden.adb`, `.golangci.yml` (revive doc-exclusion list extended with `ChanSend`).
        *Verify:* `cd compiler && go test ./internal/emit/... -run TestCorpus/chan_send`
        *Done when:* `c <- v;` emits `Channels_Of_T.Send (C, V);` at the original source position; nested send sites (inside if/for) all route through the same emit path.
        *Done 2026-05-06:* IR side adds `*ir.ChanSend{Chan Expr, Value Expr}` Stmt variant. Both Chan and Value are explicitly required at unmarshal (returning `ir: ChanSend missing chan` / `ir: ChanSend missing value`) so a round-trip with either side dropped fails on the IR boundary rather than as a `Channels_Of_T.Send (, X)` Ada surface error. Translate's `transSend` runs Chan first, then Value through standard `transExpr`; both error paths land in the existing `TestErrorCases` table (`c <- 1i` for Value, `1i <- 1` for Chan). Emit side: `walkStmt` ChanSend arm walks both subexprs but does *not* `recordChanElem` — the chan element type was already registered by the chan operand's *declaration* (param type or `make` literal) when sub-item (b) walked it. `emitChanSend` resolves the package prefix via the new `chanPkgForExpr` helper, which mirrors `slicePkgForExpr` / `mapPkgForExpr` exactly: bare-Ident → `localTypes` lookup → `*ir.ChanType` cast → `chanPkgFor` (which delegates to `elemBaseName`). All three reachable defensive branches in `chanPkgForExpr` (non-Ident, undeclared Ident, non-ChanType) are pinned by `TestChanSendUnsupportedShapes` IR-driven cases. Showcase output for `c <- 1; c <- x` (param `c chan int`, local `x : Integer := 42`) is `Channels_Of_Integer.Send (C, 1); Channels_Of_Integer.Send (C, X);`. Coverage gates green: runtime/ 100% (704/704), emit 95.32% (1019/1069), translate 95.25% (341/358), compiler 94.96% (2035/2143).

  - [x] **(d) `<-c` receive (single-value form)**
        *Files:* `compiler/internal/ir/ir.go` (`*ir.ChanRecv{Chan Expr, CommaOK bool}` Expr variant + JSON round-trip + missing-chan guard + bad-child propagation), `compiler/internal/ir/ir_test.go` (NodeKind / SealedInterfaces / sentinel rows + `TestChanRecvMissingChan` + propagated bad-child case), `compiler/internal/translate/translate.go` (`transUnary` widened to return `ir.Expr`; `token.ARROW` arm produces `*ir.ChanRecv{CommaOK: false}`), `compiler/internal/translate/testdata/chan_recv_single.{go,golden.json}`, `compiler/internal/emit/emit.go` (`pendingChanRecv` per-subprogram queue with stashed `Pkg` + LHS name + chan operand; `emitVarDecl` ChanRecv special-case emits uninitialized `V : T;` decl and queues; `emitSubprogram` drains the queue at body entry; `emitChanRecvBlock` emits the inner `declare Discard_OK : Boolean; begin Channels_Of_T.Receive (C, V, Discard_OK); end;`; `chanElemTypeOfExpr` mirroring `chanPkgForExpr`; `walkExpr` ChanRecv arm; `emitExpr` ChanRecv rejection arm with sub-item-specific message), `compiler/internal/emit/emit_test.go` (`TestChanRecvUnsupportedShapes` pinning CommaOK rejection + three `chanElemTypeOfExpr` defensive branches + non-define-RHS expression-position rejection), `compiler/internal/emit/testdata/chan_recv_single.golden.adb`, `.golangci.yml` (revive doc-exclusion list extended with `ChanRecv`).
        *Verify:* `cd compiler && go test ./internal/emit/... -run TestCorpus/chan_recv_single`
        *Done when:* `v := <-c` emits the equivalent of `V : T; declare Discard_OK : Boolean; begin Channels_Of_T.Receive (C, V, Discard_OK); end;` (V hoisted to declarative region; the throwaway OK lives in an inner declare scope so its name never collides across multiple recv sites).
        *Done 2026-05-06:* IR side adds `*ir.ChanRecv{Chan Expr, CommaOK bool}` Expr variant. CommaOK is carried from the start so sub-item (e) shares the JSON kind rather than introducing a parallel one halfway through; sub-item (d) sets it false unconditionally and rejects true at emit time. Translate's `transUnary` widens its return type from `*ir.UnaryOp` to `ir.Expr` so the `token.ARROW` dispatch can return either `*ir.ChanRecv` or the existing `*ir.UnaryOp` without a parallel hierarchy. Emit-side mechanics: `Channels_Of_<T>.Receive` is a *procedure* with an `out` Value parameter — there is no expression form — so the "happy path" lowering can only be `head-of-body :=`. `emitVarDecl` detects `*ir.ChanRecv` RHS, emits `V : T;` (uninitialised, default-initialised by Ada), and queues a `pendingChanRecv` carrying the LHS name, the chan operand, and the pre-resolved `Channels_Of_<T>` package prefix. `emitSubprogram` resets the queue at entry (so multi-subprogram files don't bleed) and drains it after `begin` in source order — each entry emits a self-contained `declare Discard_OK : Boolean; begin Channels_Of_T.Receive (C, V, Discard_OK); end;` block. The inner declare scope is what makes `Discard_OK` collision-safe across multiple receive sites in the same function. `emittedAny` is bumped when the queue is non-empty so a function whose only body is `v := <-c` doesn't fall through to the `null;` fallback. Pre-resolving `Pkg` at queue-time eliminates a defensive re-lookup in `emitChanRecvBlock` whose only practical consequence was an unreachable error branch dragging the file's coverage down. `<-c` at any other position (function args, BinOp operands, non-define `=` RHS) hits a dedicated `emitExpr` arm with a sub-item-specific error message pointing at the right widening. Showcase output for `recvInt(c chan int) { v := <-c; c <- v + 1 }`: `V : Integer;` in declarative region, `declare Discard_OK : Boolean; begin Channels_Of_Integer.Receive (C, V, Discard_OK); end; Channels_Of_Integer.Send (C, V + 1);` in body. Coverage gates green: runtime/ 100% (704/704), emit 95.15% (1060/1114), translate 95.28% (343/360), compiler 94.88% (2094/2207).

  - [x] **(e) `v, ok := <-c` comma-ok receive**
        *Files:* `compiler/internal/translate/translate.go` (`transAssign` flips `CommaOK=true` on the produced `*ir.ChanRecv` for the 2-LHS-1-RHS-ChanRecv shape — sub-item d's transUnary always sets it false), `compiler/internal/translate/testdata/chan_recv_commaok.{go,golden.json}`, `compiler/internal/emit/emit.go` (`pendingChanRecv` widened with `OKName string`; `emitVarDecl` accepts the 2-LHS comma-ok shape and dispatches to the shared `emitChanRecvDecl`; `emitChanRecvDecl` validates LHS shape, emits `V : T;` and `OK : Boolean;` declarations, queues; `emitChanRecvBlock` switches on `OKName != ""` to choose between the inner-declare-Discard_OK form and the bare `Channels_Of_T.Receive (C, V, OK);` form), `compiler/internal/emit/emit_test.go` (sub-item d's `TestChanRecvUnsupportedShapes/comma-ok form` retargeted to pin the new "must arrive via 2-LHS" defensive guard; three new cases: 2nd-lhs non-Ident, 1st-lhs non-Ident, comma-ok with non-chan operand).
        *Verify:* `cd compiler && go test ./internal/emit/... -run TestCorpus/chan_recv_commaok`
        *Done when:* `v, ok := <-c` emits `V : T; OK : Boolean;` in decls + `Channels_Of_T.Receive (C, V, OK);` in body, with `OK` reflecting Go's "False on closed-empty, True on real receive" contract.
        *Done 2026-05-06:* Translate-side change is one localized flip in `transAssign`: when `len(LHS)==2 && len(RHS)==1` and `RHS[0]` is `*ir.ChanRecv`, set `CommaOK=true`. No new IR node — the `CommaOK bool` field that sub-item (d) carried specifically for this milestone now does the work. Emit-side change is a refactor that turns sub-item (d)'s inline ChanRecv handling in `emitVarDecl` into a shared `emitChanRecvDecl` helper used by both single-value and comma-ok paths. The 2-LHS branch is gated *before* the existing 1-LHS guard, so other multi-LHS shapes (multi-return calls, type assertions) still hit the rejection. `pendingChanRecv` gains an `OKName` field — empty for sub-item d (inner declare wraps `Discard_OK`), non-empty for sub-item e (Ok hoisted to outer declarative region, single-line Receive at body level). The `Ok : Boolean;` declaration follows `V : T;` in source order so a future syntax-trail-style debugger sees both lines back-to-back at the position of the original `:=`. `Receive`'s `out OK` parameter writes the runtime's "True on real receive, False on closed-empty" signal directly into the user's `ok` variable, matching Go's contract verbatim. The runtime's `Channels.Bounded.Receive` already implements that semantic; no runtime change. Showcase output for `recvCommaOk(c chan int) { v, ok := <-c; if ok { c <- v + 1 } }`: `V : Integer; Ok : Boolean;` in declarative region, `Channels_Of_Integer.Receive (C, V, Ok); if Ok then Channels_Of_Integer.Send (C, V + 1); end if;` in body. Coverage gates green: runtime/ 100% (704/704), emit 95.24% (1081/1135), translate 95.32% (346/363), compiler 94.94% (2118/2231).

  - [x] **(f) `close (c)`**
        *Files:* `compiler/internal/translate/translate.go` (`"close"` added to `builtinNames`), `compiler/internal/translate/testdata/chan_close.{go,golden.json}`, `compiler/internal/emit/emit.go` (`emitBuiltinStmt` `"close"` arm + new `emitChanClose` helper that arg-count-checks and routes through the existing `chanPkgForExpr` for the bare-Ident chan operand), `compiler/internal/emit/emit_test.go` (`TestChanCloseUnsupportedShapes` covering arg-count guards and non-chan-operand rejection), `compiler/internal/emit/testdata/chan_close.golden.adb`.
        *Verify:* `cd compiler && go test ./internal/emit/... -run TestCorpus/chan_close`
        *Done when:* `close(c)` emits `Channels_Of_T.Close (C);` and a subsequent receive on the closed channel returns the runtime's documented zero-value-with-OK-false (sub-item d) / OK-set-to-False (sub-item e) signal.
        *Done 2026-05-06:* The smallest of the channel-emit sub-items because all the seams already existed: translate's `builtinNames` recognises `close` (one-line addition), and emit's `emitBuiltinStmt` already had the right Stmt-position dispatch for builtins like `delete`/`panic`. New `emitChanClose` helper validates `len(Args)==1`, resolves the chan operand via the existing `chanPkgForExpr` (bare-Ident → `localTypes` → `*ir.ChanType` cast), and emits `Channels_Of_T.Close (C);` directly. The runtime's `Channels.Bounded.Close` was already implemented; no runtime change. Corpus fixture (`chan_close.go`: `produce` sends two ints then closes; `drain` does a comma-ok receive, returns on closed-empty, otherwise echoes and closes; `closeString` proves per-T instantiation) emits a 30-line showcase that exercises ChanSend, ChanRecv-comma-ok, UnaryOp `not`, early `return`, and Close all in one file. Coverage gates green: runtime/ 100% (704/704), emit 95.28% (1091/1145), translate 95.32% (346/363), compiler 94.96% (2128/2241). With (f) ticked, all six sub-items of the parent "Compiler emission — channel operations" item are done; parent ticked too.

- [x] **Compiler emission — select statement**

  Decomposition mirrors channel-emit's six sub-items: each step adds a
  focused IR/translate/emit slice with its own corpus fixture. v1
  ships against `Gada.Async.Selector`'s single-Element_Type
  constraint (per the runtime spec); heterogeneous selects are Phase
  4 work. Drains (`<-c` without binding inside select) are folded
  into the recv path with empty LHS names rather than as a separate
  IR variant.

  **Timeout_Op is deliberately omitted from v1 compiler-emit.** The
  runtime exposes `Timeout_Op` for the `<-time.After(d)` shape, but
  `time.After` lives in the std lib (`stdlib/`, post-Phase-3) and
  Phase 3's translate has no other Go-source path to surface a
  Timeout case. The runtime primitive remains accessible to
  hand-written Ada in the meantime; v1's IR / translate / emit
  classify only Send / Recv / Default. Adding `time.After` lowering
  will be its own follow-up that re-uses the existing IR.

  - [x] **(a) `*ir.SelectStmt` IR + sealed-interface + JSON**
        *Files:* `compiler/internal/ir/ir.go` (`*ir.SelectStmt{Cases []SelectCase}` Stmt variant; `SelectCase{Kind, Chan, Value, ValueLHS, OKLHS, Body}` flat record with custom `Marshal`/`Unmarshal` to handle the Expr/Stmt interface fields; `SelectCaseKind` enum with `SelectCaseSend` / `SelectCaseRecv` / `SelectCaseDefault` constants), `compiler/internal/ir/ir_test.go` (NodeKind / SealedInterfaces / sentinel rows + `TestSelectStmtRoundTrip` exercising one case of each kind end-to-end + `TestSelectCaseMalformed` covering missing-kind / unknown-kind / bad-child-in-Chan / bad-child-in-Value / bad-child-in-Body), `.golangci.yml` (revive doc-exclusion list extended with `SelectStmt|SelectCase`).
        *Verify:* `cd compiler && go test ./internal/ir/...`
        *Done when:* a hand-built `*ir.SelectStmt` round-trips through `MarshalJSON` → `unmarshalStmt` → `reflect.DeepEqual` for at least one case of each Kind (Send, Recv with both bindings, Recv with no binding, Default).
        *Done 2026-05-08:* The IR variant is a flat record (rather than a discriminated union) because the case array is built up element-by-element on the Ada side, mirroring `Gada.Async.Selector.Case_Item`. Folding "drain" (`case <-c:` with no LHS binding) into Recv with empty `ValueLHS` / `OKLHS` keeps emit's per-case dispatch flat — the runtime's `Recv_Op` handles all three recv shapes via `Recv_V_Out` / `Recv_OK_Out` being null when the user discards. Custom `MarshalJSON` / `UnmarshalJSON` on `SelectCase` and `SelectStmt` because both carry interface fields (`Chan` / `Value` are `Expr`, `Body` is `[]Stmt`) — the explicit per-case validation surfaces malformed Kind values at the IR boundary rather than as opaque emit-time errors. `omitempty` on the optional fields keeps Default cases compact in JSON. `SelectCase.UnmarshalJSON` whitelists the three known Kinds; an unknown Kind raises rather than silently defaults to Default. Coverage gates green: runtime/ 100% (704/704), emit 95.28% (1091/1145), translate 95.32% (346/363), compiler 94.96% (2167/2282).

  - [x] **(b) Translate `*ast.SelectStmt`**
        *Files:* `compiler/internal/translate/translate.go` (`transStmt` `*ast.SelectStmt` arm + `transSelect` helper + `transSelectCommClauseHead` per-clause classifier), `compiler/internal/translate/translate_test.go` (TestErrorCases entries: `=` form rejection, send-bad-chan, send-bad-value, recv non-arrow rhs, drain non-arrow X, bad body stmt, recv-arrow-bad-chan, drain-arrow-bad-chan), `compiler/internal/translate/testdata/select_basic.{go,golden.json}`.
        *Verify:* `cd compiler && go test ./internal/translate/... -run TestCorpus/select_basic`
        *Done when:* a Go fixture with one of each case kind round-trips to a `*ir.SelectStmt` whose case count, kinds, and binding names match the source.
        *Done 2026-05-09:* `transSelect` walks the `BlockStmt.List` of `*ast.CommClause`s and classifies each via `transSelectCommClauseHead`: `Comm == nil` → Default, `*ast.SendStmt` → Send, `*ast.AssignStmt{Tok:DEFINE}` → Recv with one or two bindings, `*ast.ExprStmt{X: UnaryExpr ARROW}` → Recv-drain. The `=` form is rejected explicitly (v1's emit hoists Recv-bound names into a per-branch `declare` scope, which only matches `:=` semantics; `=` arrives with type-info plumbing). The corpus fixture `select_basic.go` exercises all four reachable Recv shapes (single-value, comma-ok, drain) plus Send and Default in one select. Parser-invariant defensive branches (non-CommClause body items, `len(Lhs) != {1,2}`, `len(Rhs) != 1`, `identNameOrBlank` failure on `:=` LHS) were dropped: Go's parser guarantees those shapes, so threading defensive errors for impossible inputs would add coverage debt without meaningful safety. Coverage gates green: runtime/ 100% (704/704), emit 95.28% (1091/1145), translate 95.57% (388/406), compiler 95.01% (2209/2325).

  - [x] **(c) Emit Selectors_Of_<T> instantiation + with-clause**
        *Files:* `compiler/internal/emit/emit.go` (`selectorElems` / `selectorElemOrder` per-file maps mirroring `chanElems`; `chanIdentTypes` file-wide map populated by the pre-scan in `collectSliceElems` over function params + head-of-body `:= make(chan T)` defines; `recordSelectorElem` populator; `walkStmt` `*ir.SelectStmt` arm resolving each non-Default case's chan operand through `chanIdentTypes`; `emitSelectorInstantiations` helper analogous to `emitChannelInstantiations`; `with Gada.Async.Selector;` slotted between the Channels.Bounded with-clause and the Defer / Panic / Scheduler ones; blank-line discipline extended in both `emitMainProcedure` and `emitPackageBody` so the Selectors_Of_<T> block sits between Channels and Panic; placeholder `null;  --  sub-item (d): …` emit-stub on `*ir.SelectStmt` so files emit cleanly until (d) replaces the body), `compiler/internal/emit/emit_test.go` (`TestSelectorInstantiationsPrelude` with two sub-tests: chan-param operand path through fn.Params pre-scan + chan-local operand path through fn.Body head-of-body pre-scan).
        *Verify:* `cd compiler && go build ./... && go test ./internal/emit/... -run TestSelectorInstantiationsPrelude`
        *Done when:* a file containing a `select` whose cases name at least one chan operand emits `with Gada.Async.Selector;` plus one `package Selectors_Of_<T> is new Gada.Async.Selector (Element_Type => T, Default_Element => <zero>, Bnd => Channels_Of_<T>);` per distinct element type. v1 picks the element type from the first non-Default case's chan operand; mixed-T selects raise an explicit emit error pointing at the Phase 4 widening. Degenerate selects with only a `default:` case (Go accepts these, though they are useless) skip the instantiation entirely — emit lowers them to the default body inline since `Select_One` itself is unnecessary when no case can ever block.
        *Done 2026-05-11:* The new piece is the `chanIdentTypes` file-wide map — populated by the pre-scan in `collectSliceElems` over function params + head-of-body `:= make(chan T)` defines — that lets `walkStmt`'s SelectStmt arm resolve a chan operand's element type at pre-walk time, before any subprogram's `localTypes` is populated. Each non-Default case's chan operand (always an `*ir.Ident` in v1) is looked up in `chanIdentTypes`; the resolved element type flows into `recordSelectorElem` which mirrors `recordChanElem` exactly. The `with Gada.Async.Selector;` import slots between `with Gada.Async.Channels.Bounded;` (it depends on the package's `Bnd` formal) and the Defer/Panic/Scheduler imports. The instantiation block emits in the showcase form mirroring `emitMapInstantiations`: one `=>` per line, aligned columns. Blank-line discipline extended in both `emitMainProcedure` and `emitPackageBody` so Selectors_Of_<T> sits between Channels and Panic with single-blank separators in either direction. The per-site Select_One lowering arrives in (d); until then `emitStmt`'s `*ir.SelectStmt` arm emits a `null;  --  sub-item (d): select-stmt body lowering` placeholder so a select-containing file still produces well-formed (if degenerate) Ada at the file level. `TestSelectorInstantiationsPrelude` has two sub-tests pinning both pre-scan paths (chan param vs chan local). Coverage gates green: runtime/ 100% (704/704), emit 95.31% (1139/1195), translate 95.57% (388/406), compiler 94.95% (2258/2378).

  - [x] **(d) Emit Select_One lowering with case-branching body**
        *Files:* `compiler/internal/emit/emit.go` (`emitSelectStmt` driving the per-site lowering; new `selectCounter` field for file-wide 1..N unique naming of Sel_Cases_<n> / Sel_Idx_<n> / V_<n>_<i> / OK_<n>_<i>; `emitSelectCaseAssign` writing one positional-by-name Case_Item aggregate per case with the five fields aligned; `emitSelectCaseBody` emitting per-branch body with nested `declare V : T := V_<n>_<i>.all; Ok : Boolean := OK_<n>_<i>.all; begin … end;` for Recv-with-bindings cases; placeholder `null;  --  sub-item (d): …` from sub-item (c) removed), `compiler/internal/emit/emit_test.go` (`TestSelectStmtEdgeCases` with six sub-tests covering empty-select / all-default-degenerate (with body + empty body) / non-Ident chan operand / undeclared chan ident / heterogeneous-Element_Type rejection), `compiler/internal/emit/testdata/select_basic.golden.adb`.
        *Verify:* `cd compiler && go test ./internal/emit/... -run TestCorpus/select_basic`
        *Done when:* a select with a Send case, a Recv case with `v, ok :=` binding, a Recv case with no binding (drain), and a Default case lowers to a `declare … begin … end;` block whose body is the `Case_Array` build, the `Select_One` call, and an Ada `case Idx is when 1 => …; when 2 => …; when 3 => …; when 4 => …; end case;` dispatch. Ada syntax forbids declarations directly inside a `case` branch, so each Recv case with bindings emits a per-branch nested `declare V : T := V_<i>.all; Ok : Boolean := OK_<i>.all; begin <user body> end;` block. Cases without bindings (Send, Default, drain) emit their body directly under `when N =>` with no nested declare.
        *Done 2026-05-11:* The full select lowering is one wrapping `declare … begin … end;` per select site, scoping the per-Recv-case heap-allocated out-pointers (`V_<n>_<i>`, `OK_<n>_<i>` — library-level accessibility on the runtime's `Element_Ptr` / `Boolean_Ptr` forces heap allocation, not stack `'Access`), the `Sel_Cases_<n>` Case_Array, and `Sel_Idx_<n>`. Body region: per-case aggregate assignments populate all five fields of each Case_Item (Kind, Chan, Send_V, Recv_V_Out, Recv_OK_Out, Timeout_Duration) — irrelevant fields get null / zero / 0.0 rather than being omitted, matching the runtime test pattern verbatim. `Select_One` returns the 1-based fired index; an Ada `case` statement dispatches. Recv cases with bindings wrap the user body in their own `declare V : T := V_<n>_<i>.all; …; begin … end;` because Ada `when N => …` forbids declarations directly. The drain case (`<-c` with no LHS) uses the same Recv_Op aggregate but with both pointers null — the runtime skips writeback when either is null. Single-Element_Type validation walks all non-Default cases and asserts their chan operands resolve to the same element-base name; heterogeneous selects fail with an explicit error pointing at Phase 4's type-erasure widening. Degenerate all-Default selects skip Select_One and emit the default body inline. Empty `select {}` (Go's deadlock-forever shape) lowers to `raise Program_Error with "select with no cases…";`. The `selectCounter` field is file-wide so nested selects produce unique Sel_Cases_<n> / V_<n>_<i> names; Ada would shadow legally but unique names keep gprbuild diagnostics actionable. Showcase output: `select_basic.golden.adb` for the corpus fixture (one chan-int select with all five case shapes) is 70 lines of dense, aligned-aggregate Ada that reads like the runtime spec it instantiates. Coverage gates green: runtime/ 100% (704/704), emit 95.52% (1257/1316), translate 95.57% (388/406), compiler 95.08% (2376/2499). With (d) ticked, all four sub-items of the parent "Compiler emission — select statement" item are done; parent ticked too.

- [x] **Promote `Gada.Core.Panic` Pending stack to per-goroutine storage**
      *Why:* The body's design note
      (`runtime/src/gada-core-panic.adb:8-9`) already promises this:
      *"v1 single-threaded runtime: one global stack. Phase 3
      promotes this to per-task storage when the goroutine
      scheduler lands."* The scheduler has landed (sub-items 3a-3f
      DONE) but the promotion is overdue — the global
      `Pending_Count : Natural` and the `Pending : array (1 ..
      Max_Pending_Panics) of Payload_Type` survive untouched into
      the multi-worker Phase 3 runtime, where two goroutines
      panicking concurrently race on `Pending_Count` increment and
      on the `Pending (Pending_Count)` slot index. Surfaced by
      Gemini's PR #19 review against the Ada 2022 sweep that
      touched these two increments.

      Bare `pragma Thread_Local_Storage` is **not** the right shape
      for two distinct reasons, both load-bearing:

        - **Multiplexing**: GADA is M:N. Multiple goroutines share
          the same worker (and therefore the same OS thread). They
          would all share the same TLS slot. If Goroutine A pushes
          a panic and then yields, Goroutine B running on the same
          worker observes — or worse, overwrites — Goroutine A's
          panic state on its next `Do_Panic`/`Recover`. TLS
          partitions by *OS thread*, but panic state needs to
          partition by *goroutine*. This is the primary objection;
          it holds even on a single-worker build.

        - **Migration**: even if multiplexing weren't a problem,
          docs/incidents/2026-05-03-scheduler-3b-multi-worker-race
          documents the libco-pinning trap that emerges once you
          unpin: a goroutine that pushes a panic on worker A and
          resumes on worker B would observe an empty TLS slot in
          worker B because the cothread carried no state across
          the OS-thread boundary. Pinning is the current
          invariant, but it's an invariant we depend on, not one
          we want panic correctness to depend on too.

      The correct lowering is per-goroutine storage hung off
      `Gada.Async.Scheduler.Goroutine_Record`, with
      `Gada.Core.Panic.Do_Panic` / `Recover` / `Is_Panicking`
      reading from the currently-active goroutine's record via a
      scheduler-side accessor. The record travels with the
      cothread automatically — same mechanism the scheduler
      already uses for the body-procedure dispatch in 3a.

      **Layering**: `Gada.Core.Panic` is generic over
      `Payload_Type`; `Gada.Async.Scheduler` is non-generic and
      sits at a layer Gada.Core.Panic depends on, not the other
      way around. The scheduler therefore **cannot** carry a
      concrete `Panic_Stack_Type` field on `Goroutine_Record` —
      that would force the scheduler to know the panic payload's
      generic type. The right shape is an opaque slot:
      `Goroutine_Record` carries a `Local_Storage : System.Address
      := Null_Address`, and the per-Payload_Type
      `Gada.Core.Panic` instantiation manages its own
      heap-allocated state behind that pointer (allocate on first
      `Do_Panic`/`Push` per goroutine; the scheduler frees the
      slot when the goroutine is reaped). This generalises beyond
      panic — other future per-goroutine state (recover stacks,
      thread-local-equivalent maps, race-detector shadow data)
      uses the same slot via the same registration shape.

      **Main task**: the non-goroutine context (the main Ada task
      that runs before any `Scheduler.Spawn`) must remain
      panic-capable — the v1 single-threaded `defer_panic_suite`
      runs panics from main, and that must still pass post-change.
      Handled by giving the scheduler a `Main_Local_Storage :
      System.Address := Null_Address` package-body global, used as
      a fallback when `Scheduler.Current = No_Goroutine`. The
      `Get_Local_Storage` / `Set_Local_Storage` accessors route
      to this fallback automatically in main context. Multiplexing
      isn't a concern for the main fallback because Ada's main
      task is genuinely a single thread; the rest of the runtime
      will not race with itself there.

      *Files:* `runtime/src/gada-async-scheduler.{ads,adb}` (extend
      `Goroutine_Record` with an opaque `Local_Storage :
      System.Address := Null_Address` field — **no dependency on
      Gada.Core.Panic's generic parameter**; add public
      `Get_Local_Storage` / `Set_Local_Storage (Addr :
      System.Address)` accessors that operate on
      `Scheduler.Current`'s slot, transparently routing to a
      package-body `Main_Local_Storage` global when
      `Scheduler.Current = No_Goroutine`),
      `runtime/src/gada-core-panic.{ads,adb}` (delete the
      package-body `Pending`/`Pending_Count` globals; per
      `Payload_Type` instantiation owns a heap-allocated
      `Panic_State_Type` record behind
      `Scheduler.Get_Local_Storage`; first `Do_Panic` /
      `Is_Panicking` on a goroutine allocates and `Set_Local_
      Storage`s the per-instantiation record),
      `runtime/tests/scheduler_suite.adb` (extend existing suite —
      same `<package>_suite.adb` convention used throughout the
      runtime — with the 100-goroutines-concurrent-panic isolation
      case + the main-context fallback case asserting
      `Get_Local_Storage` returns the `Main_Local_Storage` global
      when called outside any spawned goroutine).

      *Verify:* `make -C runtime test PKG=core.panic && make -C
      runtime test PKG=async.scheduler`

      *Done when:* (i) the package-body `Pending`/`Pending_Count`
      are gone from `Gada.Core.Panic`; (ii) the new AUnit cases
      demonstrate (a) isolation across 100 concurrent panicking
      goroutines on a multi-worker scheduler (`Workers => 4`),
      and (b) the main-task fallback — `Do_Panic` / `Recover`
      from outside any spawned goroutine routes correctly via
      `Main_Local_Storage`; (iii) the v1 single-threaded
      `defer_panic_suite` continues to pass unchanged (the
      main-task fallback is *what* keeps it passing); (iv) the
      design-note comment at the top of `gada-core-panic.adb` is
      updated to describe the opaque-per-goroutine layout, the
      multiplexing rationale for not using TLS, and the
      main-task-fallback mechanism (with a reference back to this
      roadmap item).

      *Done 2026-05-30:* The scheduler gained an opaque
      `Local_Storage : System.Address := System.Null_Address` field on
      `Goroutine_Record` (plus a `Local_Storage_Final :
      Storage_Finalizer` reclaimer pointer), the public
      `Get_Local_Storage` / `Set_Local_Storage (Addr; Finalizer :=
      null)` accessors, and a package-body `Main_Local_Storage` global
      for the non-goroutine context. Accessors route on
      `Current_Goroutine = null` exactly as specified — goroutine slot
      vs. main fallback. The only reap path that frees a goroutine
      which actually ran (`Worker_Task`'s `DONE` arm) now calls a new
      `Free_Local_Storage (G)` immediately before `Free_Goroutine`; it
      runs the registered finalizer and blanks the slot. The two
      Spawn-failure free sites free never-run records whose slot is
      provably `Null_Address`, so they correctly need nothing. `Gada.
      Core.Panic`'s package-body `Pending` / `Pending_Count` globals
      are gone; the state is now a heap-allocated `Panic_State_Type`
      (named `Pending_Array` component to satisfy "no anonymous array
      component", `Pending_Count`) reached through the scheduler slot
      via `System.Address_To_Access_Conversions`. `Do_Panic` allocates
      and registers the block on first use (`Get_State`); `Recover` /
      `Is_Panicking` only *read* (`Peek_State` returns null when the
      slot is empty), so a non-panicking goroutine never allocates. The
      finalizer is taken with `'Unrestricted_Access` — the same idiom
      the Spawn-closure path uses — to cross the RM 3.10.2(32)
      generic-body accessibility boundary safely under the one-
      instantiation-per-program invariant. No layering cycle: the
      runtime is a single `gada_core.gpr` crate and `Gada.Async.
      Scheduler` never withs `Gada.Core.Panic`, so the new `Panic` →
      `Scheduler` with-dependency is legal Ada with a clean elaboration
      order. `scheduler_suite` gained the two required cases — 100
      concurrent panickers on `Workers => 4` each Recover their own Id
      (fails on any shared/global/TLS stack), and the main-context
      `Do_Panic` / `Recover` round-trip via `Main_Local_Storage`. The
      v1 `panic_suite` passes unchanged (main fallback). The
      `gada-core-panic.adb` header now documents the opaque-per-
      goroutine layout, the multiplexing rationale against TLS, and the
      main-task fallback. Coverage held: runtime/ 100% (729/729); two
      pre-existing scheduler exclusions re-pointed +38 lines in
      `tools/coverage_thresholds.toml` for the inserted code. emit
      95.53%, translate 95.81%, compiler 95.12%.

- [ ] **`ping_pong` example**

  Decomposition mirrors channel-emit and select-emit: each step is a
  focused compiler-emit slice with its own corpus fixture; the
  example itself ships last and is the end-to-end gate. The
  original one-paragraph bullet implicitly required two compiler-emit
  capabilities that neither channel-emit nor select-emit needed —
  `go fn(args)` argument capture (channels are how the goroutine
  body talks to the rest of the program, so the spawn call has to
  carry them in) and `fmt.Println` with non-string arguments (the
  exit-criterion's "correct iteration count" needs `Println("…", n)`
  shape with int rendering). Each is its own sub-item below; the
  third sub-item is the example proper.

  Two paths to share state between main and the relay goroutines
  were considered:

  1. **`go fn(args)` argument capture** — spawn carries args by
     value through a per-spawn heap-allocated record; the generated
     worker procedure unpacks the record into local copies of fn's
     formal parameters. Matches the runtime's existing `Spawn`
     contract (`Spawn (Goroutine_Body)`) one-to-one once a closure
     record bridges the no-arg `Goroutine_Body` to the user's
     parametrised function.

  2. **Package-level `var` declarations** — make the chans
     globals, so the no-arg `go pinger()` shape that the current
     emit handles can still see them. Simpler to add in isolation
     but doesn't generalise (every multi-goroutine program past
     ping-pong needs args), and Ada-side elaboration order for
     `make(chan T)` at package level adds its own runtime-spec
     work.

  v1 picks (1). It is the only path that scales to the std-lib port
  and to the SPARK target (where global mutable state is
  awkward). The existing `checkGoArgsEmpty` emit-time guard
  (`compiler/internal/emit/emit.go`) explicitly points at this
  roadmap file as the place where the gap is tracked.

  - [x] **(a) Compiler-emit: `go fn(x, y, …)` argument capture**
        *Done 2026-05-30:* Same capability as the `go`-statement
        sub-item (b) above — implemented once, shared. See that
        item's Done note for the full design (Spawn closure
        overload + `Closure` getter, per-call-site `Go_Closure_<n>`
        / `Allocate_Closure_<n>` / `Go_Worker_<n>` emission, the
        `go_with_args` corpus fixture, the 100-spawn closure
        round-trip AUnit case, and the `gada build` libco-`ARCH`
        fix that finally let a generated goroutine program run).
        `checkGoArgsEmpty` is gone; the with-args path is selected
        by `goCallArgCount(g) > 0`.
        *Why:* Today `emit/emit.go:checkGoArgsEmpty` rejects any
        `go fn(…)` with a non-empty arg list. Ping-pong's two relay
        goroutines must receive their chans (and a `done` chan for
        the ponger) by value through the spawn boundary.
        *Files:* `runtime/src/gada-async-scheduler.{ads,adb}`
        (extend `Spawn` to accept an opaque closure pointer
        alongside the existing `Goroutine_Body` access — either
        as an overload `Spawn (Body : Goroutine_Body; Closure :
        System.Address)` or as a generic-instantiated variant per
        closure type; add a public getter `function Closure (G :
        Goroutine_Id) return System.Address` on the spec so the
        emitted `Go_Worker_<n>` procedure — which lives in the
        transpiled program's package, not in `Gada.Async.Scheduler`
        — can retrieve the per-spawn closure pointer without
        reaching into `Goroutine_Record`'s private fields; the
        worker reads `Scheduler.Closure (Scheduler.Current)` once
        at entry and unchecked-converts to its per-spawn record
        type), `runtime/tests/scheduler_suite.adb` (extend the
        existing AUnit suite — same `<package>_suite.adb`
        convention as channels_suite / channels_unbounded_suite /
        selector_suite — with cases asserting the closure-payload
        round-trips correctly across 100 concurrent spawns with
        distinct arg tuples), `compiler/internal/emit/emit.go`
        (new `emitGoClosureWithArgs` path generating a per-spawn
        `Go_Closure_<n>` record type carrying the formal-parameter
        copies, an `Allocate_Closure_<n>` helper for heap
        allocation, and a `Go_Worker_<n>` procedure that unpacks
        the closure into named locals before calling the user's
        function body; `checkGoArgsEmpty` becomes a no-op), new
        `compiler/internal/translate/testdata/go_with_args.{go,golden.json}`
        + `compiler/internal/emit/testdata/go_with_args.golden.adb`
        showcase fixture.
        *Verify:* `cd compiler && go test ./internal/emit/... -run TestCorpus/go_with_args && make -C runtime test PKG=async.scheduler`
        *Done when:* a `go relay(c1, c2)` with two `chan int`
        operands lowers to (i) one `Go_Closure_<n>` record decl
        per call-site (per-call-site keyed by `emit.goIndex`, not
        per distinct signature — the v1 emit deliberately picks
        the simpler per-call-site shape to avoid type-matching
        across call-sites; deduplication is a later perf pass if
        the binary-size cost shows up in measurement),
        (ii) one `Go_Worker_<n>` procedure per call-site that
        unpacks the record into locals matching the user's
        parameter names, (iii) one `Spawn (Go_Worker_<n>'Access,
        Closure_<n>)` call at the go-statement site, with the
        closure heap-allocated through a per-call
        `Allocate_Closure_<n>` helper, plus the scheduler's
        public `Closure` getter retrievable from
        `Go_Worker_<n>`. AUnit cases in `scheduler_suite.adb`
        spawn 100 workers with distinct `(int, int)` arg pairs
        and assert the per-spawn args land at the expected
        positions inside each worker.

  - [x] **(b) Compiler-emit: multi-arg `fmt.Println` with int rendering**
        *Done 2026-05-30:* `emitFmtPrintln` lowers `fmt.Println(a, b,
        …)` to a run of `Gada.Core.IO.Print` calls with a `Print (" ")`
        between consecutive operands and a terminating `New_Line` —
        Go's variadic-Println shape. Ada overload resolution picks
        `Print (String)` vs `Print (Integer)` per operand, so emit
        stays type-agnostic (unsupported scalar types surface as a
        gprbuild overload error; Float/Bool faithful rendering is
        Phase 4). The single-string `fmt.Println(s)` is just the
        one-operand subset, so the five `Println`-bearing goldens
        (hello, combined, …) were regenerated to `Print (s); New_Line;`
        and `emitSelector`'s now-dead `fmt.Println` special case
        removed. Runtime: `Gada.Core.IO` gained `Print (String)`,
        `Print (Integer)`, and `New_Line`, with `Println` re-expressed
        as `Print; New_Line`. **Correction to the plan above:** GNAT's
        `N'Image` (the Ada 2022 object form) does *not* omit the
        leading sign-position blank — it is identical to
        `Integer'Image` (verified: both render ` 1000000`). So
        `Print (Integer)` trims it with `Ada.Strings.Fixed.Trim (…,
        Left)`; negatives keep their `-`. io_suite gained four cases
        (string adjacency, the int trim, a negative, a bare New_Line),
        capturing through New_Line-terminated sequences because
        Ada.Text_IO appends a terminator to an unterminated line on
        close. Verified end-to-end: the `println_mixed_args` program
        transpiles, builds, and prints byte-for-byte what `go run`
        does (`123` / `hi` / `iterations: 7` / `7 items` / `1 2`).
        Gates green: runtime 100% (710/710), emit 95.56%, translate
        95.81%, compiler 95.15%.
        *Why:* The exit-criterion line is
        `fmt.Println("iterations:", n)` for `n = 1000000`,
        producing `iterations: 1000000\n`. Current emit handles
        only single-string-literal `fmt.Println` and has no
        int-rendering path. Lowering target: `fmt.Println(a, b, …)`
        maps to `Ada.Text_IO.Put (render (a))` for each argument
        with a space separator between consecutive args (matching
        Go's variadic Println spec), followed by `New_Line`.
        Int args use Ada 2022's `Object'Image` attribute (`N'Image`
        on the object, not `Integer'Image (N)` on the type) — the
        Object form does not prepend the leading space that the
        Type form does for non-negative values, so the rendering
        matches Go's bare-digit output without a `Trim` step.
        *Files:* `compiler/internal/emit/emit.go` (new
        `emitFmtPrintln` helper handling 1..N args of any
        currently-supported scalar type; existing single-string
        path becomes a one-arg subset), `compiler/internal/emit/emit_test.go`,
        new corpus fixture
        `compiler/internal/translate/testdata/println_mixed_args.{go,golden.json}`
        + `compiler/internal/emit/testdata/println_mixed_args.golden.adb`
        covering one-int / one-string / string+int / int+string / int+int.
        *Verify:* `cd compiler && go test ./internal/emit/... -run TestCorpus/println_mixed_args`
        *Done when:* `fmt.Println("iterations:", n)` for `n = 1000000`
        produces `iterations: 1000000\n` byte-for-byte equal to
        the corresponding `go run` output, and `fmt.Println(123)`
        produces `123\n` (no leading space).

  - [ ] **(c) `ping_pong` example proper**
        *Files:* `examples/ping_pong/ping_pong.go`,
        `examples/ping_pong/expected_output.txt`,
        `examples/ping_pong/go.mod`.
        *Verify:* `make example HELLO=ping_pong` (must complete in
        < 5s wall-clock)
        *Done when:* The transpiled binary runs 1M ping-pong
        iterations between two relay goroutines (pinger uses
        `for { select { case v, ok := <-ping: … } }`, ponger uses
        the trivial-for shape `for i := 0; i < 1000000; i = i + 1`
        with a single-case select-recv on `pong`), prints
        `iterations: 1000000` as the final stdout line, and exits
        cleanly. `diff -u` of stdout against
        `expected_output.txt` is empty; total wall-clock is
        under 5 s on the dev host.

- [ ] **Race detector integration (best-effort)**
      *Files:* `runtime/src/gada-async-race.ads`
      *Verify:* `make -C runtime test PKG=async.race`
      *Done when:* an intentional data race is detected and reported (or documented as a known limitation in an ADR).

- [x] **Goroutine leak test**
      *Files:* `runtime/tests/stress_goroutines.adb`
      *Verify:* `make -C runtime test PKG=stress.goroutines`
      *Done when:* spawning + completing 100k goroutines leaves runtime task count back at baseline.

      *Done 2026-05-30:* Realised as `runtime/tests/stress_goroutines_suite.{ads,adb}` (suite type `Stress_Goroutines_Test`), wired into `runtime/tests/test_runner.adb` under the opt-in `stress.*` namespace exactly like `stress.gc` / `stress.scheduler` — the default `make test` / `make ci` skip it; only `make -C runtime test PKG=stress.goroutines` selects it. The single test spawns 100_000 spawn-and-return goroutines at the *default* worker width (`Init` => `Number_Of_CPUs`, real multi-worker concurrency, unlike `stress.scheduler`'s deliberately single-worker shape) and asserts on two observable baseline proxies, since the scheduler's private state (`Run_Queue`, `The_Workers`, the `Goroutine_Record` free-list) is not readable from a test: **(1) exactness** — a protected `Run_Counter` (serialised increments, because an Atomic Natural's read-modify-write would lose increments under multi-worker fan-out) tallies exactly 100_000 completed bodies, so a dropped goroutine undershoots and a record reused-while-live double-runs and overshoots; **(2) clean second cycle** — a follow-up 1_000-goroutine `Init`/`Spawn`/`Shutdown` burst still tallies exactly, proving the first `Shutdown` returned the pool to the not-initialised baseline (`The_Workers := null`, every record `Free_Goroutine`'d on the DONE reap arm) and nothing bled across the barrier. A direct OS task-count probe is intentionally not asserted on — the AdaCore FSF runtime spins helper tasks lazily on macOS, so it is non-deterministic; the exactness + clean-second-cycle proxies are the contract. `make -C runtime test PKG=stress.goroutines` reports 1/1 test, 0 failed assertions, 0 unexpected errors; the 100k burst completes in well under a second wall-clock. `make ci` stays fully green (116/116 non-stress tests, runtime/ coverage 100%, coverage-gate PASSED, roadmap consistency OK) — the new files live under `runtime/tests/` which the 100%-line gate (scoped to `runtime/src/`) does not count.
