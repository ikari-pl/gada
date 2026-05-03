#!/usr/bin/env bash
#
# tools/prove.sh
#
# Run gnatprove against the SPARK-opted-in subset of the GADA runtime.
# Per ADR-0008, SPARK is opt-in per package, so this script enumerates
# the opted-in units explicitly with `-u` rather than letting gnatprove
# walk the whole project (which would generate hundreds of useless flow
# warnings on Async/Defer/IO bodies that are deliberately `SPARK_Mode
# (Off)`).
#
# Exit codes:
#   0    every VC discharged on every opt-in unit
#   1    one or more VCs unproven, or a unit failed to compile under SPARK
#   127  gnatprove not on PATH (run `cd runtime && alr build` first to
#        materialise the gnatprove binary from the Alire toolchain crate)
#
# Usage:
#   tools/prove.sh                 # prove every opt-in unit
#   tools/prove.sh gada-core-hash  # prove a single unit
#
# The opt-in unit list lives in this script (single source of truth)
# and is mirrored in `runtime/PROOF.md`. When you add a new SPARK_Mode
# package, append it here AND add its row to PROOF.md AND link the
# row to ADR-0008's "first inclusions" list.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME="$ROOT/runtime"

# Mirror runtime/Makefile's PATH augmentation so gnatprove (installed
# via `alr with gnatprove`) is discoverable without the caller having
# to source `alr printenv` first.
PATH="$HOME/src/gnatstudio/.tools/bin:$HOME/.local/share/alire/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

# Per ADR-0008 §2: the opt-in set. Add new units here when their
# SPARK_Mode pragma lands. The list is short on purpose.
OPT_IN_UNITS=(
    "gada-core-hash"
)

# Filter: a single positional arg restricts the run to that unit.
if [[ $# -gt 0 ]]; then
    REQUESTED="$1"
    found=0
    for u in "${OPT_IN_UNITS[@]}"; do
        if [[ "$u" == "$REQUESTED" ]]; then
            OPT_IN_UNITS=("$REQUESTED")
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        echo "prove.sh: '$REQUESTED' is not in the SPARK opt-in set." >&2
        echo "         Known units: ${OPT_IN_UNITS[*]}" >&2
        echo "         See docs/adr/0008-spark-policy.md for the policy." >&2
        exit 1
    fi
fi

if ! command -v alr >/dev/null 2>&1; then
    echo "prove.sh: 'alr' not on PATH (Alire is required to dispatch gnatprove)." >&2
    echo "  Install Alire from https://alire.ada.dev." >&2
    exit 127
fi

# gnatprove ships from the Alire `gnatprove` binary crate (pinned in
# runtime/alire.toml per ADR-0008). It is NOT on the user's PATH; it
# lives at ~/.local/share/alire/releases/gnatprove_*/bin/. We dispatch
# via `alr exec --` so the crate's environment (PATH=${CRATE_ROOT}/bin)
# is materialised for the duration of the call.
cd "$RUNTIME"
if ! alr exec -- which gnatprove >/dev/null 2>&1; then
    echo "prove.sh: 'gnatprove' not deployed in the Alire crate cache." >&2
    echo "  Install via:  cd runtime && alr update" >&2
    echo "  (alr update materialises the gnatprove dependency from runtime/alire.toml)" >&2
    exit 127
fi

# Build the -u file list. gnatprove's -u takes file basenames (not Ada
# unit names): a single -u followed by every .ads/.adb to analyse.
U_FILES=()
for u in "${OPT_IN_UNITS[@]}"; do
    U_FILES+=("$u.ads" "$u.adb")
done

echo "=== prove.sh: ${#OPT_IN_UNITS[@]} unit(s) ==="
for u in "${OPT_IN_UNITS[@]}"; do
    echo "  - $u"
done
echo

# --mode=all     : check + flow + prove (the strongest pass).
# --level=2      : medium prover effort; level=4 is the heaviest.
#                  Level 2 discharges all the VCs in our current
#                  opt-in set in well under a minute on M-series Macs.
# --report=fail  : print only failed VCs to keep the output scannable
#                  (use --report=all when debugging a specific check).
# -j0            : use all available CPUs.
# -P             : the umbrella project file. SPARK_Mode pragmas in
#                  individual sources gate which units gnatprove
#                  actually attacks; the project file is just the
#                  source-discovery vehicle.
# --checks-as-errors=on : the default exit code of gnatprove is 0 even
#                         when checks are unproven (they surface as
#                         warnings). For a CI-shaped script we want any
#                         unproven VC to propagate as a non-zero exit
#                         so the gate fails loudly.
alr exec -- gnatprove \
    -P gada_core.gpr \
    --mode=all \
    --level=2 \
    --report=fail \
    --checks-as-errors=on \
    -j0 \
    -u "${U_FILES[@]}"

# gnatprove exits 0 on "all proved" and non-zero otherwise; the
# explicit echo below is for the human reader.
echo
echo "=== prove.sh: PASSED ==="
