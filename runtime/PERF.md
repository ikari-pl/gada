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

| Benchmark | GADA ns/op | GADA B/op | Go ns/op (ref) | Ratio | Notes |
|---|---:|---:|---:|---:|---|
| `Memory_Allocate_64` | 11 | 80 | ~10–15 | ~1.0× | Traced 64-byte alloc; libgc fast path. |
| `Memory_Allocate_Atomic_64` | 10 | 80 | ~10–15 | ~1.0× | Atomic 64-byte alloc; ~equal to traced because libgc's per-call setup cost dominates at this size. |
| `Memory_Allocate_Atomic_4K` | 338 | 4112 | ~150–200 | ~1.5–2× | 4 KB alloc; libgc zeroing cost dominates. Within bar; documented as the "atomic-large-alloc" reference shape. |

**Go-side reference column is currently expert-estimate**, not
measured. Phase 11's cross-comparison harness replaces estimates
with measured numbers from a parallel `gc`-built corpus on the
same hardware. Treat ratios above as ±20% accurate until then.

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
