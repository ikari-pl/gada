#!/usr/bin/env bash
#
# tools/coverage_go.sh
#
# Run the Go compiler module's test suite with coverage instrumentation
# and produce two artifacts:
#
#   1. compiler/coverage.out  — Go's machine-readable cover profile,
#                               consumed by `go tool cover` and by
#                               tools/coverage_gate.sh (per-path threshold
#                               enforcement, added later in Phase 02).
#   2. stdout                 — `go tool cover -func` summary, ending in
#                               a `total: (statements) NN.N%` line that
#                               the top-level `make coverage` target
#                               folds into coverage/summary.txt.
#
# `-covermode=atomic` is required because the suite uses `-race` and
# parallel subtests; the cheaper `set` mode is unsafe under concurrent
# coverage updates. `-coverpkg=./...` instruments every package in the
# module so cross-package calls are credited (without it, `cmd/gada`
# calling `internal/version.Describe()` would leave `version` at 0%).
#
# Usage:
#   ./tools/coverage_go.sh
#
# Exit codes:
#   0  tests pass and the cover profile was written.
#   non-zero  test failure or a missing `go` binary; the failure is
#             surfaced verbatim from `go test`.
#
# This script is invocation-location-agnostic: it always resolves the
# repo root from its own dirname so `make -C compiler coverage`,
# `bash tools/coverage_go.sh`, and CI all produce the same artifact path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER_DIR="$ROOT/compiler"
PROFILE="$COMPILER_DIR/coverage.out"

if ! command -v go >/dev/null 2>&1; then
    echo "ERROR: 'go' not on PATH; install Go 1.22+ to run the compiler test suite" >&2
    exit 127
fi

cd "$COMPILER_DIR"

# -count=1 disables the test result cache so coverage is always recomputed.
# Without it, an unchanged tree returns cached PASS without writing the
# coverprofile, leaving stale data on disk.
go test \
    -count=1 \
    -race \
    -covermode=atomic \
    -coverpkg=./... \
    -coverprofile="$PROFILE" \
    ./...

echo
echo "=== go tool cover -func ==="
go tool cover -func="$PROFILE"
