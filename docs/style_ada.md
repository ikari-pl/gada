---
type: style
title: GADA Ada style guide
created: 2026-05-01
tags: [style, ada, runtime, lint]
related:
  - "[[0000-record-architecture-decisions]]"
  - "[[0002-runtime-layered]]"
  - "[[0003-gc-boehm-for-v1]]"
  - "[[0004-scheduler-libco-for-v1]]"
  - "[[CONTRIBUTING]]"
---

# GADA Ada style guide

This document is the canonical style reference for every Ada source
file under `runtime/` (and, when they land, `stdlib/` and any other
Ada-side trees). It is the human-readable companion to the
machine-checked rule set in [`tools/gnatcheck.rules`](../tools/gnatcheck.rules):
every rule listed here either is already enforced by gnatcheck on the
CI Ubuntu runner, or is documented as the "Why" entry behind a rule
in that file. The two documents are intended to stay in lockstep —
adding a project rule means adding *both* a paragraph here and a
gnatcheck entry there.

The style decisions here are downstream of [[0002-runtime-layered]]
(the `Gada.X.Y` namespace and the no-upward-`with` rule),
[[0003-gc-boehm-for-v1]] (the GC interface lives in `Gada.Core`,
which constrains what `Gada.Core`'s spec may expose), and
[[0004-scheduler-libco-for-v1]] (Ravenscar-friendliness rules out
exception handlers in elaboration code). When a rule below cites an
ADR, that ADR is the single source of truth — this document is the
operational form, not the rationale.

## 1. Naming: every package starts with `Gada`

Every package, generic, and library-level unit in the runtime is
rooted at `Gada` and follows the `Gada.X.Y` form:

- `Gada` is the umbrella namespace package (`runtime/src/gada.ads`).
  It is `pragma Pure` and contains no declarations — it exists only
  to anchor the namespace.
- `Gada.Core`, `Gada.Async`, `Gada.Reflect`, `Gada.Std` are the four
  layers ratified in [[0002-runtime-layered]]. Each has a body even
  when its spec is empty (via `pragma Elaborate_Body` — see
  `runtime/src/gada-core.ads` for the rationale comment).
- Every concrete unit lives at depth ≥ 2 (e.g., `Gada.Core.IO`,
  `Gada.Async.Channels`, `Gada.Std.Encoding.Json`). Flat
  `Gada.Foo` packages with no layer prefix are forbidden — the
  layer prefix is what makes layering reviewable.
- Transpiled user code lives under `Gada.User.<module-path>`
  (e.g., `Gada.User.Github_Com.Gada_Lang.Example`). The `Gada.User`
  prefix is reserved for the compiler; user code never lands at
  `Gada.<anything-else>`.

**Lint encoding.** Rule discovery is by inspection today: a future
gnatcheck custom-rule plugin (or a `tools/check_namespace.sh` shell
script) will mechanise the "every unit starts with `Gada.`" check.
Until then, the convention is enforced at review time and by the
Alire crate boundary — each layer's `.gpr` file lists only its own
sources, which catches accidental top-level `Foo.Bar.ads` files at
build time.

## 2. File layout: `-` separator maps `.` to path

GNAT's standard file-naming convention is non-negotiable here:
the compilation-unit name `Gada.Core.IO` lives in the file
`runtime/src/gada-core-io.ads` (spec) and `gada-core-io.adb` (body).
Lowercase, hyphens for dots. This is GNAT's `gnatname` default and
the layout `gprbuild` expects — deviating breaks the build.

- All runtime sources live under `runtime/src/`. Subdirectories
  inside `src/` are not used for v1.0; the flat layout matches the
  Alire crate convention and keeps `gnatcheck`'s `--files=` lists
  short.
- Tests live under `runtime/tests/`, follow the same naming rule,
  and the test driver is always `runtime/tests/test_runner.adb`.
- Spec (`*.ads`) and body (`*.adb`) for the same unit are siblings
  in the same directory — never split across `src/` and another
  tree.

## 3. Comment style: every public subprogram has a `Purpose` line

Every public subprogram declared in a package spec carries a
"Purpose" comment — a short paragraph immediately following the
declaration that says what the subprogram does, what it returns,
and (when relevant) what side effect it has. The style follows
the existing runtime examples (`runtime/src/gada-core-io.ads`):

```ada
   procedure Println (Text : String);
   --  Write `Text` followed by a single line terminator (LF on Unix,
   --  whatever the host runtime considers `New_Line` on other targets)
   --  to the current default output. Equivalent to Go's
   --  `fmt.Println(text)` for a single string argument.
```

Rules of the form:

- The first line is a single sentence, active voice, present tense
  — *"Write ..."* not *"Will write ..."* or *"This subprogram
  writes ..."*. The point is operational documentation, not prose.
- When the subprogram corresponds to a Go-side primitive, name the
  Go equivalent in backticks (`fmt.Println(text)` above). This is
  what makes the runtime story navigable from the compiler side.
- When the subprogram has a layering implication (e.g., calls a
  lower-layer primitive, must not be called from `Gada.Core`),
  note the layer in the same comment. The reviewer's job is to
  verify the layering against [[0002-runtime-layered]] from the
  Purpose line alone.
- Internal (non-public) subprograms that are obvious from their
  body do not require Purpose comments. Apply judgement: if a
  reviewer would have to read the body to know what the helper
  does, write the Purpose comment.

Every package spec also carries a top-of-file comment block
explaining the package's role in the layering and naming any
non-obvious dependencies. `runtime/src/gada-core-io.ads` is the
worked example — copy its shape.

**Lint encoding.** This rule is the *Why* behind the
`+RHeaders:Header=tools/header_ada.txt` placeholder in
`tools/gnatcheck.rules`. The placeholder is currently
commented out because `tools/header_ada.txt` does not yet exist;
re-enabling the rule (Phase 1 follow-up item) requires landing the
header template alongside this style doc and pointing the rule at
it. Until then, header presence is checked at review time.

## 4. No `goto`

Ada permits `goto`, GADA forbids it. The control-flow primitives
that goto would be used for (early exit, error unwinding) are
covered by `return`, `exit`, `raise`, and structured `if`/`case`.

**Lint encoding.** `+RGOTO_Statements` in
`tools/gnatcheck.rules`. CI fails any new goto.

## 5. No global mutable state in package specs

Package specifications declare types, constants, generics, and
subprogram signatures. They do *not* declare mutable variables.
Mutable state lives in package bodies (where it can be hidden behind
accessors) or in objects passed by reference to subprograms. The
exceptions are:

- `constant`s of any type — these are not mutable.
- Type definitions, including tagged types and access types.
- Protected objects whose entries gate the mutability — the
  protection is the mutability rule.

The rule exists because spec-level mutable state is invisibly
shared across every unit that `with`s the package, which destroys
the layering story in [[0002-runtime-layered]] and makes
elaboration order matter in ways that are hard to reason about
on Ravenscar.

**Lint encoding.** `+RGlobal_Variables` in
`tools/gnatcheck.rules`. CI fails any new spec-level mutable
variable.

## 6. No upward or sibling `with` between layers

This is the lint-form of [[0002-runtime-layered]]. Within
`runtime/src/`:

- A unit in `Gada.Core` may not `with Gada.Async`,
  `with Gada.Reflect`, or `with Gada.Std`.
- A unit in `Gada.Async` may not `with Gada.Reflect` or
  `with Gada.Std`. It *may* `with Gada.Core`.
- A unit in `Gada.Reflect` may not `with Gada.Async` or
  `with Gada.Std`. It *may* `with Gada.Core`.
- A unit in `Gada.Std` may `with` any lower layer.

The rule is mechanically checkable from the unit name alone: if
`with Gada.X.Y` appears in a file whose unit name has prefix
`Gada.A.B`, the (`A`, `X`) pair must satisfy a strict downward
ordering (`Core < Async = Reflect < Std`, with sibling `Async`/
`Reflect` disjoint).

**Lint encoding.** A `tools/check_layering.sh` script (planned for
Phase 1) walks `runtime/src/*.ad?` and the layer GPRs, parses
`with` clauses, and exits 1 on any upward or sibling-cross-layer
edge. Today the rule is enforced at review time and by the
per-layer `.gpr` file's source list (a sibling-`with` would fail
to find the unit because the `.gpr` doesn't include the other
layer's source dir).

## 7. Public spec → at least one test

Every public subprogram exported from a package spec has at least
one corresponding AUnit test in `runtime/tests/`. The test calls
the subprogram with one valid input and at least one invalid
input (where "invalid" means a precondition violation, an empty
slice, etc.) so that both the success and failure paths are
exercised. This is the operational form of `AGENTS.md` design
principle #1's "Every public API has at least one direct unit
test" — the runtime side targets **100% line coverage**, so a
public subprogram with no test will fail the coverage gate
regardless of this rule.

The current example is `runtime/tests/io_suite.adb`'s
`Test_Println_Emits_Hello_GADA`, which redirects `Ada.Text_IO`
output, calls `Gada.Core.IO.Println`, reads back the captured
bytes via `Ada.Streams.Stream_IO`, and asserts the byte-exact
output. New runtime primitives ship with a similarly direct
test.

## 8. Additional baseline rules (already enforced)

The following are gnatcheck rules already enabled in
`tools/gnatcheck.rules`. They are well-understood, the current
codebase satisfies them by inspection, and CI rejects any
regression:

- **No anonymous arrays or anonymous subtypes**
  (`+RAnonymous_Arrays`, `+RAnonymous_Subtypes`) — promotes named,
  documented types so that signatures remain readable.
- **No exception handlers in elaboration code**
  (`+RExceptions_As_Control_Flow`) — Ravenscar-friendly, and
  forced by [[0004-scheduler-libco-for-v1]]'s Ravenscar-mode
  guarantees.
- **Maximum line length 100 columns** (`+RMax_Line_Length:100`) —
  the GADA project convention. 100, not 80, because the existing
  Ada-community 79-column limit is hostile to descriptive
  identifier names (`Gada.Std.Encoding.Json.Decoder` already eats
  35 columns of a 79-column line) and to the runtime's use of
  fully-qualified package names in `with` clauses.
- **No `with` clauses for unused units** (`+RUnused_With_Clauses`)
  — keeps the layering story honest. An unused upward `with` is
  often a trace of an aborted layering violation.

## 9. What this document does *not* try to settle

- **Personal indentation preferences.** GNAT's default formatter
  (3-space indent, aligned `is`, aligned `:=`) is what `make ci`
  enforces; deviations are not relitigated here. If a future
  reformatter pass changes the canonical layout, both the
  reformatter command and this section are updated together.
- **Header copyright notices.** TBD pending the project license
  decision (`AGENTS.md` §License says license is TBD). When that
  lands, `tools/header_ada.txt` ships with the chosen header and
  `+RHeaders` flips on.

## See also

- [`tools/gnatcheck.rules`](../tools/gnatcheck.rules) — the
  machine-checked form of this document.
- [[0002-runtime-layered]] — the layering ADR; the no-upward-`with`
  rule and the `Gada.X.Y` naming rule are its lint-encodable
  consequences.
- [[CONTRIBUTING]] — links here from its *Style* section so that a
  new contributor reads this document before submitting their first
  Ada PR.
