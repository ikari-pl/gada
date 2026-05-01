#!/usr/bin/env bash
#
# tools/check_roadmap_consistency.sh
#
# Verify that the Status: line in each roadmap/NN-*.md phase file
# matches the corresponding row in roadmap/README.md's phases table.
#
# The roadmap has two sources of truth for phase status:
#   1. roadmap/README.md's phases table (the at-a-glance dashboard).
#   2. The Status: line in each individual phase file.
# They must agree. This script is the mechanical check.
#
# Usage:
#   ./tools/check_roadmap_consistency.sh
#
# Exit codes:
#   0  every phase file's Status: matches the index table.
#   1  one or more mismatches; details printed to stderr.
#   2  setup error (index file missing, malformed, etc.).
#
# This script has no dependencies beyond POSIX bash, awk, sed, grep.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROADMAP_DIR="$ROOT/roadmap"
INDEX="$ROADMAP_DIR/README.md"

if [ ! -f "$INDEX" ]; then
    echo "ERROR: index file not found at $INDEX" >&2
    exit 2
fi

mismatches=0
checked=0

# Iterate over phase rows in the index table.
# A phase row matches: "| <int> | <name> | <STATUS> | [<file.md>](<file.md>) |"
# Header rows ("| # | Phase | Status | File |") and the separator row do not
# start with "| <int> |" so they are skipped by the regex.
while IFS= read -r line; do
    num=$(awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}' <<< "$line")
    status_in_table=$(awk -F'|' '{gsub(/^ +| +$/, "", $4); print $4}' <<< "$line")
    link_cell=$(awk -F'|' '{gsub(/^ +| +$/, "", $5); print $5}' <<< "$line")

    # link_cell looks like: [00-foundation.md](00-foundation.md)
    # Extract the path inside the parens.
    file=$(sed -E 's/.*\(([^)]+)\).*/\1/' <<< "$link_cell")

    if [ -z "$file" ]; then
        echo "ERROR: could not parse file link from row: $line" >&2
        mismatches=$((mismatches + 1))
        continue
    fi

    phase_file="$ROADMAP_DIR/$file"
    if [ ! -f "$phase_file" ]; then
        echo "MISSING: index row for phase $num references $file, but $phase_file does not exist" >&2
        mismatches=$((mismatches + 1))
        continue
    fi

    # Extract Status from the phase file. Format:
    #   **Status:** `NOT_STARTED`
    status_in_file=$(grep -E '^\*\*Status:\*\*' "$phase_file" | head -1 \
        | sed -E 's/.*`([A-Z_]+)`.*/\1/')

    if [ -z "$status_in_file" ]; then
        echo "NO_STATUS: $phase_file has no '**Status:** \`STATE\`' line" >&2
        mismatches=$((mismatches + 1))
        continue
    fi

    if [ "$status_in_file" != "$status_in_table" ]; then
        echo "MISMATCH: phase $num ($file)" >&2
        echo "    index says:      $status_in_table" >&2
        echo "    phase file says: $status_in_file" >&2
        mismatches=$((mismatches + 1))
        continue
    fi

    checked=$((checked + 1))
done < <(grep -E '^\| [0-9]+ \|' "$INDEX")

if [ "$checked" -eq 0 ] && [ "$mismatches" -eq 0 ]; then
    echo "ERROR: no phase rows found in $INDEX (table may be malformed)" >&2
    exit 2
fi

if [ "$mismatches" -eq 0 ]; then
    echo "OK: roadmap status consistent across index and $checked phase file(s)."
    exit 0
fi

echo "" >&2
echo "FAIL: $mismatches roadmap status mismatch(es)." >&2
echo "Fix by updating either the index table or the phase file's Status: line" >&2
echo "so the two agree." >&2
exit 1
