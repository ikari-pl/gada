# Phase 9 — Verification track: Go → SPARK

[← Phase 8](08-stdlib-wave4-crypto.md) · [Index](README.md) · Next: [Phase 10 →](10-mixed-codebases.md)

**Status:** `NOT_STARTED`
**Prerequisites:** [Phase 5](05-stdlib-wave1.md) `DONE`
**Goal:** Add `gada build -mode=spark` that emits SPARK-compatible
Ada for the Go subset that respects SPARK rules. Wire `gnatprove`.
Deliver a verified Go program.
**Exit criterion:** `examples/verified_sort` is a Go merge-sort
implementation that, in `-mode=spark`, passes `gnatprove --level=2`
with zero unproved checks.

## Items

- [ ] **ADR — SPARK subset definition**
      *Files:* `docs/adr/0020-spark-subset.md`
      *Verify:* ADR is `accepted` and enumerates the Go subset rules.
      *Done when:* the Go subset is precisely defined: no unsafe, no goroutines, no maps with mutable keys, no exceptions, ownership-via-scope only.

- [ ] **Compiler — `-mode=spark` flag**
      *Files:* `compiler/internal/emit/spark.go`
      *Verify:* `cd compiler && go test ./internal/emit/... -run Spark`
      *Done when:* the flag enables SPARK-compatible emission (no exception handlers, no aliasing, no dynamic dispatch).

- [ ] **Compiler — diagnostics for SPARK violations**
      *Files:* `compiler/internal/check/spark_check.go`
      *Verify:* `cd compiler && go test ./internal/check/...`
      *Done when:* a Go program using a forbidden feature (e.g., goroutines) under `-mode=spark` produces a clear error pointing to the line.

- [ ] **Compiler — emit pre/postconditions from `//go:gada-pre` etc.**
      *Files:* `compiler/internal/emit/contracts.go`
      *Verify:* golden tests
      *Done when:* `//go:gada-pre x > 0` on a function generates the corresponding `Pre =>` aspect in Ada.

- [ ] **`verified_sort` example**
      *Files:* `examples/verified_sort/main.go`, `examples/verified_sort/spark_check.sh`
      *Verify:* `./examples/verified_sort/spark_check.sh` (runs `gada build -mode=spark` then `gnatprove`)
      *Done when:* `gnatprove --level=2` reports zero unproved checks.

- [ ] **Documentation: writing GADA-compatible SPARK-Go**
      *Files:* `docs/spark_authoring.md`
      *Verify:* `wc -l docs/spark_authoring.md` ≥ 200; reviewed.
      *Done when:* a developer can read it and write a verifiable Go function from scratch.
