# libco — vendored userspace coroutine library

This directory holds a verbatim copy of selected files from the
[higan-emu/libco](https://github.com/higan-emu/libco) project. libco
provides the cooperative-context-switching primitive used by GADA's
goroutine scheduler on hosted targets, per
[`docs/adr/0004-scheduler-libco-for-v1.md`][adr-0004].

The vendoring policy — why the source lives here, which platforms
are part of the v1 contract, how the licence is preserved — is set
by [`docs/adr/0007-libco-vendoring.md`][adr-0007]. This README is
the operational record: which upstream commit is on disk, what was
copied, what was left behind.

[adr-0004]: ../../../../docs/adr/0004-scheduler-libco-for-v1.md
[adr-0007]: ../../../../docs/adr/0007-libco-vendoring.md

## Upstream pin

```
[upstream]
url     = https://github.com/higan-emu/libco
commit  = e18e09d634d612a01781168ad4d76be10a7e3bad
date    = 2024-09-09
message = Fix all "declaration after statement" warnings, for greater C89 compatibility.
```

To bump the pin, run a dedicated `vendor: bump libco to <SHA>`
commit that:

1. `git clone --depth 1 https://github.com/higan-emu/libco /tmp/libco-src`
2. `git -C /tmp/libco-src rev-parse HEAD` — record the new SHA in
   the block above.
3. Copy the files listed under "Vendored files" verbatim.
4. Run the AUnit context suite (`make -C runtime test
   PKG=async.context`) to confirm the bump is benign.
5. Commit. Do not bundle the bump with feature work.

## Vendored files

| File         | Purpose                                                    | Licence      |
|--------------|------------------------------------------------------------|--------------|
| `libco.h`    | Public API + `LIBCO_C`-gated settings macros               | ISC          |
| `libco.c`    | Dispatcher — `#include`s the right per-arch implementation | ISC          |
| `settings.h` | `thread_local` / `alignas` portability shims               | ISC          |
| `amd64.c`    | x86_64 implementation (Linux/macOS/Win64)                  | ISC          |
| `aarch64.c`  | ARM 64-bit implementation (Linux/macOS)                    | ISC          |
| `valgrind.h` | Stack-register hints for Valgrind (used by amd64+aarch64)  | BSD-style †  |
| `LICENSE`    | Upstream licence file, verbatim                            | —            |

† `valgrind.h` is licensed under a BSD-style notice reproduced at
the top of the file itself, *not* under the ISC notice. The
upstream `LICENSE` calls this out explicitly: "The above applies
to all files in this project except valgrind.h which is licensed
under a BSD-style license. See the license text and copyright
notice contained within that file." Both notices flow through to
any GADA distribution that links libco; ADR-0007 documents the
attribution path.

## Files NOT vendored

| File             | Why                                                                |
|------------------|--------------------------------------------------------------------|
| `arm.c`          | 32-bit ARM — outside the v1 platform matrix (ADR-0007 §4)          |
| `x86.c`          | 32-bit x86 — outside the v1 platform matrix                        |
| `ppc.c`          | PowerPC big-endian — outside the v1 platform matrix                |
| `ppc64v2.c`      | PowerPC ELFv2 — outside the v1 platform matrix                     |
| `fiber.c`        | Win32 Fibers — Windows-hosted is post-1.0                          |
| `sjlj.c`         | setjmp/longjmp fallback — not needed on covered platforms          |
| `ucontext.c`     | POSIX ucontext fallback — not needed on covered platforms          |
| `doc/`           | Upstream design notes — useful for maintainers but not the build   |
| `README.md`      | Replaced by this file                                              |

A future ADR can supersede ADR-0007 to widen the matrix and add
back any of the above. Until then, do not vendor them — drift
between "vendored but unused" and "actually used" sources is the
class of bug this exclusion list prevents.

## Per-architecture source selection

`gada_core.gpr` compiles exactly *one* of `amd64.c` / `aarch64.c`
per build via the `ARCH` scenario variable (set by
`runtime/Makefile` from `uname -m` and exported into the
`external ("ARCH", ...)` call inside the gpr). The build system
is the right layer to know the target arch (ADR-0007 §5).

`libco.c` (upstream's dispatcher) is **not compiled** — it is
listed in `Excluded_Source_Files` for every supported arch.
libco.c works by `#include`ing the per-arch source via an
`#if defined(__amd64__)` cascade; if it were compiled it would
produce a second translation unit defining the same `co_*`
symbols the per-arch file already defines, breaking the link
with duplicate-symbol errors.

Why keep libco.c on disk if we never compile it? Because removing
it would be a per-file deviation from upstream that the
`vendor: bump libco` workflow would have to remember. Keeping the
upstream tree as-is (and excluding at the build layer) means a
bump is a verbatim copy plus a SHA edit — no diff against
upstream beyond the README pin block.

## Reading the upstream

If you are debugging a libco-side issue and want to read the
upstream's history rather than this snapshot:

```bash
git clone https://github.com/higan-emu/libco /tmp/libco-upstream
cd /tmp/libco-upstream
git log --oneline e18e09d^..HEAD     # commits since our pin
```
