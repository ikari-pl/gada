---
type: style
title: GADA Go style guide
created: 2026-05-01
tags: [style, go, compiler, lint]
related:
  - "[[0000-record-architecture-decisions]]"
  - "[[0001-go-frontend-via-go-ast]]"
  - "[[CONTRIBUTING]]"
---

# GADA Go style guide

This document is the canonical style reference for every Go source
file under `compiler/` (and any future Go-side trees, e.g.,
ancillary tools). It is the human-readable companion to the
machine-checked rule set in [`.golangci.yml`](../.golangci.yml):
every rule listed here is either enforced by one of the active
linters in that file, or is documented as the "Why" entry behind
the linter's enablement. The two documents are intended to stay in
lockstep — adding a project rule means adding *both* a paragraph
here and either a linter to `.golangci.yml`'s enable list or an
explanatory comment in this file.

The style decisions here are downstream of [[0001-go-frontend-via-go-ast]]
(GADA's compiler is a Go program, so Go style conventions govern
the project's largest single body of source). When a rule below
cites that ADR, the ADR is the source of truth — this document is
the operational form, not the rationale.

## 1. Module path: `github.com/gada-lang/gada/...`

The Go module rooted at `compiler/go.mod` declares its module path as

```
github.com/gada-lang/gada/compiler
```

Every internal import below the compiler module uses that prefix
(see `compiler/cmd/gada/main.go`'s
`"github.com/gada-lang/gada/compiler/internal/version"` import).
Rules of the form:

- The `github.com/gada-lang/gada` GitHub organisation is reserved
  for the project. The module path is part of the public API
  (Go's import paths are addresses, not names) and is not
  rewritten across releases.
- Future Go-side modules — e.g., a `tools/` module for ancillary
  developer scripts — sit at sibling paths:
  `github.com/gada-lang/gada/tools`. They do not nest under
  `compiler/`.
- The `compiler/` module's `go.mod` is the floor for the Go
  toolchain version (`go 1.22` today). [[0001-go-frontend-via-go-ast]]
  binds GADA's input-Go-version support to this version: bumping
  it is itself a roadmap event, not a routine dependency update.

**Lint encoding.** Module-path correctness is checked at build
time by `go build`/`go vet` (a wrong path fails to resolve);
import-path style is enforced by `goimports` (formatter block in
`.golangci.yml`).

## 2. No `panic` in library code; return `error`

Public packages under `compiler/internal/...` (and any future
exported packages) communicate failure by returning an `error`.
They do not call `panic` for operational errors. The only
acceptable uses of `panic` are:

- *Truly impossible* invariant violations — a `default:` case in
  a switch over an exhaustive enum that the type system already
  rules out, where reaching the panic indicates a programmer
  error in *this* file. The panic message names the invariant.
- Initialisation errors during `init()` or `main()` startup that
  cannot meaningfully be returned — and even then, prefer
  `os.Exit(2)` after a `fmt.Fprintln(os.Stderr, ...)` over `panic`,
  so the operator gets a clean message rather than a stack trace.
  See `compiler/cmd/gada/main.go`'s `run()` function for the
  pattern: errors flow as return values, the indirected `osExit`
  is the one and only termination point.

Tests are not "library code" in this rule's sense. `t.Fatal` and
`require.NoError` (when testify lands) are how tests fail.
Helpers under `_test.go` files may panic to surface setup bugs.

**Lint encoding.** `staticcheck`'s SA-rules and `revive`'s
unhandled-error checks are enabled in `.golangci.yml`; combined
with `errcheck`, every returned error is either handled, assigned
to a named variable, or explicitly discarded with `_`. A `panic`
in non-`_test.go` code passes lint mechanically (it is a valid Go
statement) but fails review under this rule — an explicit comment
naming the impossible invariant is required for any such call site.

## 3. Interfaces stay small (≤ 4 methods unless documented)

An interface declared in compiler-side code carries no more than
four methods unless its godoc explicitly explains why. Concrete
limits:

- **Single-method interfaces** are preferred where the consumer
  only needs one capability — e.g., a `type Resolver interface { Resolve(path string) (Module, error) }`
  is preferred over a 20-method `PackageManager` whose consumer
  only calls `Resolve`.
- **Two-to-four-method interfaces** are fine when the methods are
  cohesive (e.g., a `type Cursor interface { Next() bool; Decode(*X) error; Err() error }`).
- **Larger interfaces** are flagged at review and require a
  godoc paragraph naming the cohesion that justifies bundling
  more than four methods. The most common legitimate exception
  is "the interface mirrors a stdlib interface verbatim"
  (`io.ReadWriteCloser`, `fs.FS`-derived interfaces).

The rationale is consumer-side: a single-purpose interface is
trivial to mock in tests and trivial to implement in production
without dragging unused methods. [[0001-go-frontend-via-go-ast]]
forces a lot of compiler-side code to consume `go/types`'s
already-large `types.Object` and `types.Type` interfaces from
upstream — those are out-of-scope for this rule (we do not
reshape upstream APIs), but anything *we* declare follows the
rule.

**Lint encoding.** No automatic check today. `revive`'s
`max-public-structs` rule is candidate enforcement once we have
a stable measurement of where the project naturally sits;
adding it now would over-fit on Phase 0–1's tiny surface area.

## 4. Public APIs have at least one test

Every exported identifier (`Func`, `Type`, `Const`, `Var`) in a
non-`main` package has at least one direct test that exercises
it with both a valid input and an input that drives the
error/edge path. This is the operational form of `AGENTS.md`
design principle #1 — coverage is the gate, this rule is the
review-time check that explains *why* a coverage drop is a
review-blocker, not just a CI-blocker.

Coverage targets ([[CONTRIBUTING]] cites the same numbers; the
authoritative source is `tools/coverage_thresholds.toml`):

- `compiler/`: ≥ 90% line coverage.
- `compiler/internal/emit/`: ≥ 95% line coverage.
- `compiler/internal/translate/`: ≥ 95% line coverage.

Existing examples are `compiler/internal/version/version_test.go`
(prefix/Version/Phase contract) and `compiler/cmd/gada/main_test.go`
(`--version`, no-args, unknown-flag, plus the trivial `main()`
wrapper exercised via the `osExit` indirection).

**Lint encoding.** `tools/coverage_gate.sh` (invoked from
`make coverage-gate`) reads `tools/coverage_thresholds.toml`
and fails CI on any package below threshold. The gate matches
by *overlapping prefix* — a file under `compiler/internal/emit/`
counts toward both that threshold and the parent `compiler/`
threshold — so deep-package regressions cannot hide behind
broad averages.

## 5. Exported identifiers use Go-standard naming (no `Gada` prefix)

The `Gada.X.Y` namespace is the **Ada side**'s rule
([[0002-runtime-layered]]). On the Go side, identifiers follow
Go-standard naming as documented in the upstream
`https://google.github.io/styleguide/go/`:

- Exported identifiers start with a capital letter, use
  CamelCase, and read naturally without their package as a
  prefix. `version.Describe()` reads correctly; renaming it to
  `version.GadaDescribe()` would stutter (the package name
  already says "this is GADA's version package").
- Package names are short, lowercase, single-word where
  possible, and never carry the `gada_` prefix — the import
  path already disambiguates. Today's packages are `version`,
  `ping`, `main`; future packages follow suit (`emit`,
  `translate`, `parse` — not `gadaemit`).
- Receiver names are 1–3 letters, abbreviating the type
  (`func (c *Compiler) ...` not `func (theCompiler *Compiler) ...`).
- Initialisms are all-caps in identifiers: `URL`, `ID`, `IO`,
  `JSON`. `parseURL` is correct; `parseUrl` is not (this is
  enforced by `staticcheck`).

The corollary worth stating: a Go file whose package name is
`gada` is wrong by this rule. The repo uses `gada` only as the
binary name (`compiler/cmd/gada/main.go`'s `package main` ships
as the `gada` executable) — never as a Go package name.

**Lint encoding.** `staticcheck`'s ST1003 (initialisms),
`revive`'s `var-naming` and `package-comments`, plus `gofmt`
enforce the bulk of these rules. Receiver-naming consistency is
enforced by `revive`'s `receiver-naming` rule (active under
`revive`'s defaults).

## 6. Errors are values, wrapped with context

Errors flow upward via `error` returns, never via global state or
panics (rule 2). When a function returns an error from a lower
layer, it wraps it with operational context using
`fmt.Errorf("doing X: %w", err)` — never `errors.New(err.Error())`
(loses the wrapping chain) and never bare `return err` when the
caller would not be able to identify the failing operation from
the message alone.

Sentinel errors (`var ErrFoo = errors.New("foo")`) are exposed
when callers need to compare against them with `errors.Is`. Custom
error types (implementing `error`) are used when callers need to
extract structured fields with `errors.As`. Both patterns are
fine; the choice is at the package author's discretion.

**Lint encoding.** `errcheck` (every returned error is handled or
discarded with `_`), `govet`'s `errorsas` analyzer (catches
`errors.As(err, &target)` where `target` is not a pointer to an
error-implementing type), and `staticcheck`'s SA-error rules.

## 7. Imports: standard library, then third-party, then local

`goimports` (formatter block in `.golangci.yml`) groups imports
into three blocks separated by blank lines:

```go
import (
    "flag"
    "fmt"
    "os"

    "golang.org/x/tools/go/packages"

    "github.com/gada-lang/gada/compiler/internal/version"
)
```

The third block is anything under `github.com/gada-lang/gada/...`.
This is the standard `goimports` `-local` convention; the
formatter handles it automatically when run as part of
`make lint`.

## 8. What this document does *not* try to settle

- **Tab vs. space, brace placement, semicolon style.** `gofmt`
  is the source of truth. There is no project debate.
- **Internal-only structural decisions.** Whether a helper goes
  in `internal/parse/` or `internal/translate/`, whether a
  factory takes a `Config` struct or three positional arguments,
  whether to use generics or interface{} — these are review-time
  judgement calls, not style-doc rules. The rule is whatever
  the existing surrounding code does, unless an ADR overrides.
- **Test framework.** The standard library `testing` package is
  what we use today; whether testify or another assertion
  library lands later is a separate decision. When it does, this
  section gets a paragraph and `.golangci.yml` may gain a
  matching exclusion.

## See also

- [`.golangci.yml`](../.golangci.yml) — the machine-checked form
  of this document. The active linter list (`errcheck`, `govet`,
  `staticcheck`, `gosec`, `unparam`, `revive` plus `gofmt` and
  `goimports` formatters) implements rules 1, 2, 4, 5, 6, and 7
  mechanically.
- [[0001-go-frontend-via-go-ast]] — the ADR that pins the
  compiler as a Go program, forcing a Go style guide to exist
  in the first place.
- [[CONTRIBUTING]] — links here from its *Style* section so that
  a new contributor reads this document before submitting their
  first Go PR.
