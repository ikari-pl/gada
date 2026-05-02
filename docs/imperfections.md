---
type: note
title: Architectural imperfections to deal with later
created: 2026-05-02
tags: [tech-debt, gaps, todo]
---

# Architectural imperfections to deal with later

Running list of design and implementation rough edges we have
*deliberately* accepted in order to ship phases on schedule. Not a
bug tracker — bugs go in GitHub Issues. Items here are either:

- known-acceptable trade-offs (we picked X over Y; Y still has merit
  and would be reconsidered post-1.0),
- mitigations rather than fixes (we papered over a deeper issue and
  said so),
- enabling work for future phases (a phase lays groundwork; the
  finished shape needs later-phase work).

Every entry has: a one-line summary, *Where* (file or boundary),
*Why not fixed yet* (schedule, scope, dependency), *What "fixed"
looks like* (concrete success condition), and *Tracker* (GitHub
Issue number when filed, roadmap phase reference, or "none").

When an imperfection is resolved, move the entry to the *Resolved*
section at the bottom with the resolution commit / PR reference.

## Active

### libgc switches must be redeclared in every executable project
*Where:* `runtime/tests/aunit_harness.gpr` re-declares `GC_Switches := external_as_list ("GADA_GC_LDFLAGS", " ") & ("-lgc");` independently from `runtime/gada_core.gpr`.
*Why not fixed yet:* GNAT does not propagate `Linker.Default_Switches` from imported library projects to the importing executable; gada_core (a static library) emits the warning *"Linker switches not taken into account in library projects"* if you try, so the package was removed there. Each new executable project that links gada_core has to redeclare GC_Switches.
*What "fixed" looks like:* a shared `gada_link_options.gpr` *abstract* project that all executables `with` and inherit from; or libgc moved to a `pragma Linker_Options` strategy in the Ada source that doesn't need pkg-config-driven path resolution.
*Tracker:* file when the second executable project (Phase 3 scheduler test harness or Phase 4 reflection test harness) shows up.

### `Gada.Core.Memory.Initialize` is per-test, not per-elaboration
*Where:* `runtime/tests/memory_suite.adb` calls `Gada.Core.Memory.Initialize` at the start of every test. Real user code would have to do the same.
*Why not fixed yet:* libgc's `GC_init` is documented as idempotent so repeated calls are safe; the proper Ada-elaboration call site for `Gada.Core.Memory` body to invoke `Libgc.GC_Init` automatically hasn't been wired. `Gada.Core` carries `pragma Elaborate_Body` already (Phase 0) but the body is empty.
*What "fixed" looks like:* `Gada.Core.Memory` body's elaboration calls `Libgc.GC_Init`; tests / user code never touch `Initialize` directly. Public `Initialize` becomes optional / no-op for already-initialized state, retained only for explicit re-init in test setups.
*Tracker:* Phase 3 (concurrency runtime needs deterministic GC startup before goroutine creation).

### Goroutine-stack registration with libgc is not wired
*Where:* `runtime/src/gada-core-memory.ads` exposes only `Initialize`/`Allocate`/`Allocate_Atomic`/`Collect`/`Heap_Size` — no `Register_Goroutine_Stack` / `Unregister_Goroutine_Stack`.
*Why not fixed yet:* Phase 2 deliberately scoped `Gada.Core.Memory` to single-threaded allocation. Phase 3 (`roadmap/03-concurrency.md`) owns the libco scheduler binding and the matching libgc stack-registration contract. ADR-0003 §3 + ADR-0004 already specify the API shape.
*What "fixed" looks like:* `Memory.Register_Goroutine_Stack` calls libgc's `GC_set_stackbottom` and `Memory.Unregister_Goroutine_Stack` undoes it; libco coroutine stacks register as alternate roots via `GC_push_all_stack` from a marker hook.
*Tracker:* `roadmap/03-concurrency.md`.

### macOS Sequoia (Darwin 25+) duplicate-`LC_RPATH` strip workaround
*Where:* `runtime/tests/run_tests.sh` (Phase 0); `compiler/cmd/gada/build.go` (Phase 1) — both post-process the produced executable with `install_name_tool -delete_rpath` to remove a second `LC_RPATH` load command that GNAT 15 + gprbuild 25 emit.
*Why not fixed yet:* upstream bug in the GNAT/gprbuild pair; macOS dyld rejects duplicate `LC_RPATH` entries as of Darwin 25 and aborts the binary at exit-134 before `main()` runs. We paper over with the strip; on Linux and earlier macOS the strip is a no-op.
*What "fixed" looks like:* GNAT 15.x or 16 fixes the emit; we delete both workarounds.
*Tracker:* none — file as an Alire / Adacore upstream report.

### Anonymous-access-allocator warning suppressed file-wide in `test_runner.adb`
*Where:* `runtime/tests/test_runner.adb` line 1 — `pragma Warnings (Off, "use of an anonymous access type allocator");` (no matching `Warnings (On, ...)`).
*Why not fixed yet:* AUnit's `Add_Test (Result, new Suite_Test)` is the framework-documented pattern but trips GNAT 15's `-gnatw_a` (added in a recent GNAT). Refactoring against AUnit isn't worth a per-call workaround. Suppression is file-wide because there's no `On` pragma — narrowing to per-call requires more pragma noise than it saves.
*What "fixed" looks like:* AUnit ships an explicit named-access constructor, GNAT relaxes the warning for AUnit-shaped allocators, or the test harness moves to a different framework. Phase 4 (interfaces & reflection) may rework the test harness — revisit then.
*Tracker:* none.

### `make ci` doesn't depend on `make bootstrap`'s system-lib gate
*Where:* top-level `Makefile`; `bootstrap` runs the `pkg-config bdw-gc` check, but `ci` (lint → test → coverage → coverage-gate → roadmap-check) does not depend on `bootstrap`. CI workflow installs `libgc-dev pkg-config` explicitly via apt, so the apt step is the load-bearing gate; on a dev box that hasn't run bootstrap, `make ci` will fail with a less-actionable link error.
*Why not fixed yet:* `make ci` running `bootstrap` every time is wasteful (re-fetches Go modules, re-runs `alr build`); making it depend on a *check-only* sub-target (e.g. `_bootstrap-check-bdw-gc`) is the right shape but wasn't in scope for Phase 2 sub-item (a).
*What "fixed" looks like:* `_bootstrap-check-bdw-gc` extracted as its own .PHONY target; `ci` (and probably `test`) depends on it; `bootstrap` keeps it as a dependency too. A single source of truth for "is libgc reachable".
*Tracker:* Phase 2 follow-on; ~30 min of work.

### Brew Cellar version-specific path baked into rpath on Apple Silicon
*Where:* `pkg-config --libs bdw-gc` returns `-L/opt/homebrew/Cellar/bdw-gc/8.2.12/lib -lgc`. The linker resolves `libgc.dylib` against the version-specific Cellar path; produced binaries record this path in their LC_RPATH / install_name. A `brew upgrade bdw-gc` re-paves `/opt/homebrew/Cellar/bdw-gc/8.2.12/` and may leave already-built binaries pointing at a missing path.
*Why not fixed yet:* default Homebrew behavior. Apple Silicon hosts don't add `/opt/homebrew/lib` to the linker's default search list, so pkg-config emits an absolute Cellar path. The version-agnostic `/opt/homebrew/lib/libgc.dylib` symlink Brew provides isn't picked up automatically.
*What "fixed" looks like:* either rewrite the resulting binary's rpath/install_name to use the symlink (`install_name_tool -change`), use `pkg-config --libs --static bdw-gc` to force static linking (avoids the rpath issue entirely), or write a small post-link step that runs `install_name_tool` on the `libgc.dylib` reference.
*Tracker:* file when a brew upgrade actually breaks a previously-built binary.

### Stress-test heap-size ceiling is a magic number
*Where:* `runtime/tests/memory_suite.adb` `Max_Heap : constant := 2 * Storage_Count (N_Allocs) * Alloc_Size;` — 128 MB upper bound after 1M × 64 B atomic allocations.
*Why not fixed yet:* libgc retains capacity after `Collect`; the 2× factor was chosen empirically as "comfortably above measured peak". Different platforms or future libgc versions may overshoot or fall short of this constant.
*What "fixed" looks like:* the ceiling derives from a `pkg-config --variable=` of bdw-gc's heap-growth tuning, *or* the test asserts only the relative invariant (`Heap_Size_After_Collect <= Heap_Size_At_Peak`) and a separate environment-aware test asserts the absolute bound.
*Tracker:* file if the test ever flakes on CI.

### `Libgc` in the package name couples the abstraction to its implementation
*Where:* `runtime/src/gada-core-memory-libgc.ads` — private child named `Libgc`.
*Why not fixed yet:* explicitly named after the v1 implementation. If/when ADR-0005's four succession criteria are met and a custom Ada GC ships, the private child either renames (to e.g. `Native` or `Bdw`) or coexists with the new backend.
*What "fixed" looks like:* the post-1.0 supersession ADR replaces this child; we either rename or split.
*Tracker:* `docs/adr/0005-libgc-binding-via-pkgconfig.md` succession criteria.

### `-lgc` duplicates on the link command on macOS Homebrew
*Where:* `tests/aunit_harness.gpr` — `external_as_list (...) & ("-lgc")` produces `... -L/opt/homebrew/Cellar/bdw-gc/8.2.12/lib -lgc -lgc` because pkg-config's output already ends in `-lgc`.
*Why not fixed yet:* the trailing `-lgc` is the fall-through for hosts where pkg-config returns nothing (direct `gprbuild` invocations outside `make` on Linux/BSD with libgc in default paths). Duplicating the flag is harmless to the linker. Conditional logic in GPR to suppress when pkg-config provides `-lgc` is more work than it saves.
*What "fixed" looks like:* GPR ternary on `external_as_list (...)'Length > 0`, *or* trust pkg-config exclusively and move the `-lgc` fall-through into `runtime/Makefile` where shell ergonomics make conditionals easy.
*Tracker:* none (cosmetic).

### clang `-Woverriding-deployment-version` warning noise on every Ada compile
*Where:* every gprbuild invocation on macOS Sonoma (15) and later → "overriding deployment version from '16.0' to '26.0' [-Woverriding-deployment-version]" once per Ada source compiled.
*Why not fixed yet:* GNAT 15 emits `-mmacosx-version-min=10.9` (or 16.0 in newer pre-releases); host is Darwin 26. Harmless but each line spam-fills the log and hides real warnings.
*What "fixed" looks like:* `Compiler.Common_Switches` adds `-mmacosx-version-min=$(sw_vers -productVersion | cut -d. -f1).0` (computed in the Makefile, exported as an external variable, consumed in the gpr). Or just suppress the clang warning class.
*Tracker:* none (cosmetic).

### Phase 2 sub-items (b) + (c) had to ship in one commit
*Where:* `runtime/src/gada-core-memory{,-libgc}.{ads,adb}` — Ada's parent-child semantics require the parent spec to exist for a private child to compile. The roadmap decomposed (b) Libgc bindings and (c) public interface as separate sub-items, but they had to land together because each commit must compile and not regress coverage.
*Why not fixed yet:* this is a one-time procedural artefact, not an ongoing cost. The decomposition served its planning purpose (made the Files / Verify / Done-when crisp per sub-item) even though the commit boundary collapsed.
*What "fixed" looks like:* future per-task decomposition checks for parent-child Ada coupling and groups co-mandatory units into a single sub-item upfront.
*Tracker:* none (process note for the next agent).

### `Gada.Core.Maps` iteration order is deterministic, not Go-random
*Where:* `runtime/src/gada-core-maps.adb` `First` walks slot 0 forward; `Next` walks the slot index forward — same order every run.
*Why not fixed yet:* a per-program startup-time random seed is the right design but the seed source belongs to `Gada.Core` runtime startup, which is wired by Phase 3's scheduler init. Per-instance entropy from libgc-allocated addresses was prototyped (and worked) but added two test-time non-determinism problems for the runtime/ 100% coverage gate (advance branches that fire only on certain seeds). For v1 the contract is "any single observable order is unspecified" — deterministic-per-test is a *stronger* guarantee that doesn't break Go's invariant ("programs must not depend on order").
*What "fixed" looks like:* `Gada.Core.Random` exposes a per-program seed initialised at runtime startup (Phase 3's `Gada.Async.Initialize`); `Maps.First` reads it and uses it to rotate the starting offset by a constant per-instance amount. The "advance past empty prefix" branches fire deterministically per (seed, map-instance) pair, so coverage holds.
*Tracker:* roadmap/03-concurrency.md (scheduler startup) — wire `Gada.Core.Random` and consume it in `Gada.Core.Maps`.

### Maps `Probe_For_*` and `First`/`Next` use unconditional `loop` for coverage-gate cleanliness
*Where:* `runtime/src/gada-core-maps.adb` — `Probe_For_Lookup`, `Probe_For_Insert`, `First`, `Next` all use `loop ... end loop;` with internal `return`s instead of `for` / `while` loops with bounded iteration counts.
*Why not fixed yet:* `for I in 0 .. M.Cap - 1 loop` instruments the natural loop exit (the last `Idx + 1` increment past the bound) as a reachable line; with the load-factor invariant guaranteeing the inner `return` always fires before exhaustion, that exit is dead code that the runtime/ 100% coverage gate would flag. Unconditional `loop` makes the post-loop control flow structurally absent — gcov sees no fall-through line to instrument.
*What "fixed" looks like:* a coverage exclusion mechanism (`-- LCOV_EXCL_LINE` or equivalent recognised by `tools/coverage_gate.sh`) that lets the source declare "this line is unreachable by invariant; do not count it"; the loops can then read more naturally as `for ... loop`.
*Tracker:* none (cosmetic; current code is correct and well-commented about the invariant).

### Slice-of-slice element types are rejected at emit
*Where:* `compiler/internal/emit/emit.go` — `elemBaseName` rejects `*ir.SliceType` with "unsupported slice element type"; the IR + translate layers accept `[][]int` cleanly.
*Why not fixed yet:* a recursive instantiation chain (`Slices_Of_Integer` *then* `Slices_Of_Slices_Of_Integer is new Gada.Core.Slices (Element_Type => Slices_Of_Integer.Slice);`) needs dependency-ordered emission of *multiple* `package … is new …` declarations, plus an Ada-identifier-safe naming scheme (no dots in the suffix). Phase 2's golden corpus does not exercise the shape; shipping the rejection lets the surface ship clean.
*What "fixed" looks like:* `elemBaseName` recurses through nested `SliceType`s producing flat-underscore identifiers (e.g. `Slices_Of_Slices_Of_Integer`); `collectSliceElems` topologically sorts the order list so dependencies emit first; one new fixture per nesting depth that lands in the golden corpus.
*Tracker:* none yet — escalate when a Phase-2-or-later corpus example needs it.

### Go parameter mutation requires hoisting; emit currently rejects
*Where:* `compiler/internal/emit/emit.go` — Go's `s = append(s, x)` on a function parameter `s` would translate to assigning a value to an Ada `in`-mode parameter, which Ada disallows. The Phase 2 fixture `slice_append.go` was rewritten from `s = append(s, x); return s` to `return append(s, x)` to dodge the issue.
*Why not fixed yet:* needs a per-function pre-scan that detects "this parameter is later assigned to" and emits a local-variable shadow at the head of the declarative region (e.g. `S_Local : … := S;`) plus a name-rewrite of subsequent body references. The transformation is mechanical but adds a second pass over each function body.
*What "fixed" looks like:* the original `s = append(s, x)` shape compiles cleanly; the rewrite becomes a documented emit pass with its own unit test; the slice_append fixture restores its idiomatic Go shape.
*Tracker:* none yet — Phase 3 will need similar hoisting for goroutine-captured locals.

## Resolved

### In-tree bench harness scaffolding pending
*Resolved:* shipped 2026-05-02 alongside `Gada.Core.Memory.Total_Bytes_Allocated`. `runtime/bench/{gada_bench.{ads,adb}, memory_bench.{ads,adb}, slices_bench.{ads,adb}, maps_bench.{ads,adb}, bench_runner.adb, gada_bench_harness.gpr, run_benchmarks.sh}` in place; `runtime/PERF.md` ships with the Phase 2 baseline table; `make bench` (and `make -C runtime bench`) runs the suite. Sub-nanosecond `ns/op` formatting (`Long_Float`, 2 decimals when < 10) added so address-overlay-fast ops don't truncate.
