---
type: adr
title: "ADR-0000: Record architecture decisions as ADRs"
status: accepted
created: 2026-05-01
deciders: [gada-core]
tags: [meta, process, documentation]
related:
  - "[[CONTRIBUTING]]"
  - "[[roadmap/00-foundation]]"
  - "[[template]]"
---

# ADR-0000: Record architecture decisions as ADRs

## Context

GADA is a multi-year project that will outlive the memory of any
single contributor. The load-bearing decisions — the choice of Go
frontend, the runtime layering, the GC, the scheduler — are
already encoded in `AGENTS.md` and `README.md` as prose, but those
files mix *what is true now* with *how to work in this repo* and
*what we are trying to achieve*. When a future agent asks "why did
we pick Boehm GC?", the answer should not require archaeology
across three files and a year of git log.

We need a place where every load-bearing technical decision is
recorded once, never deleted, and easy to find. The Architecture
Decision Record (ADR) pattern, originally articulated by
Michael Nygard and standardized as MADR (Markdown ADR), is the
industry-standard answer. This ADR adopts it.

We also need the records themselves to be *navigable*. GADA's
journal entries already use YAML front matter and `[[wiki-link]]`
cross-references so the `docs/` tree renders as a graph in
Obsidian and DocGraph viewers (see
`docs/journal/2026-04-30-foundation-bootstrap.md`). ADRs must follow
that same convention so the architecture story is reachable from
the same graph.

## Decision

We record every load-bearing technical decision as an ADR under
`docs/adr/`. Concretely:

1. **Location.** All ADRs live in `docs/adr/`. There is no nested
   structure — the directory is flat.
2. **Naming.** `NNNN-kebab-title.md`, where `NNNN` is the next
   free four-digit zero-padded number, monotonically allocated
   across the whole project, and `kebab-title` is a short
   hyphenated phrase that names the *decision*, not the question
   (good: `gc-boehm-for-v1`; bad: `which-gc-do-we-use`).
3. **Template.** Every ADR uses `docs/adr/template.md` as its
   starting point. The template encodes MADR-style YAML front
   matter (`type`, `title`, `status`, `created`, `deciders`,
   `tags`, `related`) and four sections: `## Context`,
   `## Decision`, `## Consequences`, `## Alternatives considered`.
4. **Lifecycle.** An ADR moves through three states and *is never
   deleted*:
   - `proposed` — opened for discussion, may be edited freely.
   - `accepted` — the decision is in force; the file is now
     historical record. Edits are typo fixes only.
   - `superseded` — a later ADR has replaced this one. Add a
     `Superseded by [[NNNN-...]]` line at the top of the body and
     flip the front-matter `status`. Do not delete the file or
     rewrite its `Decision` section. The point of the ADR record
     is to preserve the historical reasoning, including reasoning
     that turned out to be wrong.
5. **Cross-references.** ADRs cross-link to each other and to
   roadmap files via `[[wiki-link]]` syntax — `[[ADR-0002]]` for
   another ADR, `[[roadmap/01-minimal-transpiler]]` for a roadmap
   file, `[[CONTRIBUTING]]` for the contributor guide. This makes
   `docs/adr/` a graph of decisions navigable in Obsidian, in the
   Maestro DocGraph viewer, and (through fallback link rendering)
   on GitHub.
6. **Style guides are referenced from ADRs.** The Ada and Go
   style documents (`docs/style_ada.md`, `docs/style_go.md`) are
   referenced from the ADRs whose decisions they encode in lint
   form: `docs/style_ada.md` from [[ADR-0002]] (the runtime
   layering decision shapes the `Gada.X.Y` naming rule), and
   `docs/style_go.md` from [[ADR-0001]] (the Go-frontend decision
   forces the `github.com/gada-lang/gada/...` module path).
7. **When to write an ADR.** Any decision that is *load-bearing*
   for the architecture and that a future agent could reasonably
   second-guess. Heuristic: if you can imagine someone six months
   from now writing "why on earth did they pick X over Y" in a PR
   comment, write the ADR before they have to ask. Routine
   implementation choices (which loop construct, which helper
   name) are out of scope — those go in code review.

## Consequences

- **What now becomes easier.** Onboarding a new contributor or
  agent: the architecture story is a numbered, hyperlinked list,
  not a `git log` excavation. Reversing a decision is a
  well-defined ritual (write a new ADR, supersede the old one,
  link both ways) rather than an act of forgetting. The DocGraph
  viewer turns `docs/adr/` into a clickable map of the project's
  reasoning.
- **What now becomes harder.** Every load-bearing decision now
  requires a written ADR before it is acted on in code. This
  is intentional friction: it is much cheaper to discover a bad
  decision while writing the `## Alternatives considered` section
  than after a thousand lines of code commit to it. Drive-by
  architectural changes that bypass an ADR are *bugs in process*
  and will be reverted at review time.
- **What is now off-limits.** Deleting an ADR. Editing the
  `## Decision` section of an `accepted` ADR (instead, write a
  superseding ADR). Recording a decision purely in `AGENTS.md`,
  `README.md`, or commit messages when an ADR would be load-
  bearing — any one of those will eventually drift, and the ADR
  is the single source of truth for the architecture story.

## Alternatives considered

**No structured records, rely on `git log` + `AGENTS.md`.** This
is the status quo before this ADR. It works for a small project
with one or two contributors who remember every decision. It
does not work for a multi-year, multi-agent project — the cost
of "why did we pick X" archaeology grows superlinearly with the
number of decisions and the turnover of contributors. Rejected.

**RFC-style design documents in `docs/rfc/`.** RFCs are larger,
slower, and front-loaded — they describe a *proposed* change in
detail before it is built. ADRs are smaller, faster, and
back-loaded — they record what was *already decided*, often as
a one-line summary plus the consequences. The two are
complementary; we may add `docs/rfc/` later for changes large
enough to warrant a design phase. For now ADRs are sufficient
and lower-overhead.

**Architecture journal in `docs/journal/`.** The journal already
exists and is the right place for *narrative* (what shipped this
week, what we learned, what we deferred). ADRs are the right
place for *decisions* (what is now true and why). They serve
different readers: the journal serves the human looking for
context on the last sprint; the ADR serves the agent looking for
the rule that governs a piece of code. Both are kept; they do
not substitute for each other.

**MADR vs. Nygard's original format.** MADR adds YAML front
matter and a stricter section list; Nygard's original is freer.
We pick MADR because the YAML front matter is what makes the
graph rendering work in Obsidian and DocGraph — without it, the
files are unstructured text and the graph collapses to plain
links.

## See also

- [[template]] — the file every new ADR is copied from.
- [[CONTRIBUTING]] — the contributor guide; references this ADR
  for the "when do I write an ADR?" question.
- [[roadmap/00-foundation]] — the roadmap phase under which this
  ADR was written; the **Architecture Decision Records (ADR)
  directory** item is closed by this file plus `template.md`.
