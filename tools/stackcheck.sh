#!/usr/bin/env bash
#
# tools/stackcheck.sh
#
# Static stack-usage report for the GADA runtime, addressing hazard
# #8 ("no stack overflow detection") from the Phase 3 sub-item 3a
# concurrency retro:
# [[../docs/journal/2026-05-03-async-context-concurrency.md]].
#
# libco gives every goroutine a 64 KiB fixed stack (per ADR-0004).
# A function whose own frame uses 8 KiB consumes 1/8 of that budget
# in one call; deep call chains compound. Today we have no static
# check that this happens. This script closes the gap *for single-
# function frames*; per-call-chain analysis is a follow-up.
#
# Implementation:
#   1. Compile the runtime with `gcc -fstack-usage`. The compiler
#      emits a `.su` file next to every `.o` containing per-function
#      "function: bytes static|dynamic|bounded" rows. We pass this
#      via `gprbuild -cargs -fstack-usage` rather than editing
#      gada_core.gpr (which is on the won't-touch list per
#      .claude/coordination.json).
#   2. A Python aggregator parses every .su under runtime/obj/,
#      sorts descending by bytes, and reports the top N offenders
#      and the total.
#   3. The gate fails if any *single function frame* exceeds the
#      threshold (default 8192 bytes = 1/8 of a 64 KiB libco stack).
#      That is a soft signal, not a guarantee — true stack-overflow
#      detection needs call-chain analysis. Documented in STACK.md.
#
# Why not gnatstack: gnatstack is GNAT Pro / commercial only. The
# open-source equivalent is `-fstack-usage` plus this aggregator.
# Same shape as `tools/prove.sh` (Alire-managed binary + thin
# wrapper) — see ADR-0008 for the policy on toolchain dependencies.
#
# Exit codes:
#   0    every function under the threshold
#   1    one or more functions over the threshold
#   127  prerequisite missing (alr / gprbuild / python3)
#
# Usage:
#   tools/stackcheck.sh                   # default 8192-byte gate
#   tools/stackcheck.sh --threshold 4096  # tighter gate
#   tools/stackcheck.sh --top 20          # show top 20 offenders
#   tools/stackcheck.sh --report-only     # print report, never fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME="$ROOT/runtime"

# Standard Alire install locations only -- no dev-host-specific paths
# (the gnatstudio toolchain layout is unique to one developer's
# machine, was a Gemini-flagged review issue on PR #4). Caller's
# existing PATH is preserved (appended at the end).
PATH="$HOME/.local/share/alire/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

THRESHOLD=8192
TOP_N=10
REPORT_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --threshold)   THRESHOLD="$2";   shift 2 ;;
        --top)         TOP_N="$2";       shift 2 ;;
        --report-only) REPORT_ONLY=1;    shift   ;;
        -h|--help)
            sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "stackcheck.sh: unknown arg: $1" >&2
            exit 2 ;;
    esac
done

for tool in alr gprbuild python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "stackcheck.sh: '$tool' not on PATH (required)" >&2
        exit 127
    fi
done

cd "$RUNTIME"

# Force-rebuild with -fstack-usage. -f forces recompilation so every
# unit emits a fresh .su file even when the .o is up-to-date. -cargs
# passes the flag to the compiler invocations only; -bargs / -largs
# are unaffected. We build the LIBRARY only (not the test runner),
# since the goroutine bodies that matter for hazard #8 are runtime-
# library code, not AUnit harness code.
echo "=== stackcheck.sh: compile with -fstack-usage ==="
# No `| tail -10` here: piping to tail would hide the actual
# compiler error if gprbuild fails midway, and pipefail alone
# can't recover the truncated lines. On a successful build the
# output is short anyway (one line per touched unit).
alr exec -- gprbuild -P gada_core.gpr -f -cargs -fstack-usage

# Find every .su file directly under obj/ (-maxdepth 1) -- our
# Object_Dir setup puts them flat. Recursing would pick up stale
# files from any future per-profile object subdir (e.g. obj/cov/
# from a coverage build) and double-count.
SU_COUNT=$(find obj -maxdepth 1 -name '*.su' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SU_COUNT" -eq 0 ]]; then
    echo "stackcheck.sh: no .su files emitted under runtime/obj/." >&2
    echo "  -fstack-usage may have been silently ignored (check gprbuild output above)." >&2
    exit 1
fi

echo
echo "=== stackcheck.sh: aggregating $SU_COUNT .su files ==="

export GADA_STACK_RUNTIME="$RUNTIME"
export GADA_STACK_THRESHOLD="$THRESHOLD"
export GADA_STACK_TOP="$TOP_N"
export GADA_STACK_REPORT_ONLY="$REPORT_ONLY"

python3 - <<'PY'
import os
import sys
from pathlib import Path

RUNTIME    = Path(os.environ['GADA_STACK_RUNTIME'])
THRESHOLD  = int(os.environ['GADA_STACK_THRESHOLD'])
TOP_N      = int(os.environ['GADA_STACK_TOP'])
REPORT_ONLY = os.environ['GADA_STACK_REPORT_ONLY'] == '1'

# Each .su line is:
#   <path>:<line>:<col>:<symbol>\t<bytes>\t<qualifier>
# qualifier ∈ {static, dynamic, bounded}.  We treat all three as
# "bytes used in the worst case" — dynamic is alloca-shaped, bounded
# is VLA with a known max; both can land on the libco stack.
rows = []
for su in (RUNTIME / 'obj').glob('*.su'):  # non-recursive: see find -maxdepth 1 above
    for raw in su.read_text().splitlines():
        if not raw.strip():
            continue
        # The file portion can contain colons on Windows; the *last*
        # tab-separated field is the qualifier and the second-to-last
        # is the byte count, so split from the right.
        try:
            head, bytes_, qual = raw.rsplit('\t', 2)
            n = int(bytes_)
        except (ValueError, IndexError):
            continue
        # Strip the runtime root prefix for tighter columns.
        try:
            head_rel = str(Path(head).relative_to(RUNTIME))
        except ValueError:
            head_rel = head
        rows.append((n, qual, head_rel))

rows.sort(reverse=True)

if not rows:
    print("stackcheck.sh: parsed 0 entries from .su files (empty?)")
    sys.exit(1)

total = sum(n for n, _, _ in rows)
worst = rows[0][0]

print(f"  total functions analysed: {len(rows)}")
print(f"  total bytes (sum of frames): {total}")
print(f"  worst single frame: {worst} bytes")
print(f"  threshold (per-frame): {THRESHOLD} bytes")
print()
print(f"  top {min(TOP_N, len(rows))} stack-hogs:")
for n, qual, where in rows[:TOP_N]:
    flag = "  OVER" if n > THRESHOLD else "      "
    print(f"  {flag}  {n:>7} {qual:<8} {where}")

over = [r for r in rows if r[0] > THRESHOLD]
if over and not REPORT_ONLY:
    print()
    print(f"=== stackcheck.sh: FAILED — {len(over)} function(s) over {THRESHOLD} bytes ===")
    sys.exit(1)

print()
if over and REPORT_ONLY:
    print(f"=== stackcheck.sh: REPORT-ONLY — {len(over)} function(s) over threshold (not failing) ===")
else:
    print(f"=== stackcheck.sh: PASSED — every function under {THRESHOLD} bytes ===")
PY
