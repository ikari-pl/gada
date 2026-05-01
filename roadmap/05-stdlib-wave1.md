# Phase 5 — Stdlib wave 1: pure-Go foundations

[← Phase 4](04-interfaces-reflection.md) · [Index](README.md) · Next: [Phase 6 →](06-stdlib-wave2.md)

**Status:** `NOT_STARTED`
**Prerequisites:** [Phase 2](02-core-runtime.md) `DONE`, [Phase 4](04-interfaces-reflection.md) `DONE`
**Goal:** Port the pure-Go foundational packages: `errors`, `strings`,
`strconv`, `bytes`, `io`, `bufio`, `fmt`. These are mostly mechanical
once the runtime primitives exist; their value is they unblock most
real-world Go libraries.
**Exit criterion:** transpile and run a sample of Go's own stdlib tests
(adapted) for each package; ≥ 80% pass rate; remaining failures
documented per package.

## Items

- [ ] **Stdlib package: `errors`**
      *Files:* `stdlib/errors/`, `runtime/tests/stdlib/test_errors.adb`
      *Verify:* `make stdlib-test PKG=errors`
      *Done when:* `errors.New`, `errors.Is`, `errors.As`, `errors.Unwrap` all behave identically to Go reference; coverage 100%.

- [ ] **Stdlib package: `strings`**
      *Files:* `stdlib/strings/`
      *Verify:* `make stdlib-test PKG=strings`
      *Done when:* core 60+ functions match Go behavior on the test corpus; coverage ≥ 95%.

- [ ] **Stdlib package: `strconv`**
      *Files:* `stdlib/strconv/`
      *Verify:* `make stdlib-test PKG=strconv`
      *Done when:* `Itoa`, `Atoi`, `FormatFloat`, `ParseFloat`, `Quote`, `Unquote` all match Go behavior including edge cases (NaN, Inf, denormals); coverage ≥ 95%.

- [ ] **Stdlib package: `bytes`**
      *Files:* `stdlib/bytes/`
      *Verify:* `make stdlib-test PKG=bytes`
      *Done when:* `Buffer`, `Reader`, `Equal`, `Split`, `Join` all correct; coverage ≥ 95%.

- [ ] **Stdlib package: `io`**
      *Files:* `stdlib/io/`
      *Verify:* `make stdlib-test PKG=io`
      *Done when:* `Reader`, `Writer`, `Copy`, `EOF` semantics correct; coverage ≥ 95%.

- [ ] **Stdlib package: `bufio`**
      *Files:* `stdlib/bufio/`
      *Verify:* `make stdlib-test PKG=bufio`
      *Done when:* `Scanner`, `Reader.ReadLine`, `Writer.Flush` correct; coverage ≥ 95%.

- [ ] **Stdlib package: `fmt`**
      *Files:* `stdlib/fmt/`
      *Verify:* `make stdlib-test PKG=fmt`
      *Done when:* `Println`, `Printf`, `Sprintf`, `Errorf`, `Scanf` correct for the verb set documented in `docs/fmt_verb_support.md`; coverage ≥ 95%.

- [ ] **Cross-package integration example**
      *Files:* `examples/wordcount/main.go`
      *Verify:* `make example HELLO=wordcount`
      *Done when:* a wordcount program reading a file, splitting, sorting, formatting, and printing matches expected output.
