# runtime/Makefile
#
# Per-side entry points for the GADA Ada runtime crate. The top-level repo
# Makefile (added later in Phase 02) calls these targets via
# `make -C runtime <target>`. Targets here must be self-contained and assume
# `runtime/` is the working directory; everything is invoked through the
# Alire-managed toolchain so we don't depend on the caller's PATH having
# `gprbuild`/`gnat`.
#
# Targets:
#   test       — build + run the AUnit harness via tests/run_tests.sh
#                (which paps over the macOS Sequoia duplicate-LC_RPATH bug).
#                Accepts a `PKG=<suite-name>` filter — forwarded to
#                run_tests.sh and on to test_runner — so a single suite
#                can be exercised without rebuilding the whole harness.
#                Recognised values today: `core.io` (matches the
#                Gada.Core.IO suite). Empty PKG = run every registered
#                suite. Unknown PKG = test_runner exits non-zero.
#   coverage   — build with -fprofile-arcs/-ftest-coverage, run, capture
#                lcov data into runtime/coverage.lcov.
#   lint       — gnatcheck against tools/gnatcheck.rules (config arrives
#                with the Phase 02 linting task; until then this is a
#                soft no-op so `make ci` does not block the coverage gate).
#   clean      — remove gprbuild artefacts and coverage data.

.PHONY: test coverage lint clean

# Resolve the repo root from this Makefile's location so the targets work
# regardless of the caller's CWD (`make -C runtime ...` from root, direct
# invocation from runtime/, CI checkout layouts, etc.).
RUNTIME_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ROOT := $(abspath $(RUNTIME_DIR)/..)

# PATH augmentation — mirror the discovery logic in tools/coverage_ada.sh
# so this Makefile works under bare `make` invocations (CI, Maestro agents,
# IDE build tasks) where the caller's shell may not have surfaced alr.
# Existing PATH entries take effect last so user overrides remain intact
# for tools we don't care about.
PATH := $(HOME)/src/gnatstudio/.tools/bin:$(HOME)/.local/share/alire/bin:$(HOME)/.local/bin:/opt/homebrew/bin:/usr/local/bin:$(PATH)
export PATH

test:
	$(RUNTIME_DIR)/tests/run_tests.sh $(PKG)

coverage:
	$(ROOT)/tools/coverage_ada.sh

lint:
	$(ROOT)/tools/lint_ada.sh

clean:
	rm -rf $(RUNTIME_DIR)/obj $(RUNTIME_DIR)/lib
	rm -rf $(RUNTIME_DIR)/tests/obj
	rm -f $(RUNTIME_DIR)/coverage.lcov
	find $(RUNTIME_DIR) -name '*.gcda' -delete 2>/dev/null || true
	find $(RUNTIME_DIR) -name '*.gcno' -delete 2>/dev/null || true

# Targeted helper for CI / debugging: drop only the coverage artefacts
# (obj/cov, tests/obj/cov, lcov tracefile) without nuking the regular
# non-coverage build cache. Useful when iterating on coverage_ada.sh.
.PHONY: clean-coverage
clean-coverage:
	rm -rf $(RUNTIME_DIR)/obj/cov $(RUNTIME_DIR)/tests/obj/cov
	rm -f $(RUNTIME_DIR)/coverage.lcov
	find $(RUNTIME_DIR) -name '*.gcda' -delete 2>/dev/null || true
