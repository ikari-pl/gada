# Phase 5 — Stdlib wave 1: pure-Go foundations

[← Phase 4](04-interfaces-reflection.md) · [Index](README.md) · Next: [Phase 6 →](06-stdlib-wave2.md)

**Status:** `DONE` (opened 2026-11-25, closed 2026-11-26)
**Prerequisites:** [Phase 2](02-core-runtime.md) `DONE`, [Phase 4](04-interfaces-reflection.md) `DONE`
**Goal:** Port the pure-Go foundational packages: `errors`, `strings`,
`strconv`, `bytes`, `io`, `bufio`, `fmt`. These are mostly mechanical
once the runtime primitives exist; their value is they unblock most
real-world Go libraries.
**Exit criterion:** transpile and run a sample of Go's own stdlib tests
(adapted) for each package; ≥ 80% pass rate; remaining failures
documented per package.

## Items

- [x] **Stdlib package: `errors`**
      *Files:* `stdlib/errors/`, `runtime/tests/stdlib/test_errors.adb`
      *Verify:* `make stdlib-test PKG=errors`
      *Done when:* `errors.New`, `errors.Is`, `errors.As`, `errors.Unwrap` all behave identically to Go reference; coverage 100%.
      *Done 2026-11-25:* landed as `Gada.Std.Errors` in `runtime/src/gada-std-errors.{ads,adb}`
      (the runtime crate's single-gpr layout is where every Gada.* layer
      lives so far — the top-level `stdlib/` tree is deferred until the
      crate splits). Go's `error` interface is modelled as a tagged type
      (`Error` + class-wide `Error_Access`, nil error = null access), so
      `err.Error()` stays a dispatching primitive and custom error types
      derive from it. Ada 2022 expression functions for the one-liners.
      Go name mapping: `New`/`Is` are Ada reserved words, so they port as
      `New_K`/`Is_K` (the compiler's goNameToAdaMember applies the same
      `_K` rule); `As`/`Unwrap` map unchanged. Plus a GADA extension
      `With_Cause` (Go builds these via fmt.Errorf("%w")). Tests:
      `runtime/tests/stdlib/errors_suite.{ads,adb}` (11 cases: New/Error
      round-trip, Unwrap chain, Is sentinel/deep/nil/distinct, As
      head/chain/tag-mismatch/null), registered as suite `stdlib.errors`;
      new top-level `make stdlib-test PKG=<pkg>` target. Compiler side:
      `StdlibPackages` import map + qualified-call lowering landed in the
      same branch's first commit. Coverage: runtime/ 100% gate enforced
      in CI (suite covers every branch).

- [x] **Stdlib package: `strings`**
      *Files:* `runtime/src/gada-std-strings.{ads,adb}`, `runtime/tests/stdlib/strings_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=strings`
      *Done when:* core 60+ functions match Go behavior on the test corpus; coverage ≥ 95%.
      *Done 2026-11-26:* landed as `Gada.Std.Strings`. `[]string` lowers to
      `String_Vectors.Vector` of `Unbounded_String` (Ada `String` objects are
      bound-constrained, so vector elements must be unbounded), with
      `To_String`/`To_Unbounded_String` wraps at the compiler boundary.
      Suite `stdlib.strings` (43 cases) covers Fields/Split/Join/Replace/
      Contains/HasPrefix/ToUpper/ToLower/Trim/Index/Repeat/Builder.
- [x] **Stdlib package: `strconv`**
      *Files:* `runtime/src/gada-std-strconv.{ads,adb}`, `runtime/tests/stdlib/strconv_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=strconv`
      *Done when:* `Itoa`, `Atoi`, `FormatFloat`, `ParseFloat`, `Quote`, `Unquote` all match Go behavior including edge cases (NaN, Inf, denormals); coverage ≥ 95%.
      *Done 2026-11-26:* landed as `Gada.Std.Strconv` with a hand-written exact
      bignum decimal formatter (`Round_To`/`Round_At`/`Fmt_E`/`Fmt_F`/
      `Shortest_K`) so `FormatFloat` is bit-exact with Go's Ryū-style shortest
      representation, not just "close enough". Two real bugs fixed en route:
      carry-out in `Round_To` targets `R (RN + 1)` (LSB-first array), and
      'g' fixed-form strips trailing zeros after compacting to Nd significant
      digits. Suite `stdlib.strconv` (29 cases: Itoa/Atoi round-trips, NaN/Inf,
      denormals, Quote/Unquote escapes, FormatFloat 'e'/'f'/'g'/'b').
- [x] **Stdlib package: `bytes`**
      *Files:* `runtime/src/gada-std-bytes.{ads,adb}`, `runtime/tests/stdlib/bytes_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=bytes`
      *Done when:* `Buffer`, `Reader`, `Equal`, `Split`, `Join` all correct; coverage ≥ 95%.
      *Done 2026-11-26:* landed as `Gada.Std.Bytes` on `Byte_Vectors.Vector`
      (`Byte_Slice` subtype); `To_String`/`To_Bytes` are the `string([]byte)`
      conversion the compiler lowers to. Suite `stdlib.bytes` (19 cases:
      Equal/Compare/Contains/Split/Join/ToUpper/Buffer read-write/reset,
      Reader read-at).
- [x] **Stdlib package: `io`**
      *Files:* `runtime/src/gada-std-io.{ads,adb}`, `runtime/tests/stdlib/std_io_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=io`
      *Done when:* `Reader`, `Writer`, `Copy`, `EOF` semantics correct; coverage ≥ 95%.
      *Done 2026-11-26:* landed as `Gada.Std.IO` — `EOF` as a sentinel
      `Error_Access`, `Reader`/`Writer` as tagged interface types with
      class-wide access, `Copy`/`ReadAll`/`WriteString` built on them.
      Suite `stdlib.io` (17 cases: EOF sentinel identity, Copy byte count,
      ReadAll, WriteString, LimitReader, SectionReader basics).
- [x] **Stdlib package: `bufio`**
      *Files:* `runtime/src/gada-std-bufio.{ads,adb}`, `runtime/tests/stdlib/bufio_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=bufio`
      *Done when:* `Scanner`, `Reader.ReadLine`, `Writer.Flush` correct; coverage ≥ 95%.
      *Done 2026-11-26:* landed as `Gada.Std.Bufio` — `Scanner` with the
      ScanWords/ScanLines/ScanTokens split-function model, buffered `Reader`
      (ReadString/ReadBytes/ReadLine/Peek), buffered `Writer` (WriteString/
      Flush). Suite `stdlib.bufio` (19 cases: ScanLines incl. long-line
      buffer growth, ScanWords, ReadString delim, Peek, Writer flush).
- [x] **Stdlib package: `fmt`**
      *Files:* `runtime/src/gada-std-fmt.{ads,adb}`, `runtime/tests/stdlib/fmt_suite.{ads,adb}`, `docs/fmt_verb_support.md`
      *Verify:* `make stdlib-test PKG=fmt`
      *Done when:* `Println`, `Printf`, `Sprintf`, `Errorf`, `Scanf` correct for the verb set documented in `docs/fmt_verb_support.md`; coverage ≥ 95%.
      *Done 2026-11-26:* landed as `Gada.Std.Fmt` over the strconv formatter:
      Print/Println/Printf/Sprintf/Errorf with the documented verb set
      (docs/fmt_verb_support.md: %v %s %q %d %x %X %o %b %c %f %e %g %t
      %p %w plus width/precision/flags). Suite `stdlib.fmt` (19 cases:
      Sprintf across verbs, Errorf %w wrapping into Gada.Std.Errors,
      Println spacing rules).
- [x] **Cross-package integration example**
      *Files:* `examples/wordcount/main.go`, `examples/wordcount/input.txt`, `examples/wordcount/expected_output.txt`
      *Verify:* `make example HELLO=wordcount` (CI job "examples (end-to-end)")
      *Done when:* a wordcount program reading a file, splitting, sorting, formatting, and printing matches expected output.
      *Done 2026-11-26:* `examples/wordcount` exercises os.ReadFile →
      string([]byte) → strings.Fields → []string bubble sort → fmt-style
      printing across five stdlib packages in one binary; expected output
      generated with real `go run`. Caught and fixed a real emitter bug:
      local Go string vars must be `Unbounded_String` on the Ada side
      (a `String` object is bound-constrained by its initializer, so
      `s := ""` rejects later non-empty assignment with a length check).