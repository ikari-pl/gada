#!/usr/bin/env bash
# Build + run the GADA bench harness with the macOS Sequoia
# duplicate-LC_RPATH workaround that runtime/tests/run_tests.sh
# applies (see docs/imperfections.md).
#
# Output: one benchstat-compatible line per benchmark on stdout.

set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$(dirname "$BENCH_DIR")"

# PATH augmentation mirrors runtime/Makefile and runtime/tests/run_tests.sh.
export PATH="$HOME/src/gnatstudio/.tools/bin:$HOME/.local/share/alire/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# Surface libgc switches via pkg-config; consumed by gada_bench_harness.gpr's
# external_as_list lookup.
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists bdw-gc; then
    export GADA_GC_LDFLAGS="$(pkg-config --libs bdw-gc)"
    export GADA_GC_CFLAGS="$(pkg-config --cflags bdw-gc)"
fi

cd "$RUNTIME_DIR"

# Build via Alire so AUnit etc. are on GPR_PROJECT_PATH.
if command -v alr >/dev/null 2>&1; then
    alr exec -- gprbuild -P bench/gada_bench_harness.gpr
else
    gprbuild -P bench/gada_bench_harness.gpr
fi

BENCH_BIN="$BENCH_DIR/obj/bench_runner"

# macOS Sequoia (Darwin 25+) duplicate-LC_RPATH strip — same workaround
# as runtime/tests/run_tests.sh. No-op on Linux and earlier macOS.
if [[ "$(uname -s)" == "Darwin" ]]; then
    DUP_RPATHS="$(otool -l "$BENCH_BIN" 2>/dev/null \
        | awk '/cmd LC_RPATH/{getline; getline; print}' \
        | sort | uniq -d || true)"
    if [[ -n "$DUP_RPATHS" ]]; then
        while IFS= read -r RPATH; do
            RPATH_PATH="$(echo "$RPATH" | awk '{print $2}')"
            install_name_tool -delete_rpath "$RPATH_PATH" "$BENCH_BIN" 2>/dev/null || true
            install_name_tool -add_rpath "$RPATH_PATH" "$BENCH_BIN" 2>/dev/null || true
        done <<< "$DUP_RPATHS"
    fi
fi

"$BENCH_BIN"
