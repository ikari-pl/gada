---
type: adr
title: "ADR-0001: Use upstream go/ast, go/types, and packages for the Go front-end"
status: accepted
created: 2026-05-01
deciders: [gada-core]
tags: [compiler, frontend, go, parsing, types]
related:
  - "[[0000-record-architecture-decisions]]"
  - "[[0002-runtime-layered]]"
  - "[[roadmap/01-minimal-transpiler]]"
  - "[[style_go]]"
---

# ADR-0001: Use upstream go/ast, go/types, and packages for the Go front-end

## Context

GADA must consume Go source code and produce semantically equivalent
Ada source code. To do that, the compiler needs three things from the
input: a parsed syntax tree, a fully resolved type for every
expression, and the dependency graph across packages and modules. All
three are non-trivial: Go has type inference, generics, embedded
interfaces, type aliases, dot-imports, build tags, internal-package
visibility, and a module-resolution algorithm whose corner cases have
been litigated for years inside the upstream Go project.

We have two choices for each of those three responsibilities: write
our own, or call into the canonical Go toolchain's libraries
(`go/ast`, `go/types`, `golang.org/x/tools/go/packages`). The first
option gives us a self-contained tool with no Go dependency at the
front-end. The second option gives us bug-for-bug compatibility with
upstream Go at the cost of a permanent dependency on the Go release
we vendor.

This ADR resolves that question once for the lifetime of v1.0. It is
anchored in `AGENTS.md` design principle #2 ("The transpiler is itself
a Go program. Reuse `go/ast`, `go/types`, `golang.org/x/tools/go/packages`
for the entire front-end") and forced by the practical constraint that
matching upstream Go semantics is a moving target — Go's type checker
gains features every release (generics in 1.18, range-over-func in
1.22, range-over-int in 1.22, `for` loop variable scoping change in
1.22) and we will not credibly chase it from a clean-room parser.

## Decision

We use the upstream Go toolchain's parsing and type-checking
libraries for the entire GADA compiler front-end. Concretely:

1. **Parsing.** We call `go/parser.ParseFile` (and
   `go/parser.ParseDir` for whole packages) to produce `*ast.File`
   trees. We do not write a Go parser.
2. **Type checking.** We call `go/types.NewChecker` (driven by
   `go/types.Config`) to produce a `*types.Info` that maps every
   `ast.Expr` to its `types.Type` and every `ast.Ident` to its
   `types.Object`. We do not implement type inference, method-set
   computation, embedded-field resolution, or generics
   instantiation ourselves.
3. **Package loading.** We use
   `golang.org/x/tools/go/packages.Load` with mode
   `packages.NeedName | NeedFiles | NeedCompiledGoFiles |
   NeedImports | NeedTypes | NeedSyntax | NeedTypesInfo` to resolve
   modules, build tags, and the import graph. We do not implement
   GOPATH/GOMODULE resolution, vendor-directory walking, or
   `go.mod`/`go.sum` parsing.
4. **Compiler binary.** The GADA compiler is itself a Go program,
   shipped as `compiler/cmd/gada` and built with the standard Go
   toolchain. The Go version we vendor in `compiler/go.mod` is the
   floor for GADA's input-Go-version support.
5. **No re-implementation.** Any time we are tempted to add a Go
   syntax helper, type-system helper, or package-resolution helper
   to GADA, the default answer is to find the upstream API that
   already does it. PRs that re-implement upstream Go libraries
   are rejected on sight unless they document an upstream bug or
   missing feature with a linked issue.

The decision is for v1.0 and beyond. Reversing it requires a
superseding ADR.

## Consequences

- **What now becomes easier.** We get a production-grade parser, a
  spec-conformant type checker, and a battle-tested package loader
  for free. We get free generics support — `go/types` resolves
  type-parameter instantiations and produces concrete `types.Type`
  trees that the emit layer can lower. We get free build-tag
  evaluation, free internal-package visibility checks, free
  module-resolution. The compiler's authoring complexity collapses
  to one job: typed-AST → Ada-IR → Ada source. That is a much
  smaller job than "all of the above plus a Go front-end."
- **What now becomes harder.** Our Go-version support is tied to
  the Go release we vendor. Adding Go 1.NN syntax requires bumping
  `compiler/go.mod` and re-vetting the emit layer for new
  AST-node kinds. The compiler binary will not run on a host
  without a Go toolchain available at build time; this rules out
  exotic GADA-on-GADA self-hosting scenarios for v1.0. We inherit
  upstream Go's bugs as well as its features — when `go/types`
  has a bug, our type information has the same bug. We cannot
  ship the compiler as a single Ada-built binary; it is and will
  remain a Go binary.
- **What is now off-limits.** Writing a Go parser. Writing a Go
  type checker. Writing a Go module resolver. Writing a Go
  build-tag evaluator. Writing a Go method-set or embedded-field
  algorithm. Each of these is a multi-person-year project that
  upstream has already done. A PR that adds one of them — even
  "just for the case we care about" — is rejected unless it
  supersedes this ADR with a documented upstream blocker. The
  GADA compiler is and remains a Go program; PRs proposing to
  rewrite it in Ada (a recurring suggestion from people who have
  not measured the front-end effort) are also off-limits under
  this ADR.

## Alternatives considered

**Hand-written Go parser and type checker in Ada.** This was the
"pure GADA" option: parse Go from inside the Ada toolchain so the
compiler is a single Ada binary deployable wherever GNAT runs.
Rejected. The Go specification is moving, the type checker is
genuinely subtle (generics, embedded interfaces, untyped constants,
shift-operand promotion), and a clean-room implementation will lag
upstream by years and harbor latent compatibility bugs forever.
The win — "no Go toolchain dependency" — does not pay for the
multi-person-year cost.

**Hand-written Go parser, reuse upstream types.** Splits the cost:
we own parsing but borrow type checking. Rejected. `go/parser` is
already free; rewriting just the parser saves nothing while
duplicating one of the most stable pieces of the Go toolchain.
There is no scenario in which this is the right tradeoff.

**LLVM-based Go front-end (gollvm or LLGo).** These exist as
research projects, but they are LLVM IR generators, not AST
producers. They do not help us emit Ada. Treating them as an AST
source layer would mean walking LLVM IR back to source-level
intent, which is strictly harder than starting from `go/ast`.
Rejected.

**TinyGo's front-end.** TinyGo uses upstream `go/ast` and
`go/types` but adds its own SSA pass on top. We would have to
fork TinyGo and strip its backend; the net is worse than calling
`go/ast` and `go/types` directly. Rejected.

## See also

- [[0000-record-architecture-decisions]] — the ADR convention this
  file follows.
- [[0002-runtime-layered]] — the runtime decision that pairs with
  this one. The compiler reads Go via this ADR's frontend; the
  runtime layering in ADR-0002 dictates what the compiler is
  allowed to emit calls into.
- [[style_go]] — the Go style guide the compiler itself is held
  to. Forced by this ADR: GADA's compiler is Go code, so the Go
  style guide governs it.
- [[roadmap/01-minimal-transpiler]] — the phase that consumes this
  ADR's frontend to ship the first end-to-end transpilation.
