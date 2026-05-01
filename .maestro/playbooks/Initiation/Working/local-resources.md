# GADA — Local resources on this host

Cross-session reference for paths and tools that live outside the
project tree but are relevant to GADA work.

Last updated: 2026-05-01.

## GNAT Studio source

- **Path:** `~/src/gnatstudio`
- **What it is:** AdaCore's GNAT Studio IDE source repository (cloned).
- **What it is NOT:** an installed Ada toolchain. There are no
  `gnat`, `gprbuild`, `gnatls`, or `gnatprove` binaries anywhere
  under this tree. `_build/Applications/GNATStudio.app` is the
  built IDE bundle only.
- **Why it matters for GADA:**
  - It's a real-world Ada/GtkAda codebase — useful as a *reference*
    for idiomatic project layout, `.gpr` files, and GNATCOLL usage
    when designing `runtime/` (`GADA.Core`, `GADA.Async`, etc.).
  - It is **not** a substitute for a working compiler. To build the
    GADA Ada runtime you still need to install GNAT separately
    (Alire `alr toolchain --select`, or FSF GNAT via Homebrew, or
    AdaCore's GNAT Community).
- **Do not** add it to `PATH` expecting `gnat` / `gprbuild` to
  resolve. They won't.

## Where to record future local-resource discoveries

Append new entries to this file rather than scattering them across
playbook docs. One section per resource, with: path, what it is,
what it is not, why it matters for GADA.
