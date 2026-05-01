#!/usr/bin/env bash
# tools/lint_go.sh
#
# Runs golangci-lint over the Go compiler module against the repo-root
# .golangci.yml config. Invoked by compiler/Makefile's `lint` target,
# which is in turn invoked by the top-level `make lint` and `make ci`.
#
# Contract (Phase 02 — Linting):
#   * Exits 0 if the linter found no violations.
#   * Exits non-zero (golangci-lint's own exit code) if violations are
#     found, so `make ci` aborts on the first failure.
#   * Exits 1 with an actionable install hint if golangci-lint is not on
#     PATH — this is intentional, not a soft no-op: linting is now a
#     gating Phase 02 deliverable, so a missing linter is a real failure.
#
# Invocation-location-agnostic: resolves the repo root from the script's
# own location, so `tools/lint_go.sh`, `./tools/lint_go.sh`, and absolute-
# path invocations from CI all work identically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Augment PATH the same way runtime/Makefile and Makefile do, so bare
# invocations from CI / Maestro / IDE tasks find golangci-lint installed
# under any of the common Homebrew / user-local prefixes.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v golangci-lint >/dev/null 2>&1; then
    cat >&2 <<'EOF'
tools/lint_go.sh: golangci-lint is not on PATH.

Install it:
  macOS  : brew install golangci-lint
  Linux  : see https://golangci-lint.run/welcome/install/#local-installation
  CI     : install in the workflow before invoking `make ci`.

Linting is a Phase 02 gating deliverable; this script intentionally exits
1 rather than soft-skipping so missing tooling cannot mask lint failures.
EOF
    exit 1
fi

cd "$ROOT/compiler"
exec golangci-lint run --config "$ROOT/.golangci.yml" ./...
