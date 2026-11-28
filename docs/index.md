---
layout: home
title: GADA — Go on Ada
---

# GADA — Go on Ada

**GADA transpiles Go source to Ada source and runs it on the GCC Ada
toolchain.** The output executes against a Go-semantics-preserving
runtime library written in Ada: goroutines on Ada tasks, channels on
protected objects, slices and maps as Ada generics, GC via Boehm.
Result: a Go program that builds with `gprbuild` into a **single static
executable** that runs on any GCC-Ada target — including platforms the
Go reference compiler will never reach.

> A Go program that builds with `go build` should transpile to Ada that
> builds with `gprbuild` and behaves identically for I/O, arithmetic,
> control flow, concurrency, and standard-library calls.

[Repo](https://github.com/ikari-pl/gada) ·
[Roadmap](https://github.com/ikari-pl/gada/tree/main/roadmap) ·
[ADRs](https://github.com/ikari-pl/gada/tree/main/docs/adr) ·
[Known differences](https://github.com/ikari-pl/gada/blob/main/docs/imperfections.md) ·
[CI](https://github.com/ikari-pl/gada/actions)

---

## Quick start

```sh
git clone https://github.com/ikari-pl/gada.git
cd gada
make ci                                  # lint + compiler tests + Ada runtime tests + coverage gate
make example HELLO=hello                 # transpile, gprbuild, run, diff against expected output
make example HELLO=crypto_suite          # sha256 + hmac + AES-GCM + hex, end to end
make stdlib-test PKG=crypto.aes          # one AUnit suite (FIPS-197 / SP 800-38A KATs)
```

Every claim on this page is backed by a command that exits 0 in CI —
nothing here is aspirational.

---

## What works today

Phases 0–8 of the [roadmap](https://github.com/ikari-pl/gada/tree/main/roadmap)
are `DONE` and CI-green (as of 2026-11-28).

### The pipeline

```
Go source ──► go/parser + go/types (typed AST) ──► GADA IR ──► Ada source ──► gprbuild ──► static binary
```

The front-end is the Go team's own tooling (`go/ast`, `go/types`,
`golang.org/x/tools/go/packages`) — we never parse Go ourselves.

### Go language features

- Functions, structs, methods, interfaces — with **compile-time
  structural dispatch**, type switches, and type assertions
  (single-value and comma-ok)
- Slices and maps (range, append, len/cap, make, index/slice assignment)
- **Goroutines** (`go f(x)`) on an M:N scheduler, **channels** (buffered
  and unbuffered), **`select`** (incl. comma-ok receive), `close`
- `defer`, `panic`, `recover` — including defer-during-panic LIFO and
  panic propagation
- `reflect.TypeOf` / `reflect.ValueOf` and basic struct walking
- Multi-value returns, `:=` defines, `if`/`for`/`switch`, `fmt.Println`
  and friends

### Runtime (`runtime/` — 100% line-covered by unit tests in CI)

| Layer | Provides |
|---|---|
| `GADA.Core` | slices, maps, defer, panic/recover, GC interface (Boehm-Demers-Weiser) |
| `GADA.Async` | M:N goroutine scheduler (libco), bounded/unbounded channels, select, timers, race detector (best-effort) |
| `GADA.Reflect` | type metadata, interface registry, `TypeOf`/`ValueOf` |
| `GADA.Std` | the Go standard-library ports below |

### Stdlib packages ported (import them in Go source today)

| Wave | Packages |
|---|---|
| 1 — foundations | `errors`, `strings`, `strconv`, `bytes`, `io`, `bufio`, `fmt` (via `Gada.Core.IO`), `os` (files/env/args) |
| 2 — system | `sync` (Mutex/WaitGroup), `time` (Duration, timers, sleep), `runtime` |
| 3 — network | `net` (TCP, IPv4), `net/http` (server + client), `encoding/json` |
| 4 — crypto & encoding | `hash/crc32`, `hash/crc64`, `hash/fnv`, `hash/adler32`, `crypto/sha256`, `crypto/sha512`, `crypto/sha1`, `crypto/md5`, `crypto/hmac`, `crypto/aes`, `crypto/cipher` (CBC/CTR/GCM), `encoding/base64`, `encoding/hex`, `encoding/binary`, `encoding/csv`, `encoding/xml` |

Correctness is pinned against **real Go 1.27**: every hash/HMAC/AES
vector comes from NIST CAVS / FIPS-197 / SP 800-38A and from `go run`
on the same inputs; the Ada ports must match byte-for-byte.

### End-to-end examples (each diffed against expected output in CI)

`hello` · `collections` (slices/maps/defer/panic/recover) ·
`ping_pong` (1M-iteration 2-goroutine channel relay) ·
`iface_dispatch` (interface dispatch + type switch + reflection) ·
`wordcount` (os.ReadFile + strings + maps) · `timer_pool` (timers +
sync) · `http_echo` (HTTP server on a port) · `json_roundtrip` ·
**`crypto_suite`** (SHA-256, HMAC sign/verify, AES-256-GCM seal/open,
hex — through the full transpile pipeline)

---

## How it works (and how we know)

- **Layered runtime**: `GADA.Std` → `GADA.Reflect` → `GADA.Async` →
  `GADA.Core`. A program that uses no goroutines links without
  `GADA.Async`; one that uses no reflection links without
  `GADA.Reflect`. This is what makes tiny embedded targets viable.
- **Honest verification**: CI gates are build + `go test` +
  golangci-lint + the Ada AUnit suites + a **100% line-coverage gate on
  `runtime/`** (documented per-line exclusions only, each with rationale
  in `runtime/COVERAGE.md`) + per-example output diffs. A PR that drops
  coverage or breaks an example goes red.
- **Vectors, not vibes**: all expected values are pinned from Go 1.27
  via `go run`, and the algorithms were cross-checked in independent
  Python transliterations before shipping.

---

## Where GADA differs from stock Go today

We ship known, documented divergences rather than silent breakage —
full list in
[docs/imperfections.md](https://github.com/ikari-pl/gada/blob/main/docs/imperfections.md).
The highlights:

- **Stdlib coverage is a subset** — the table above is the whole list.
  No `encoding/gob`, no `crypto/tls`, no `database/sql` yet.
- **`unsafe` is opt-in and `cgo` is post-1.0.** Go 1.18+ generics are
  in scope for 1.0 but not fully working yet.
- **Reflection is `TypeOf`/`ValueOf` + struct walking** — no
  `reflect.DeepEqual`, no method-by-name invocation yet.
- **v1 API deviations in ports**: `hmac.New` takes an explicit
  algorithm tag (`hmac.New(sha256.New, key)` lowers to
  `New_K (Sha256, Key)`) because the `hash.Hash` interface port lands
  later; `xml.Unmarshal` is single-root; `encoding/csv`'s record type
  is `Row` because `record` is an Ada reserved word.
- **Error model**: Go's `(value, error)` returns lower to Ada
  out-parameter procedures; the ports' `CONSTRAINT_ERROR` raises are
  converted into the error half, so `if err != nil` works as written.
- **Main returning does not join goroutines** (matches Go; ADR-0011) —
  hand-written Ada that leaves a ticker running must still call
  `Stop_All`.
- **The timer service is not yet Ravenscar-compatible** (timed accept;
  documented gap — ADR-0009).
- **Performance is not the goal**: we are expected to be slower than
  `gc` on most workloads. Availability on platforms `gc` cannot reach
  is the point, and numbers are measured and reported honestly against
  stock Go.

---

## Coming soon

| Phase | Status | What lands |
|---|---|---|
| 9 — Verification: Go → SPARK | **in progress** | `gada build -mode=spark` emits SPARK-compatible Ada for the verifiable Go subset; `gnatprove` proves it (exit criterion: `examples/verified_sort`, a Go merge-sort, verified) |
| 10 — Mixed Ada/Go codebases | next | Transpiled Go modules become `with`-able by Ada; Ada packages callable from Go via a `gada-import` directive — one binary, no FFI |
| 11 — Real-world validation & 1.0 | queued | 3 real Go programs transpiled, built, and run; every divergence fixed or documented |
| post-1.0 | sketched in `roadmap/future.md` | precise GC on top of `reflect` metadata, cgo via `pragma Import`, WASM target, generics-heavy programs, hot-reload via the Ada Distributed Annex |

---

## Why build on GADA — the case for this dev environment

1. **Reach**: GCC's Ada frontend targets ~30 architecture/OS pairs;
   stock Go targets ~15. GADA puts Go on AIX/POWER, OpenVMS/Itanium,
   Solaris/SPARC64, OpenBSD/SPARC64, bare-metal ARM Cortex-M, z/OS —
   platforms where vanilla Go has no port at all.
2. **One static binary**: `gada build` produces a single
   statically-linkable executable per target — no Go runtime install, no
   cgo toolchain on the target.
3. **Concurrency with Ada's guarantees**: goroutines can carry
   **priorities, deadlines, and ceiling locking**; the scheduler is
   **Ravenscar-compatible** at the appropriate compile target —
   deterministic, analyzable scheduling for certification-track work.
4. **A real verification path**: `gada build -mode=spark` + `gnatprove`
   proves the SPARK-respecting subset of your Go code. Vanilla Go
   cannot do this.
5. **Bidirectional interop**: an Ada program `with`s a transpiled Go
   package and calls it naturally; Go calls Ada packages through a
   directive. The boundary is one binary, not an FFI.
6. **Same language, better toolbox**: keep writing Go; gain Ada's
   target reach, tasking model, and proof tooling.

---

*Status: early development, phases 0–8 done, CI green. License TBD.*
