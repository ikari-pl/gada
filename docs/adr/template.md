---
type: adr
title: "ADR-NNNN: Short decision title"
status: proposed
created: YYYY-MM-DD
deciders: []
tags: []
related: []
---

# ADR-NNNN: Short decision title

> **How to use this template.** Copy this file to
> `docs/adr/NNNN-kebab-title.md`, replacing `NNNN` with the next free
> four-digit number (zero-padded) and `kebab-title` with a short
> hyphenated phrase that names the decision (not the question).
> Update every front-matter field, then write the four sections below.
> See [[0000-record-architecture-decisions]] for the full convention.

## Context

What is the situation that forces a decision? State the problem
neutrally — facts, constraints, forces in tension — without telegraphing
the answer. A reader who disagreed with the eventual decision should
still recognize their concerns in this section. Reference the roadmap
item or design document that motivated the work (`[[roadmap/NN-name]]`)
so the historical chain is reconstructible later.

Keep it tight: 1–3 paragraphs. ADRs are read by future agents under
time pressure; long context sections do not get read.

## Decision

State the decision in the active voice, present tense:
**"We use X."** *not* "We will use X" or "X was chosen."
The ADR records what is *true now* in the codebase. Tense drift makes
ADRs feel aspirational and erodes their authority.

If the decision has multiple parts (e.g., "X for hosted targets, Y for
Ravenscar"), enumerate them as a numbered list — each item should
stand on its own as a testable claim.

## Consequences

Three sub-bullets, in this order:

- **What now becomes easier.** Concrete capabilities the team
  picks up. ("We get free type information from `go/types`.")
- **What now becomes harder.** Non-imaginary costs. ("We are tied to
  the Go release we vendor.")
- **What is now off-limits.** Decisions this one *closes off*.
  ("We do not write our own Go parser. A PR proposing one is
  rejected unless it supersedes this ADR.")

This third bullet is the most important and the most often skipped.
An ADR that does not name what it forecloses is not load-bearing.

## Alternatives considered

Briefly: each option that was on the table, what its strengths were,
why it lost. One paragraph per alternative is plenty. The point is
not to refight the decision — it is to leave a record so a future
reader (or a superseding ADR) does not have to rediscover the
options from scratch.

If the alternatives were not seriously considered, say so. "We did
not survey alternatives because the constraint X made the decision
forced" is a valid entry, and more honest than fabricating a
comparison after the fact.
