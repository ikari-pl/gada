# GADA runtime static stack-usage ledger

Per-function static-stack-usage report for the GADA runtime, sibling
to [`runtime/PROOF.md`](PROOF.md) and [`runtime/PERF.md`](PERF.md).
Addresses hazard #8 ("no stack overflow detection") from the Phase 3
sub-item 3a concurrency retro:
[`docs/journal/2026-05-03-async-context-concurrency.md`](../docs/journal/2026-05-03-async-context-concurrency.md).

- **Bar:** every single Ada function frame ≤ **8192 bytes** = 1/8 of
  the libco-allocated 64 KiB goroutine stack (per
  [`docs/adr/0004-scheduler-libco-for-v1.md`](../docs/adr/0004-scheduler-libco-for-v1.md)).
  Below 1 KB ideally; over 8 KB fails the gate. The 1-KB target keeps
  call-chain headroom comfortable.
- **What this catches:** any single function that uses too much stack
  on its own. A 32-KB local array in a goroutine body would burn half
  the stack in a single frame.
- **What this does *not* catch:** call-chain accumulation. A 64-deep
  recursion of 1-KB frames overflows just as hard. Per-call-chain
  analysis (gnatstack-equivalent) is a follow-up; tracked as a
  TODO in [`tools/stackcheck.sh`](../tools/stackcheck.sh).
- **CI gate:** `tools/stackcheck.sh` exits non-zero on any over-
  threshold function. Wire into `make ci` once Phase 3 lands; for now
  it is a developer-side check (same shape as `tools/prove.sh`).

Methodology: `tools/stackcheck.sh` invokes `gprbuild -P
gada_core.gpr -f -cargs -fstack-usage`, parses every `.su` file
under `runtime/obj/`, and reports the top-N stack-using functions.
Numbers shown are from a representative run on the dev host
(darwin/arm64, GNAT 15.1.2 from the Alire `gnat_native` crate).
CI runs (Linux x86_64) will produce slightly different absolute
numbers but should hold the same shape.

## Phase 2 baseline (2026-05-03)

20 functions analysed across the runtime library; sum of all frames
= **528 bytes**, worst single frame = **64 bytes**, gate = 8192
bytes. Status: **PASSED**.

| Bytes | Qualifier | Symbol | Notes |
|---:|---|---|---|
|  64 | static | `<built-in>:Tdefer_blockCFD` | Compiler-generated defer-block trampoline (cleanup-finalisation-deallocation). Smallest stable size for a `Limited_Controlled` finalisation thunk. |
|  48 | static | `<built-in>:defer_blockIP` | Compiler-generated defer-block initialization. |
|  32 | static | `Allocate_Atomic` | `runtime/src/gada-core-memory.adb:28` — libgc atomic alloc thunk. |
|  32 | static | `Allocate`        | `runtime/src/gada-core-memory.adb:21` — libgc traced alloc thunk. |
|  32 | static | `Println`         | `runtime/src/gada-core-io.adb:12` — minimal `Ada.Text_IO.Put_Line` wrapper. |
|  32 | static | `Finalize`        | `runtime/src/gada-core-defer.adb:9` — defer-cleanup body. |
|  16 | static | `Hash_Long_Float` | `runtime/src/gada-core-hash.adb:31` — `Ada.Unchecked_Conversion` instance + multiply. |
|  16 | static | `Hash_Integer`    | (Phase 2.5 SPARK opt-in.) |
|  16 | static | `Hash_Boolean`    | (Phase 2.5 SPARK opt-in.) |

(Top 9 shown; full report from `tools/stackcheck.sh --top 50`.)

The numbers are dominated by compiler-emitted defer-block trampolines
because real runtime work delegates to libgc/libco/`Ada.Text_IO` —
none of which contribute to the *Ada* stack frame visible to gcov.
This is an honest baseline: Phase 2 runtime functions are tight, the
stack budget is essentially unspent, and any future regression that
adds a 4 KB frame to (say) `Map_Insert` would be visible immediately.

## What changes in later phases

- **Phase 3 (scheduler):** `Goroutine_Trampoline` and the worker-task
  body land. Likely adds 64–256 bytes per frame (protected-object
  in-out parameter copy, exception handler block). Re-run after
  sub-item 3a-merge and update this table.
- **Phase 4 (channels/select):** select bodies have multiple `case`
  arms which the GNAT codegen sometimes lifts to a stack-allocated
  jump table. Watch for >256-byte regressions on `Select_*` thunks.
- **Phase 6 (defer/panic full):** Phase 2 defer is `Limited_Controlled`
  finalisation chains; if Phase 6 widens this to multi-deferred-block
  trampolines, the per-frame size might double or triple. Still
  expected well under 1 KB.

## Per-call-chain analysis (deferred)

Per-function frames are a soft signal. The actual stack-overflow
hazard is **per-call-chain**: 64 deep recursive frames of 1 KB
overflows the 64 KiB libco stack. Computing this requires the GCC
call graph (`-fcallgraph-info=su,da`) plus a graph-traversal pass
to find the longest-path stack sum.

This is left as a TODO until either: (a) some Phase 3+ regression
brings a single-function frame over 1 KB and we want better
attribution, or (b) the compiler starts emitting recursive Go code
where the recursion depth is bounded by user input. Both can wait;
neither is blocked by today's runtime.

## How to update this ledger

1. Run `tools/stackcheck.sh --top 50 --report-only` to get fresh
   numbers without failing on threshold breaches.
2. Update the dated section above with the new top-N table.
3. If the worst single frame is over 1 KB, add a "Why" sub-row
   explaining (typically: large `case` jump table, large local
   record, deep RAII chain).
4. If a regression pushes a frame over 8192 bytes, **do not** raise
   the gate; either refactor the function to allocate the offending
   structure on the heap, or document a per-function exception
   following the [`runtime/PROOF.md`](PROOF.md) "justifications"
   pattern (rejected at PR review unless documented).
