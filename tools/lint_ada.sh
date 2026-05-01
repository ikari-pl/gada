#!/usr/bin/env bash
# tools/lint_ada.sh
#
# Runs gnatcheck over the Ada runtime crate against tools/gnatcheck.rules.
# Invoked by runtime/Makefile's `lint` target, which is in turn invoked
# by the top-level `make lint` and `make ci`.
#
# Contract (Phase 02 — Linting):
#   * Exits 0 if gnatcheck found no violations.
#   * Exits 1 if gnatcheck found violations (gnatcheck's own exit code).
#   * Exits 0 with a clear "skip" message if gnatcheck is *not installed*
#     on this host. This is the deliberate asymmetry vs lint_go.sh:
#     gnatcheck ships only with GNAT Pro / GNATstudio Pro, NOT with the
#     FSF GNAT distribution that Alire installs by default. Treating
#     "gnatcheck not installed" as a hard failure would break every macOS
#     dev box (Alire has FSF GNAT only) and would offer no path forward
#     short of a paid AdaCore subscription. CI on Ubuntu can install
#     `gnat-gps` / equivalent and exercise the rule file there.
#
# Invocation-location-agnostic: resolves the repo root from the script's
# own location.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Augment PATH so the GNAT Studio / Alire-managed toolchains are visible
# under bare invocations (CI, Maestro, IDE build tasks).
export PATH="$HOME/src/gnatstudio/.tools/bin:$HOME/.local/share/alire/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

RULES_FILE="$ROOT/tools/gnatcheck.rules"
PROJECT_FILE="$ROOT/runtime/gada_core.gpr"

if [[ ! -f "$RULES_FILE" ]]; then
    echo "tools/lint_ada.sh: rules file missing at $RULES_FILE" >&2
    exit 1
fi

# Probe for gnatcheck both directly and via `alr exec --` (the toolchain
# is sometimes only on the alr-managed PATH, not the host PATH).
GNATCHECK=""
if command -v gnatcheck >/dev/null 2>&1; then
    GNATCHECK="gnatcheck"
elif command -v alr >/dev/null 2>&1; then
    if alr exec -- which gnatcheck >/dev/null 2>&1; then
        GNATCHECK="alr exec -- gnatcheck"
    fi
fi

if [[ -z "$GNATCHECK" ]]; then
    cat >&2 <<'EOF'
tools/lint_ada.sh: gnatcheck not found — skipping Ada lint pass.

Reason: gnatcheck ships with GNAT Pro / GNATstudio Pro, not with the FSF
GNAT distribution that Alire installs on macOS / non-Pro Linux hosts.

To enable on this host:
  Ubuntu : sudo apt-get install gnat-gps   (or use AdaCore's installer)
  macOS  : install GNATstudio Pro from AdaCore
  CI     : install in the Linux runner before invoking `make ci`.

Exiting 0 (soft-skip) so `make ci` does not break on hosts without the
proprietary tool. The CI workflow's Ubuntu job is the authoritative
gnatcheck enforcement point for this project.
EOF
    exit 0
fi

cd "$ROOT"
exec $GNATCHECK -P "$PROJECT_FILE" -rules -from="$RULES_FILE"
