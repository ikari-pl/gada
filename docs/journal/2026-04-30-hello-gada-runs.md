---
type: note
title: hello, GADA — first end-to-end run
created: 2026-04-30
tags: [milestone, phase-1, end-to-end]
related:
  - "[[ADR-0001]]"
  - "[[ADR-0002]]"
  - "[[roadmap/01-minimal-transpiler]]"
  - "[[roadmap/02-core-runtime]]"
---

# hello, GADA — first end-to-end run

The first time the project's central thesis — *Go programs run on the
GCC Ada toolchain* — is empirically demonstrated. A Go program goes in;
a native binary linked against the Ada runtime comes out; it prints
exactly what the Go would have. Every later phase widens this pinhole.

## Roadmap items ticked

Tracker of record: [[roadmap/01-minimal-transpiler]]. Full exit-criterion
output: `.maestro/playbooks/Initiation/Working/phase-04-exit-criterion.log`;
full `make ci` output: `.maestro/playbooks/Initiation/Working/phase-04-make-ci.log`.

| # | Item | Verify command | Exit |
|---|------|----------------|------|
| 1 | Define the GADA-IR | `cd compiler && go test ./internal/ir/...` | 0 (99.0% cov) |
| 2 | Go AST → GADA-IR translation | `cd compiler && go test ./internal/translate/...` | 0 (100% cov) |
| 3 | GADA-IR → Ada source emission | `cd compiler && go test ./internal/emit/...` | 0 (96.3% cov) |
| 4 | GADA.Core.IO — minimal Println | `make -C runtime test PKG=core.io` | 0 (1 assertion, LF pinned) |
| 5 | End-to-end driver: `gada build` | `./bin/gada build ./examples/hello && ./examples/hello/hello \| grep -q "hello, GADA"` | 0 |
| 6 | `hello` example | `make example HELLO=hello` | 0 |
| 7 | CI integration: examples are run | `make example HELLO=hello` (regression-gates the diff) | 0 |

## Exit-criterion captured stdout

```
$ make clean && make example HELLO=hello
=== gada build examples/hello ===
Setup
   [mkdir]        object directory for project Gada_Core
   [mkdir]        library directory for project Gada_Core
Compile
   [Ada]          main.adb
   [Ada]          gada.ads
   [Ada]          gada-core-io.adb
   [Ada]          gada-core.adb
Build Libraries / Bind / Link …
=== running examples/hello/hello ===
make example: hello OK

$ ./examples/hello/hello
hello, GADA

$ diff <(./examples/hello/hello) examples/hello/expected_output.txt
$ echo $?
0
```

Binary: `examples/hello/hello` — 483 KB, Mach-O 64-bit executable arm64,
linked against `libgada_core.a` and the Alire-managed GNAT 15 runtime.

## Toolchain baseline (darwin/arm64, Darwin 25.5.0)

| Tool | Version |
|------|---------|
| `go` | 1.26.2 (darwin/arm64) |
| `alr` | 2.1.0 |
| `gprbuild` | 25.0.0 (2025-05-16, aarch64-apple-darwin23.6.0) |
| `gnat` | 15.0.1 prerelease (Alire `gnat_native_15.1.2`) |
| `golangci-lint` | v2.1.6 |
| `lcov` | 2.4_1 |

CI runs the same pipeline on `ubuntu-latest` via the `examples` job in
`.github/workflows/ci.yml`, gated behind `build-test-coverage`.

## Side-work forced by the exit criterion

- **macOS Sequoia duplicate-LC_RPATH dyld bug**, redux. Phase 01 papered
  over it for the AUnit test runner via `runtime/tests/run_tests.sh`.
  The same fix had to land in the user-binary side: `gada build` now
  post-processes its output with `otool -l` + `install_name_tool
  -delete_rpath`, no-op on Linux/older macOS, mandatory on Darwin 25+.
  Without it, the example aborted at exit 134 before main() ran.
- **`make example` exit-code capture bug.** The `if ! cmd; then
  actual_exit=$?; …` pattern in `Makefile`'s `example` target captured
  the negated exit, not the binary's. With the dyld bug above, this
  silently masked a 134 abort as success. Fixed to capture
  `$?` immediately after the unwrapped command.
- **`make example` needs Alire env on dev machines.** Bare `gprbuild`
  from a PATH-shim doesn't surface the GNAT compiler to gprconfig on
  aarch64-darwin; CI's `Expose gprbuild on PATH` step works around it
  for x86_64-linux. Added an `alr -n exec --` wrap to the `example`
  recipe for parity on local dev boxes that have Alire installed.
- **First `make lint` audit since Phase 1 code landed.** Surfaced 68
  issues — 50 missing doc comments on IR's interface-implementation
  methods, 14 gosec warnings on the build driver / golden-file test
  infrastructure, 1 `cap` shadowing, 1 gofmt regression, 3 unused test
  helper params. Resolved with narrowly-scoped `.golangci.yml`
  exclusions (each carrying a one-line rationale) plus genuine fixes
  for the shadowing, formatting, and dead test params.

## Phase 2 outlook

Phase 2 (core runtime: memory & errors) is now `IN_PROGRESS` per
[[roadmap/02-core-runtime]]. Phase 1 carries the bare minimum for
`fmt.Println` of a string literal; Phase 2 adds `Gada.GC`
(Boehm-Demers-Weiser binding), `Gada.Core.{Slices,Maps,Defer,Panic}`,
and the matching emit paths (`[]T{...}`, `append`/`len`/`cap`, slice
expressions, map literals + lookup + delete + range,
`defer`/`panic`/`recover` with scope-exit hooks). Exit criterion
(`make example HELLO=collections`) is the next end-to-end proof point
— same regression-gate shape as `hello`, broader runtime+compiler
surface. The IR is intentionally narrow today; widening it once for
slices/maps and once for control flow is the load-bearing decision the
next phase has to get right.
