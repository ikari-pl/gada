#!/usr/bin/env bash
#
# tools/coverage_ada.sh
#
# Build the GADA Ada runtime + AUnit test harness with gcov instrumentation,
# run the harness, then capture line-coverage data into runtime/coverage.lcov
# (the artifact consumed by tools/coverage_gate.sh and by CI).
#
# Why this script exists separately from tests/run_tests.sh:
#   run_tests.sh is the developer's "did my change break anything?" path —
#   no instrumentation, no extra build cost. Coverage is a heavier workflow:
#   it forces a full rebuild with -fprofile-arcs/-ftest-coverage, leaves
#   .gcda files behind, and depends on lcov. Keeping the two paths separate
#   means the fast feedback loop stays fast.
#
# Tooling assumptions:
#   - `alr` (Alire) is on PATH or under one of the well-known install
#     locations probed below. Alire owns the GNAT 15.x + gprbuild 25.x
#     toolchain we build against.
#   - `lcov` 1.14+ is available (Homebrew on macOS, apt-get on Linux).
#     CI installs it explicitly; local devs should `brew install lcov`.
#   - `gcov` MUST come from the same GCC that produced the .gcno files,
#     otherwise the format check fails silently and coverage reads as 0%.
#     We resolve gcov via `alr exec` so the Alire-managed toolchain wins
#     over any system gcov (Xcode CLT ships GCC 11's gcov on macOS).
#
# Coverage-flag injection strategy:
#   We use the `Build_Mode` scenario variable declared in gada_core.gpr
#   (and mirrored in tests/aunit_harness.gpr) to switch on coverage flags
#   only for GADA-owned projects. Combined with `--subdirs=cov`, this
#   isolates instrumented artefacts in `obj/cov/`, `lib/cov/`, and
#   `tests/obj/cov/` so coverage builds coexist with the regular non-
#   coverage build without forcing a full rebuild.
#
#   The crucial property of this strategy: Alire-supplied dependency
#   projects (AUnit, etc.) live in their own per-build cache and do NOT
#   declare `Build_Mode`, so they are unaffected. Earlier iterations of
#   this script used `gprbuild -f -cargs -fprofile-arcs ... -largs -lgcov`
#   which propagated the flags to *every* unit gprbuild touched —
#   including AUnit — and poisoned Alire's shared AUnit build cache with
#   gcov references that broke every subsequent non-coverage build on
#   the host. Scenario variables are the right level of granularity.
#
# Verify contract (roadmap/00-foundation.md "Coverage tooling — Ada"):
#   `make -C runtime coverage` exits 0, produces runtime/coverage.lcov,
#   and `lcov --summary` reports a non-zero line count.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_DIR="$ROOT/runtime"
LCOV_OUT="$RUNTIME_DIR/coverage.lcov"

# --- PATH discovery ----------------------------------------------------------
# Cover the common install layouts so the script works whether the user
# launched us from a login shell, a CI runner, or a Maestro agent with a
# minimal PATH. Order matters: prepend so explicit user PATH still wins
# for tools we don't care about, but Alire/Homebrew bins are reachable.
EXTRA_PATH=(
    "$HOME/src/gnatstudio/.tools/bin"     # GNAT Studio bundle (current host)
    "$HOME/.local/share/alire/bin"        # standalone Alire install
    "$HOME/.local/bin"                    # user-local
    "/opt/homebrew/bin"                   # Apple Silicon Homebrew
    "/usr/local/bin"                      # Intel Homebrew / generic
)
for p in "${EXTRA_PATH[@]}"; do
    if [[ -d "$p" && ":$PATH:" != *":$p:"* ]]; then
        PATH="$p:$PATH"
    fi
done
export PATH

# --- tool availability -------------------------------------------------------
missing=0
require_tool() {
    local tool=$1 hint=$2
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: '$tool' not on PATH; $hint" >&2
        missing=1
    fi
}
require_tool alr  "install Alire from https://alire.ada.dev (manages GNAT + gprbuild)"
require_tool lcov "install via 'brew install lcov' (macOS) or 'apt-get install lcov' (Debian/Ubuntu)"
if [[ "$missing" -ne 0 ]]; then
    exit 127
fi

cd "$RUNTIME_DIR"

# Coverage artefacts live under a `cov/` subdir of each project's obj_dir
# (gprbuild --subdirs=cov). Keeping these isolated means the regular
# non-coverage build cache (used by `make test`) stays untouched.
COV_OBJ="$RUNTIME_DIR/obj/cov"
COV_TEST_OBJ="$RUNTIME_DIR/tests/obj/cov"

# --- clean stale coverage data ----------------------------------------------
# Stale .gcda files from a prior run accumulate execution counts, biasing
# results. .gcno files are notes describing the program graph and are
# regenerated automatically each compile.
find obj tests/obj -name '*.gcda' -delete 2>/dev/null || true

# --- instrumented build -----------------------------------------------------
# alr exec pushes the Alire-managed GNAT + gprbuild onto PATH for the
# duration of the inner command. The scenario variable Build_Mode=coverage
# turns on -fprofile-arcs/-ftest-coverage in gada_core.gpr and
# aunit_harness.gpr (only); --subdirs=cov isolates the resulting .o, .ali,
# and library artefacts so a regular `make test` rebuild stays cheap.
echo "=== building test harness with Build_Mode=coverage --subdirs=cov ==="
alr exec -- gprbuild -P tests/aunit_harness.gpr \
    -XBuild_Mode=coverage --subdirs=cov

BIN="tests/obj/cov/test_runner"

# --- macOS Sequoia rpath fix (mirrors tests/run_tests.sh) -------------------
# GNAT 15 + gprbuild 25 emit duplicate LC_RPATH load commands; Darwin 25's
# dyld aborts on duplicates. Strip one if present. No-op on Linux.
if [[ "$(uname)" == "Darwin" ]]; then
    DUP_RPATH="${HOME}/.local/share/alire/toolchains/gnat_native_15.1.2_60748c54/lib"
    COUNT=$(otool -l "$BIN" | awk -v p="$DUP_RPATH" '/^ +path /{ if ($2 == p) c++ } END { print c+0 }')
    if [[ "$COUNT" -gt 1 ]]; then
        install_name_tool -delete_rpath "$DUP_RPATH" "$BIN" 2>/dev/null || true
    fi
fi

# --- run the instrumented harness -------------------------------------------
# AUnit's exit code is 0 iff every assertion passed. .gcda files materialize
# in obj/ and tests/obj/ as the binary executes.
echo
echo "=== running instrumented test harness ==="
"$BIN"

# --- capture coverage -------------------------------------------------------
# Resolve gcov from the Alire toolchain so its format matches the .gcno
# files produced by `alr exec -- gprbuild` above. Falling back to system
# gcov (e.g. Xcode CLT's GCC 11) yields silent format-mismatch errors.
GCOV_TOOL="$(alr exec -- bash -c 'command -v gcov' 2>/dev/null || command -v gcov)"

echo
echo "=== capturing coverage with gcov: $GCOV_TOOL ==="
# --rc geninfo_unexecuted_blocks=1 ensures uncovered basic blocks count
# toward the denominator (lcov 2.x defaults can otherwise mask zero-hit
# regions). --ignore-errors keeps lcov from aborting on benign warnings
# emitted by gcov when a unit was excluded from this run (e.g. a body
# with no test-driver entry point).
lcov --quiet \
     --capture \
     --directory "$COV_OBJ" \
     --directory "$COV_TEST_OBJ" \
     --gcov-tool "$GCOV_TOOL" \
     --rc geninfo_unexecuted_blocks=1 \
     --ignore-errors inconsistent,inconsistent \
     --ignore-errors gcov,gcov \
     --ignore-errors empty,empty \
     --ignore-errors negative,negative \
     --output-file "$LCOV_OUT" 2>&1 | grep -Ev '^$' || true

# Filter to runtime/src only. Without this, AUnit framework sources (which
# are pulled in transitively and instrumented along with everything else)
# would inflate denominators with code we have no obligation to cover.
echo
echo "=== filtering to runtime/src/* ==="
lcov --quiet \
     --extract "$LCOV_OUT" "$RUNTIME_DIR/src/*" \
     --ignore-errors inconsistent,inconsistent \
     --ignore-errors empty,empty \
     --output-file "$LCOV_OUT" 2>&1 | grep -Ev '^$' || true

echo
echo "=== lcov --summary $LCOV_OUT ==="
lcov --summary "$LCOV_OUT"
