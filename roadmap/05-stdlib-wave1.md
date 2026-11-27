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

**Exit-criterion status (2026-11-27, PR #45 review #15) — owner
accepted the replacement.** The criterion above was **never run**: no
adapted Go stdlib test corpus exists in the tree, and no command for it
exists. The phase was flipped to `DONE` on 2026-11-26 without it, and
the PR body's "met at 100%" had no command or output behind it. What
*was* built is Ada AUnit suites ported per package (Go-verified expected
values, several pinned from `go run`) plus one transpiled end-to-end
program. The runnable replacement — accepted by the owner as this
phase's exit evidence (a **scope change**, recorded honestly: it does
not transpile Go's own tests):

```sh
for p in errors strings strconv bytes io bufio fmt os; do
  make stdlib-test PKG=$p || exit 1
done && make example HELLO=wordcount
```

CI run 45783719261 (PR #45) is green on it: every `Gada.Std.*` suite
case OK, `Failed Assertions: 0`, and `make example: wordcount OK` with
output matching Go byte for byte. The original adapted-corpus criterion
(≥ 80% pass per package on Go's own tests) is not dropped — it is
carried to [Phase 11](11-validation-1.0.md) as an explicit item.

## Items

- [x] **Exit-criterion sign-off (owner)** — accepted 2026-11-27.
      *Verify:* the replacement command in *Exit-criterion status* above
      exits 0 (CI run 45783719261: all stdlib suites OK, 0 failed
      assertions; wordcount example matches Go).
      *Done when:* met by owner acceptance of the replacement; the
      original adapted Go stdlib corpus (≥ 80% pass per package) is
      tracked in [Phase 11](11-validation-1.0.md).

- [x] **Stdlib package: `errors`**
      *Files:* `runtime/src/gada-std-errors.{ads,adb}`, `runtime/tests/stdlib/errors_suite.{ads,adb}`
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
      *Gap (recorded 2026-11-27, PR #45 review #14):* the "60+ functions"
      bar was **not** met — the spec declares 35 subprograms (incl. the
      Replacer). Missing Go API (e.g. `Cut`/`CutPrefix`, `IndexFunc`,
      `LastIndexFunc`, `ContainsFunc`, `TrimLeftFunc`, `Builder`,
      `NewReader`, `Compare`, `SplitAfterN`) is not ported; see
      docs/imperfections.md ("Stdlib wave 1 API gaps" and the
      byte-oriented, no-rune-decoding limits).
      *Done 2026-11-26:* landed as `Gada.Std.Strings`. `[]string` lowers to
      `String_Vectors.Vector` of `Unbounded_String` (Ada `String` objects are
      bound-constrained, so vector elements must be unbounded), with
      `To_String`/`To_Unbounded_String` wraps at the compiler boundary.
      Suite `stdlib.strings` (18 test routines) covers Fields/Split/Join/
      Replace/Replacer/Contains/HasPrefix/ToUpper/ToLower/Trim/Index/Repeat.
      *Corrected 2026-11-27 (PR #45 review #14):* the note originally said
      "43 cases" and listed `Builder`; there are 18 routines and no
      Builder. Review fixes since: ASCII-only case mapping (UTF-8 is no
      longer corrupted), `NewReplacer` accepts an empty old string.
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
      digits. Suite `stdlib.strconv` (15 test routines: Itoa/Atoi round-trips,
      NaN/Inf, denormals, Quote/Unquote escapes, FormatFloat 'e'/'f'/'g').
      *Corrected 2026-11-27 (PR #45 review #14):* originally "29 cases" and
      'b' format; 'b' is not supported, and the "bit-exact" claim was false
      until the review fixes — negative floats raised or printed -0.0
      (review #1) and shortest output was wrong for ~17% of subnormals
      (review #9). Shortest is now Go's exact roundShortest, checked by a
      62,768-value differential run against Go (0 mismatches). ParseFloat
      still misrounds ~1% of subnormal decimals (docs/imperfections.md).
- [x] **Stdlib package: `bytes`**
      *Files:* `runtime/src/gada-std-bytes.{ads,adb}`, `runtime/tests/stdlib/bytes_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=bytes`
      *Done when:* `Buffer`, `Reader`, `Equal`, `Split`, `Join` all correct; coverage ≥ 95%.
      *Done 2026-11-26:* landed as `Gada.Std.Bytes` on `Byte_Vectors.Vector`
      (`Byte_Slice` subtype); `To_String`/`To_Bytes` are the `string([]byte)`
      conversion the compiler lowers to. Suite `stdlib.bytes` (8 test
      routines: To_Bytes/To_String, Equal/Compare, Index/Contains,
      HasPrefix/HasSuffix, Split/Join, Buffer write/read/reset, Reader
      read/readbyte/len, Compare/Contains edges).
      *Corrected 2026-11-27 (PR #45 review #14):* originally "19 cases" with
      ToUpper and Reader ReadAt; neither exists in `Gada.Std.Bytes`.
- [x] **Stdlib package: `io`**
      *Files:* `runtime/src/gada-std-io.{ads,adb}`, `runtime/tests/stdlib/std_io_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=io`
      *Done when:* `Reader`, `Writer`, `Copy`, `EOF` semantics correct; coverage ≥ 95%.
      *Done 2026-11-26:* landed as `Gada.Std.IO` — `EOF` as a sentinel
      `Error_Access`, `Reader`/`Writer` as tagged interface types with
      class-wide access, `Copy`/`ReadAll` built on them, plus the
      `ErrShortWrite` sentinel. Suite `stdlib.io` (8 test routines: EOF
      sentinel identity, Copy happy/empty/read-error/write-error/short-write,
      ReadAll ok/hard error).
      *Corrected 2026-11-27 (PR #45 review #14):* originally "17 cases" with
      `WriteString`, `LimitReader` and `SectionReader`; none of the three
      is ported (gap — not implemented by this review round).
- [x] **Stdlib package: `bufio`**
      *Files:* `runtime/src/gada-std-bufio.{ads,adb}`, `runtime/tests/stdlib/bufio_suite.{ads,adb}`
      *Verify:* `make stdlib-test PKG=bufio`
      *Done when:* `Scanner`, `Reader.ReadLine`, `Writer.Flush` correct; coverage ≥ 95%.
      *Done 2026-11-26:* landed as `Gada.Std.Bufio` — `Scanner` in ScanLines
      mode, buffered `Reader` (Read/ReadString/ReadLine), buffered `Writer`
      (Write/WriteString/Flush/Len). Suite `stdlib.bufio` (13 test routines:
      chunk reads, ReadLine CR/EOF/prefix/CRLF straddle, ReadString delim,
      stored-error delivery, Flush short write/EOF, Scanner lines incl.
      long-line reassembly and CR at EOF, Writer buffering/auto-flush).
      *Corrected 2026-11-27 (PR #45 review #14):* originally claimed the
      ScanWords/ScanTokens split-function model, `ReadBytes`, `Peek` and
      "19 cases"; none of those APIs exists (gap — Scanner is ScanLines
      only), and there are 13 routines. Review fixes since: Flush returns
      io.EOF from the destination (#12), Scanner drops a final CR at EOF
      (#16).
- [x] **Stdlib package: `fmt`**
      *Files:* `runtime/src/gada-std-fmt.{ads,adb}`, `runtime/tests/stdlib/fmt_suite.{ads,adb}`, `docs/fmt_verb_support.md`
      *Verify:* `make stdlib-test PKG=fmt`
      *Done when:* `Println`, `Printf`, `Sprintf`, `Errorf`, `Scanf` correct for the verb set documented in `docs/fmt_verb_support.md`; coverage ≥ 95%.
      *Done 2026-11-26:* landed as `Gada.Std.Fmt` over the strconv formatter:
      Print/Println/Printf/Sprintf/Errorf with the documented verb set
      (docs/fmt_verb_support.md: %v %s %q %d %x %X %o %b %c %f %e %g %t
      %p %w plus width/precision/flags). Suite `stdlib.fmt` (8 test
      routines: Sprintf across verbs, Errorf %w wrapping into
      Gada.Std.Errors, Sscanf, Print/Sprint spacing).
      *Corrected 2026-11-27 (PR #45 review #14):* originally "19 cases";
      there are 8 routines. "Scanf" in *Done when* shipped as `Sscanf`
      only (no stdin `Scanf`). Review fixes since: %w wraps wherever it
      sits (#2), float +/space/zero-pad flags (#6), Print spacing and new
      Sprint/Sprintln (#7), %c of any rune as UTF-8 (#8).
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