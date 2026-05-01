# GADA — Project Manifest

> This file is also accessible as `CLAUDE.md` (symlink). It is the single
> source of truth for **what GADA is**, **what GADA is not**, and **how
> agents work in this repository**. Read this first.

## What GADA is

**GADA** (Go-on-Ada) is a transpiler-plus-runtime that takes Go source code
and produces Ada source code which executes against a Go-semantics-preserving
runtime library implemented in Ada. The deliverable is a Go program running
on the GCC Ada toolchain, with goroutines, channels, slices, maps,
garbage collection, and a meaningful subset of the Go standard library —
but on platforms, with scheduling guarantees, and with verification
properties that vanilla Go cannot reach.

The project name follows the obvious pattern: **G**o on **ADA**.

## Pure goals

These are the load-bearing commitments. Every design decision should be
traceable back to one of these:

1. **A useful subset of Go runs unmodified on the Ada toolchain.** From
   hello-world to programs of `prometheus-client_golang` complexity. A
   program that builds with `go build` should transpile to Ada that builds
   with `gprbuild` and behaves identically for I/O, arithmetic, control
   flow, concurrency, and standard-library calls.

2. **Ada's strengths are exposed where Go's would have been sufficient.**
   Goroutines get priorities, deadlines, and ceiling-locking when the user
   asks for them. The scheduler is Ravenscar-compatible at the appropriate
   compile target. The output binary is a single statically-linkable
   executable deployable to any GCC-Ada target without a Go runtime
   install.

3. **Bidirectional Ada/Go interop is a first-class feature.** An Ada program
   can `with` a transpiled Go package and call its public functions
   naturally. A Go program can call into Ada packages via a `gada-import`
   directive. The boundary is one binary, not an FFI.

4. **The verification path is real.** For Go code that respects SPARK rules
   (no unsafe aliasing, no exceptions, bounded data, no dynamic dispatch in
   verifiable contexts), the compiler emits SPARK source, and `gnatprove`
   verifies the program. The verifiable-subset target (`gada build
   -mode=spark`) is a build-time choice, not a separate tool.

5. **Cross-compilation reach.** GCC's Ada frontend targets ~30 architectures.
   Stock Go targets ~15. GADA = Go on AIX/POWER, OpenVMS/Itanium,
   Solaris/SPARC, OpenBSD/SPARC64, ARM Cortex-M with Ravenscar,
   anything GCC supports.

## Non-goals

These are explicitly out of scope. Saying so up front avoids relitigation:

- **Performance parity with `gc` (Go's reference compiler).** Not the point.
  *Availability* on platforms `gc` cannot reach is. We will measure
  performance honestly, and we expect to be slower on most workloads on
  most platforms.
- **100% Go semantics on day one.** Reflection beyond `reflect.TypeOf` /
  `reflect.ValueOf` / basic struct walking is post-1.0. `unsafe` is opt-in
  with explicit module annotations. `cgo` is post-1.0. Generics in Go 1.18+
  are in scope.
- **Writing our own GC.** Boehm-Demers-Weiser is the v1 GC. A precise GC
  may be a research effort later; it is not a 1.0 deliverable.
- **Embedding ourselves in the Go ecosystem.** GADA lives in the Ada
  ecosystem, depends on Alire for Ada packages, and consumes Go source
  as input. We will publish to crates.io-equivalents only where doing so
  serves an Ada user.
- **Replacing `gc` for Go developers.** GADA's audience is Ada developers
  who need Go libraries, embedded engineers who need Go on tiny targets,
  and certification-track teams who need a verifiable Go subset. Cloud-Go
  developers are not the target user.

## Design principles

### 1. Every behavior is unit-tested before it ships

This is not aspirational; it is gating. Coverage targets are:

- **100% of executable lines** in `runtime/` packages must be covered by
  unit tests. Deviations are documented per package in
  `runtime/<package>/COVERAGE.md` with rationale and an explicit
  reviewer-approved exception.
- **≥ 90% of executable lines** in `compiler/` packages, with `≥ 95%` for
  the AST-emission and type-translation layers (the most bug-sensitive
  parts).
- **Every public API has at least one direct unit test** that calls it
  with valid inputs and at least one with invalid inputs.
- **Every fixed bug has a regression test.** No exceptions.

Coverage is measured in CI on every PR. A drop below threshold blocks
merge. Tooling: `gcov` + `lcov` + `genhtml` for Ada (or `gnatcoverage`
where available); `go test -cover` + `go tool cover` for Go.

### 2. The transpiler is itself a Go program

Reuse `go/ast`, `go/types`, `golang.org/x/tools/go/packages` for the entire
front-end. We do not parse Go ourselves; the Go team's tooling does that
work better than we will. Our transpiler eats typed AST and emits Ada
source.

### 3. The runtime is layered

```
GADA.Std       (Go standard library port: fmt, errors, strings, ...)
GADA.Reflect   (type metadata + reflect.TypeOf/ValueOf)
GADA.Async     (scheduler, channels, select)
GADA.Core      (slices, maps, defer, panic, GC interface)
```

Each layer depends only on layers below it. A program that uses no
goroutines can be linked without `GADA.Async`. A program that uses no
reflection can be linked without `GADA.Reflect`. This matters for
embedded targets and for the verifiable-subset compiler mode.

### 4. Verification commands are first-class artifacts

Every roadmap item, every package, every phase has an explicit
"how to know this is done" command that:

- exits 0 on success,
- prints a clear, actionable failure message otherwise,
- can be run by an agent, a human, and CI without modification.

If a verification command does not exist for a task, that is itself a
bug in the roadmap. Fix the roadmap before doing the work.

### 5. Small atomic commits

One concept per commit. Each commit:
- compiles,
- passes all tests,
- does not regress coverage,
- has a commit message body explaining *why*, not *what*.

There is no "I'll add tests later" register in this project.

## Repository layout (target)

```
gada/
├── AGENTS.md              # this file (symlinked as CLAUDE.md)
├── README.md              # user-facing overview
├── roadmap/               # phase-by-phase work checklist (one file per phase)
│   ├── README.md          # roadmap index + cross-cutting policy
│   ├── 00-foundation.md
│   ├── 01-minimal-transpiler.md
│   ├── ...                # 02 .. 11
│   └── future.md          # post-1.0 sketches
├── compiler/              # Go transpiler (Go module)
│   ├── cmd/gada/          # main entry point
│   ├── internal/ast/      # Go AST -> intermediate representation
│   ├── internal/types/    # type system bridging
│   ├── internal/emit/     # Ada source emission
│   └── testdata/          # transpiler tests (input.go + expected.adb)
├── runtime/               # Ada runtime library (Alire crate)
│   ├── alire.toml
│   ├── gada_core.gpr      # GADA.Core
│   ├── gada_async.gpr     # GADA.Async
│   ├── gada_reflect.gpr   # GADA.Reflect
│   ├── gada_std.gpr       # GADA.Std
│   ├── src/
│   └── tests/             # AUnit-based unit tests
├── stdlib/                # Go-stdlib-shaped Ada packages (auto-generated
│   │                      #   shells + hand-written impl bodies)
├── examples/              # transpilable Go programs used as integration tests
├── docs/                  # design notes, ADRs, architecture
└── tools/                 # build helpers, coverage scripts, CI wiring
```

## How agents work in this repository

When picking up a task:

1. **Open `roadmap/README.md`.** It is the index and cross-cutting
   policy. Find the active phase (`Status: IN_PROGRESS`) in the table.
   If no phase is `IN_PROGRESS`, find the lowest-numbered `NOT_STARTED`
   phase whose prerequisites are `DONE`, open its file (e.g.,
   `roadmap/00-foundation.md`), and announce the intent to start it.

2. **Find an unchecked item** (`- [ ]`) within that phase whose own
   prerequisites (if any) are checked off. Pick the lowest item.

3. **Read the verification command.** If absent, your *first* job is to
   add a verification command to the roadmap. Then proceed.

4. **Implement.** Make the verification command pass. Add unit tests.
   Coverage of touched code must not regress.

5. **Run the full test suite** (`make test`) and the coverage gate
   (`make coverage-gate`). Both must be green.

6. **Mark the item `[x]`** in the relevant phase file under
   `roadmap/`. Commit. Commit message format:

   ```
   <area>: <one-line summary>

   <body explaining why, with reference to roadmap/<phase-file>.md item>
   ```

7. **If the item completes a phase** (every item checked + phase
   exit-criteria verification passes), update the phase file's
   `Status:` from `IN_PROGRESS` to `DONE`, update the row in
   `roadmap/README.md`'s phase table to match, set the next phase
   to `NOT_STARTED` → `IN_PROGRESS` if its prerequisites are met
   (in *both* the next phase file's `Status:` and the index table),
   and commit the roadmap update as its own atomic change.

### Working sub-tasks

If an item is too large to fit one commit, decompose it into sub-items
*in the relevant phase file*, each with its own verification command.
Update the file, commit that update, then begin work on the sub-items.
Never decompose silently in your head — the phase file should always
reflect the current decomposition so the next agent can pick up where
you left off.

### Failures

If a verification command fails after implementation:

1. Do not "make it pass" by gaming the test. Read the failure, find the
   real cause, fix it.
2. If the failure surfaces a roadmap-level wrong assumption (e.g. "this
   approach won't work on macOS"), stop, document the finding in the
   roadmap as a sub-item, and request human review before proceeding.

### Branch & PR workflow

- Each phase lives on a branch: `phase/NN-description` (e.g.,
  `phase/03-concurrency-runtime`).
- Each item completed pushes a commit to that branch.
- Phase completion = PR to `main` with the phase's exit-criteria
  output pasted in the PR description.
- `main` is always green. CI gates: build, test, coverage threshold, lint.

## What "honest" means in this repo

- Performance numbers are measured against stock Go (`gc`-built binaries
  on the same hardware), reported as ratios, and tracked over time.
- Failed approaches are documented in `docs/adr/` (Architecture Decision
  Records) so we don't repeat them.
- "Doesn't work yet" is a valid status; "works but slow" is reportable;
  "broken in subtle ways" is *not* shippable. We don't ship known
  silent breakage.

## License

TBD by the project owner. Until set, treat all code as unlicensed and
do not redistribute.
