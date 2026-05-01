# Phase 11 — Real-world validation & 1.0

[← Phase 10](10-mixed-codebases.md) · [Index](README.md) · [Future →](future.md)

**Status:** `NOT_STARTED`
**Prerequisites:** [Phase 6](06-stdlib-wave2.md), [Phase 7](07-stdlib-wave3-network.md), [Phase 8](08-stdlib-wave4-crypto.md) `DONE`
**Goal:** Pick 3 real Go programs, transpile them, run them, fix every
bug surfaced. Establish a performance baseline against stock Go. Cut a
1.0 release.
**Exit criterion:** all three target programs build with `gada build`,
run their own test suites with ≥ 90% pass rate, and have a published
performance ratio against stock Go.

## Items

- [ ] **Pick the 3 target programs**
      *Files:* `docs/v1_targets.md`
      *Verify:* document is reviewed; each target is named with rationale.
      *Done when:* candidates listed (suggestions: `google/uuid` —
      pure algorithm, no concurrency; `pkg/errors` — interfaces +
      reflection; a small CLI tool e.g. `mvdan/gofumpt` — fmt + os +
      filesystem).

- [ ] **Target 1: build + test**
      *Files:* `targets/<target1>/`
      *Verify:* `make target T=<target1>`
      *Done when:* program builds with GADA, its test suite passes ≥ 90%, failure modes documented.

- [ ] **Target 2: build + test**
      *Files:* `targets/<target2>/`
      *Verify:* `make target T=<target2>`
      *Done when:* same.

- [ ] **Target 3: build + test**
      *Files:* `targets/<target3>/`
      *Verify:* `make target T=<target3>`
      *Done when:* same.

- [ ] **Performance baseline**
      *Files:* `benchmarks/baseline.md`, `benchmarks/run.sh`
      *Verify:* `./benchmarks/run.sh` produces a CSV of GADA-vs-`gc` timings on each target.
      *Done when:* report published in `docs/performance.md` with raw numbers and analysis.

- [ ] **1.0 release notes**
      *Files:* `RELEASES.md`, `CHANGELOG.md`
      *Verify:* `wc -l RELEASES.md` ≥ 100; release tag created.
      *Done when:* `git tag -a v1.0.0 -m "..."` is pushed.

- [ ] **1.0 documentation pass**
      *Files:* `docs/` (full review)
      *Verify:* `make docs-check` (link checker, spell checker, dead-code in examples)
      *Done when:* every doc page is reviewed; all examples in docs are tested in CI.
