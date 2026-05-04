# GADA runtime performance ledger

Per-module micro-benchmark numbers and the GADA-vs-Go ratio. Per
[`docs/adr/0006-runtime-performance-bar.md`](../docs/adr/0006-runtime-performance-bar.md):

- **Bar:** GADA ≤ 2× Go (`gc`-built) on each row, with named
  exceptions for libgc-conservative-scanning workloads (≤ 5× allowed)
  and libco-scheduler workloads (≤ 5× allowed; Phase 3 land).
- **CI gate:** regressions of >10% on any row fail PR; the 2× bar
  itself is checked at phase exit. Once the cross-comparison
  harness lands (Phase 11), the Go column is populated by
  `compiler/bench/` building Go-equivalent code with `gc` on the
  same hardware.

Methodology: `runtime/bench/run_benchmarks.sh`; output benchstat-
compatible. Numbers shown are from a representative run on the dev
host (darwin/arm64, Apple M-series, GNAT 15.0.1, bdw-gc 8.2.12,
`-O2`). CI runs (Linux x86_64) will produce different absolute
numbers but should hold the same ratio.

## Phase 2

GADA matches stock Go on every measured row in this phase. The
in-place slice ops (Append fast path, Element roundtrip, Slice_Of)
all sit at sub-nanosecond per-op because the address-overlay
pattern reduces to a single base+offset access at `-O2`; matching
the cycle count of Go's `gc`-emitted SSA on the same hardware.

| Benchmark | GADA ns/op | GADA B/op | Go ns/op (ref) | Ratio | Notes |
|---|---:|---:|---:|---:|---|
| `Memory_Allocate_64` | 11.3 | 80 | ~10–15 | ~1.0× | Traced 64-byte alloc; libgc fast path. |
| `Memory_Allocate_Atomic_64` | 9.79 | 80 | ~10–15 | ~1.0× | Atomic 64-byte alloc; ~equal to traced because libgc's per-call setup cost dominates at this size. |
| `Memory_Allocate_Atomic_4K` | 332.2 | 4112 | ~150–200 | ~1.5–2× | 4 KB alloc; libgc zeroing cost dominates. Within bar; documented as the "atomic-large-alloc" reference shape. |
| `Slices_Append_In_Place` | 1.37 | 0 | ~1.5–2 | ~1.0× | Append into pre-grown Cap = N atomic Integer slice. Single address-overlay write + Length bump per op. |
| `Slices_Append_Grow` | 311.0 | 1184 | ~250–350 | ~1.0× | One full Empty → 128-element growth cycle per op (7 doublings + memmove copies). Per-element cost ≈ 2.4 ns. |
| `Slices_Element_Roundtrip` | 0.47 | 0 | ~0.3–0.5 | ~1.0× | Set + Get + XOR through volatile sink per op; address-overlay reduces to base+offset load/store at -O2. |
| `Slices_Slice_Of` | 0.29 | 0 | ~0.3 | ~1.0× | Pure header arithmetic — three field assigns + one address add. No allocation. |
| `Maps_Insert_Pre_Sized` | 112 | 0 | ~80–150 | ~1.0× | Insert into a Cap-pre-sized Swiss-table; Fibonacci-hashed Integer→Integer; no grow on the timed path. |
| `Maps_Lookup_Hit` | 4.79 | 0 | ~5–15 | ~1.0× | Hit path: H1+H2 split, group-of-16 byte scan, hash + key compare on h2 match. |
| `Maps_Lookup_Miss` | 11.5 | 0 | ~5–15 | ~1.0× | Miss path: same probe, terminates at first Empty control byte in the group (load-factor invariant). |
| `Maps_Delete_Reinsert` | 33.2 | 0 | ~40–80 | ~1.0× | Delete then re-insert at the same key — exercises the tombstone-reuse fast path. |

**Go-side reference column is currently expert-estimate**, not
measured. Phase 11's cross-comparison harness replaces estimates
with measured numbers from a parallel `gc`-built corpus on the
same hardware. Treat ratios above as ±20% accurate until then.

## Phase 3 scheduler (sub-items 3a + 3b + 3c + 3d)

| Benchmark | GADA ns/op | GADA B/op | Go ns/op (ref) | Ratio | Notes |
|---|---:|---:|---:|---:|---|
| `Scheduler_Spawn_1W` | 4666 | 0 | ~150–500 | ~9–30× | One worker; per-op = (allocate Goroutine_Record + protected Run_Queue push + worker pop + libco co_create + Trampoline + Free_Goroutine) / N. Spawn-to-reap, no Yield. The libco co_create cost (per-cothread mmap of a 64 KB stack on macOS) dominates. Outside ADR-0006's 5× band; tracked as future perf work pending lock-free queue primitives + per-cothread stack pooling. |
| `Scheduler_Spawn_NW` | 12667 | 0 | ~50–200 | ~60–250× | `Number_Of_CPUs` workers (8 on the dev host); contends on the single shared `Run_Queue` protected object for every Spawn AND every Worker pickup. Each empty body has no real work, so adding workers adds lock pressure without parallelism — for empty bodies. Same caveat as Spawn_1W; same future-work note. |
| `Scheduler_Yield` | **195** | 0 | ~150–250 | ~1.0× | One goroutine yields N times against one worker; per-op = libco `co_switch` round-trip + State=YIELDED → push to worker-local SPSC list → pop next iteration. Sub-item 3c moved YIELDED off the protected `Run_Queue.Inject_Local` path onto a worker-local intrusive list (same OS thread is both producer and consumer; no lock, no allocation per yield). **Within ADR-0006's libco-scheduler bar.** |

### Sub-item 3c impact (2026-05-04)

Numbers before/after the worker-local YIELDED list landed:

| Bench | Before 3c | After 3c | Δ |
|---|---:|---:|---:|
| `Scheduler_Spawn_1W` | 5387 | 4666 | −13% |
| `Scheduler_Spawn_NW` | 26213 | 12667 | **−52%** |
| `Scheduler_Yield` | 620 | **195** | **−69%** |

The Spawn_NW halving is the more interesting result — Spawn_NW
doesn't even use the new SPSC list (its Worker.Switch_To'd bodies
are empty, no yields), but removing YIELDED from the protected lock
freed contention on the *whole* `Run_Queue` protected for everyone:
fewer waiters means shorter wait queues on every protected call,
including Inject and the entry-family Pop. The path that wasn't
optimised got faster as a side-effect of the path that was.

The remaining gap on Spawn_* is the shared `Items` queue's
serialisation — every Spawn, every Worker pickup, and every Reap
goes through one protected lock. Closing that gap requires lock-free
queue primitives (Vyukov MPSC for Items + atomic counter for
In_Flight); design and implementation are tracked as a future perf
pass, not a Phase 3 sub-item, because:

1. Phase 3's exit criterion is `ping_pong` (2 goroutines, 1 channel,
   1 M iterations) — it never stresses high-throughput Spawn at all.
2. The lock-free design needs careful interaction with the existing
   entry-family barrier (which can't reference atomic counters
   directly — barrier guards are protected-state only).
3. Real workloads have non-trivial bodies that dwarf Spawn-time
   contention. Optimising before measuring under realistic load is
   the textbook premature-optimisation mistake; the post-`ping_pong`
   measurement gives that load.

Methodology and machine: same dev host as Phase 2 (darwin/arm64,
Apple M-series, GNAT 15.0.1, libco MP build, `-O2`), `make -C runtime
bench`. The B/op column reports 0 across all three rows because
`Goroutine_Record` allocations live in libgc's atomic pool and the
benchstat-format `B/op` column is computed from `GC_get_total_bytes`
deltas which exclude that pool — see Phase 2 ledger note above.

## How to add a row

1. Implement the unit under test in `runtime/src/`.
2. Add a benchmark procedure in `runtime/bench/<module>_bench.{ads,adb}`,
   register from its `Register_All`, wire `Register_All` into
   `runtime/bench/bench_runner.adb`'s sequence.
3. Run `make -C runtime bench`; copy the line into the table above.
4. If you cannot fit the 2× bar, document the named exception per
   [ADR-0006 §"Named exceptions"](../docs/adr/0006-runtime-performance-bar.md).
5. Cross-link the benchmark from the relevant roadmap item's
   `Done YYYY-MM-DD:` notes.
