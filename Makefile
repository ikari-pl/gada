# Top-level Makefile — orchestrates the Go compiler module and Ada runtime
# crate as one project.
#
# Per-side Makefiles in compiler/ and runtime/ own the build details
# (toolchain discovery, coverage instrumentation, lint config); this file
# coordinates them so a single `make ci` from the repo root exercises the
# whole project under the same gates CI applies.
#
# Design notes:
#   - Targets that depend on Phase 02 follow-up artifacts (coverage_gate.sh,
#     lint configs) gracefully no-op until those land. This lets `make ci`
#     stay green on the current tree while subsequent Phase 02 tasks only
#     have to flip on enforcement, not wire plumbing.
#   - All paths are derived from $(ROOT) (this file's dirname) so the
#     Makefile works regardless of caller CWD.
#   - PATH is augmented identically to runtime/Makefile so bare `make`
#     invocations (CI, Maestro agents, IDE tasks) find `alr` and friends.
#
# Targets:
#   bootstrap     — fetch Go deps and run `alr build` (notes missing tools).
#   test          — run both per-side test suites; first failure aborts.
#   coverage      — produce per-side coverage artefacts under coverage/ +
#                   a unified summary at coverage/summary.txt.
#   lint          — run both per-side lint targets (each soft-no-ops until
#                   the Phase 02 linting task lands its configs).
#   coverage-gate — enforce per-path thresholds via tools/coverage_gate.sh
#                   (soft-no-ops until that script lands in the next task).
#   example       — build the compiler if missing, run `gada build` against
#                   examples/$(HELLO)/, run the produced binary, and diff
#                   its output byte-for-byte against the example's
#                   expected_output.txt. Any divergence exits non-zero
#                   with the diff. Used by Phase 1's exit criterion.
#   ci            — lint → test → coverage → coverage-gate → roadmap-check.
#                   First failure aborts (Make's default semantics).
#   clean         — wipe per-side build state and coverage/.

.PHONY: bootstrap test coverage lint coverage-gate example ci clean

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
COVERAGE_DIR := $(ROOT)/coverage
GO ?= go

# Mirror runtime/Makefile's PATH augmentation so bare `make` invocations
# (CI, Maestro agents, IDE build tasks) can find `alr`/`gprbuild`/`lcov`
# at the top level. The per-side Makefiles handle their own PATH for
# invocations dispatched through `make -C ...`; this is for direct calls
# from this file (`alr build` in bootstrap, `lcov --summary` in coverage).
PATH := $(HOME)/src/gnatstudio/.tools/bin:$(HOME)/.local/share/alire/bin:$(HOME)/.local/bin:/opt/homebrew/bin:/usr/local/bin:$(PATH)
export PATH

bootstrap:
	@echo "=== bootstrap: bdw-gc system library (Phase 2+) ==="
	@# Per docs/adr/0005-libgc-binding-via-pkgconfig.md, the runtime
	@# resolves Boehm-Demers-Weiser (libgc) via `pkg-config bdw-gc`.
	@# Surface a missing dep here as a first-class error with the
	@# actionable per-platform install hint, rather than letting it
	@# leak through to a cryptic linker failure during the Ada build.
	@if ! command -v pkg-config >/dev/null 2>&1; then \
	    echo "Makefile: 'pkg-config' not on PATH." >&2 ; \
	    echo "  Install pkg-config: brew install pkg-config / sudo apt install pkg-config / etc." >&2 ; \
	    exit 1 ; \
	fi
	@if ! pkg-config --exists bdw-gc; then \
	    echo "Makefile: bdw-gc.pc not discoverable by pkg-config." >&2 ; \
	    echo "  GADA's runtime depends on Boehm-Demers-Weiser (ADR-0003 + ADR-0005)." >&2 ; \
	    echo "  Install the libgc system package:" >&2 ; \
	    echo "    macOS:           brew install bdw-gc" >&2 ; \
	    echo "    Debian/Ubuntu:   sudo apt install libgc-dev" >&2 ; \
	    echo "    Fedora:          sudo dnf install gc-devel" >&2 ; \
	    echo "    FreeBSD:         sudo pkg install boehm-gc" >&2 ; \
	    echo "    Alpine:          sudo apk add gc-dev" >&2 ; \
	    exit 1 ; \
	fi
	@echo "bootstrap: bdw-gc OK (`pkg-config --modversion bdw-gc`)"
	@echo
	@echo "=== bootstrap: Go module deps (compiler/) ==="
	@if command -v go >/dev/null 2>&1; then \
	    cd $(ROOT)/compiler && go mod download ; \
	else \
	    echo "Makefile: 'go' not on PATH — install Go 1.22+ to bootstrap the compiler module" >&2 ; \
	fi
	@echo
	@echo "=== bootstrap: Ada runtime crate (runtime/) ==="
	@if command -v alr >/dev/null 2>&1; then \
	    cd $(ROOT)/runtime && alr build ; \
	else \
	    echo "Makefile: 'alr' not on PATH — install Alire from https://alire.ada.dev to bootstrap the runtime crate" >&2 ; \
	fi

test:
	$(MAKE) -C $(ROOT)/compiler test
	$(MAKE) -C $(ROOT)/runtime test

coverage:
	@mkdir -p $(COVERAGE_DIR)
	$(MAKE) -C $(ROOT)/compiler coverage
	$(MAKE) -C $(ROOT)/runtime coverage
	@cp $(ROOT)/compiler/coverage.out  $(COVERAGE_DIR)/compiler.coverage.out
	@cp $(ROOT)/runtime/coverage.lcov  $(COVERAGE_DIR)/runtime.coverage.lcov
	@{ \
	    set -e ; \
	    echo "GADA unified coverage summary" ; \
	    echo "Generated: $$(date -u +%Y-%m-%dT%H:%M:%SZ)" ; \
	    echo "Repo root: $(ROOT)" ; \
	    echo ; \
	    echo "=== Go compiler module (compiler/) ===" ; \
	    echo "Profile: coverage/compiler.coverage.out" ; \
	    cd $(ROOT)/compiler && go tool cover -func=$(COVERAGE_DIR)/compiler.coverage.out | tail -1 ; \
	    echo ; \
	    echo "=== Ada runtime crate (runtime/) ===" ; \
	    echo "Tracefile: coverage/runtime.coverage.lcov" ; \
	    lcov --summary $(COVERAGE_DIR)/runtime.coverage.lcov 2>&1 \
	        | grep -E '^( {2}(source files|lines|functions|branches)|Summary)' || true ; \
	} > $(COVERAGE_DIR)/summary.txt
	@echo
	@echo "=== coverage/summary.txt ==="
	@cat $(COVERAGE_DIR)/summary.txt

lint:
	$(MAKE) -C $(ROOT)/compiler lint
	$(MAKE) -C $(ROOT)/runtime lint

coverage-gate:
	@if [ -x $(ROOT)/tools/coverage_gate.sh ]; then \
	    $(ROOT)/tools/coverage_gate.sh ; \
	else \
	    echo "Makefile: tools/coverage_gate.sh not yet present — skipping (lands with the Phase 02 coverage-gate task)" >&2 ; \
	fi

# `example HELLO=<name>` is the user-facing pipeline runner. It is the
# Phase 1 exit-criterion target and is also the example-as-regression-test
# hook for CI: any change that breaks the binary's stdout fails the diff.
#
# Steps (each fails fast on a non-zero exit):
#   1. Build compiler/bin/gada if absent (so a clean tree is single-step).
#   2. Run `gada build examples/$(HELLO)`. The driver writes the produced
#      binary to examples/$(HELLO)/$(HELLO).
#   3. Run the binary, capture stdout, diff against
#      examples/$(HELLO)/expected_output.txt. `diff -u` prints the unified
#      diff on mismatch and exits non-zero.
#
# `HELLO` is a positional ergonomic — `make example HELLO=hello` is the
# spelled-out form documented in roadmap/01-minimal-transpiler.md. The
# variable name is unfortunate (it does not have to be the hello example)
# but is what the phase doc pins.
example:
	@if [ -z "$(HELLO)" ]; then \
	    echo "make example: HELLO=<name> is required (e.g. make example HELLO=hello)" >&2 ; \
	    exit 2 ; \
	fi
	@if [ ! -d $(ROOT)/examples/$(HELLO) ]; then \
	    echo "make example: examples/$(HELLO)/ does not exist" >&2 ; \
	    exit 2 ; \
	fi
	@if [ ! -f $(ROOT)/examples/$(HELLO)/expected_output.txt ]; then \
	    echo "make example: examples/$(HELLO)/expected_output.txt is missing" >&2 ; \
	    exit 2 ; \
	fi
	@if [ ! -x $(ROOT)/compiler/bin/gada ]; then \
	    echo "=== building compiler/bin/gada ===" ; \
	    cd $(ROOT)/compiler && $(GO) build -o ./bin/gada ./cmd/gada ; \
	fi
	@echo "=== gada build examples/$(HELLO) ==="
	@# `gada build` shells out to `gprbuild` directly via PATH, so the
	@# Alire-managed toolchain (GNAT + gprbuild) must be reachable in the
	@# child process's environment. When `alr` is on PATH, run `gada build`
	@# inside `alr -n exec --` from the runtime crate so GPR_PROJECT_PATH
	@# and the gnat_native / gprbuild toolchain bin dirs are surfaced
	@# correctly — the same trick `runtime/tests/run_tests.sh` uses. Without
	@# this, on aarch64-darwin gprconfig fails to discover the Ada compiler
	@# because it walks gprbuild's real bindir (which holds only gprbuild)
	@# rather than the symlink shim dir. The non-alr fallback preserves
	@# the CI examples-job flow, which surfaces gprbuild on PATH explicitly.
	@if command -v alr >/dev/null 2>&1; then \
	    cd $(ROOT)/runtime && alr -n exec -- $(ROOT)/compiler/bin/gada build $(ROOT)/examples/$(HELLO) ; \
	else \
	    $(ROOT)/compiler/bin/gada build $(ROOT)/examples/$(HELLO) ; \
	fi
	@echo "=== running examples/$(HELLO)/$(HELLO) ==="
	@out=$$(mktemp -t gada-example.XXXXXX) ; \
	    trap 'rm -f $$out' EXIT ; \
	    $(ROOT)/examples/$(HELLO)/$(HELLO) > $$out ; \
	    rc=$$? ; \
	    if [ $$rc -ne 0 ]; then \
	        echo "make example: binary exited $$rc" >&2 ; \
	        exit $$rc ; \
	    fi ; \
	    if ! diff -u $(ROOT)/examples/$(HELLO)/expected_output.txt $$out ; then \
	        echo "make example: output mismatch" >&2 ; \
	        exit 1 ; \
	    fi
	@echo "make example: $(HELLO) OK"

# `ci` is the gate every PR must pass. Order matters: lint first (cheap,
# fails fast on style nits), then test (catches functional regressions),
# then coverage + gate (catches under-tested code), then roadmap consistency
# (catches drift between the index table and phase-file Status: lines).
# Make's default semantics abort on the first non-zero target, which is
# exactly the "first-failure aborts" contract the phase doc requires.
ci: lint test coverage coverage-gate
	$(ROOT)/tools/check_roadmap_consistency.sh

clean:
	$(MAKE) -C $(ROOT)/compiler clean
	$(MAKE) -C $(ROOT)/runtime clean
	rm -rf $(COVERAGE_DIR)
	@# Remove example-produced binaries (the Go source and expected_output.txt
	@# are checked in; the binary is gprbuild output and must regenerate).
	@find $(ROOT)/examples -mindepth 2 -maxdepth 2 -type f -perm -u+x \
	    ! -name '*.go' ! -name '*.txt' ! -name '*.md' -delete 2>/dev/null || true
