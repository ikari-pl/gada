#!/usr/bin/env bash
#
# tools/coverage_gate.sh
#
# Per-path coverage gate. Reads tools/coverage_thresholds.toml, parses the
# coverage artefacts produced by `make coverage` (Go cover profile + lcov
# tracefile), computes aggregate line coverage for every threshold path,
# and exits non-zero with a clear "FAIL: <path> <actual>% < <threshold>%"
# line if any threshold is violated.
#
# Threshold matching is "every file whose repo-relative path starts with
# the threshold's `path` prefix". Overlapping by design — a file under
# `compiler/internal/emit/` counts toward BOTH the emit/ threshold AND
# the parent compiler/ threshold. This catches the case where a deep
# package regresses but the broad average still looks acceptable.
#
# Implementation: a thin Bash CLI that resolves artefact paths and exec's
# an inline Python parser. Python is the right tool here — TOML parsing
# (stdlib `tomllib` since 3.11) and floating-point aggregation in awk
# would be far more fragile than three short parsers in one heredoc.
# No new compiled dependencies.
#
# Usage:
#   ./tools/coverage_gate.sh [--config <toml>]
#                            [--go-profile <go cover profile>]
#                            [--lcov <lcov tracefile>]
#                            [--repo-root <path>]
#
# Default artefact lookup order (per side):
#   1. coverage/compiler.coverage.out  (top-level `make coverage` output)
#      fallback: compiler/coverage.out (per-side `make -C compiler coverage`)
#   2. coverage/runtime.coverage.lcov  (top-level)
#      fallback: runtime/coverage.lcov  (per-side)
#
# Exit codes:
#   0    every threshold met (PASS)
#   1    one or more thresholds violated (FAIL)
#   2    bad CLI usage
#  127   missing python3, missing config, or both artefacts absent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$ROOT/tools/coverage_thresholds.toml"
GO_PROFILE="$ROOT/coverage/compiler.coverage.out"
LCOV_FILE="$ROOT/coverage/runtime.coverage.lcov"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)     CONFIG="$2";     shift 2 ;;
        --go-profile) GO_PROFILE="$2"; shift 2 ;;
        --lcov)       LCOV_FILE="$2";  shift 2 ;;
        --repo-root)  ROOT="$2";       shift 2 ;;
        -h|--help)
            sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "coverage_gate.sh: unknown arg: $1" >&2
            exit 2 ;;
    esac
done

# Per-side fallbacks: prefer the unified coverage/ artefacts produced by the
# top-level Makefile, but accept per-side artefacts when someone ran
# `make -C compiler coverage` (or `make -C runtime coverage`) directly.
if [[ ! -f "$GO_PROFILE" ]] && [[ -f "$ROOT/compiler/coverage.out" ]]; then
    GO_PROFILE="$ROOT/compiler/coverage.out"
fi
if [[ ! -f "$LCOV_FILE" ]] && [[ -f "$ROOT/runtime/coverage.lcov" ]]; then
    LCOV_FILE="$ROOT/runtime/coverage.lcov"
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: 'python3' not on PATH; required to parse coverage_thresholds.toml (Python 3.11+ for stdlib tomllib)" >&2
    exit 127
fi
if [[ ! -f "$CONFIG" ]]; then
    echo "ERROR: thresholds file not found: $CONFIG" >&2
    exit 127
fi

if [[ ! -f "$GO_PROFILE" && ! -f "$LCOV_FILE" ]]; then
    echo "ERROR: neither coverage artefact found; run 'make coverage' first." >&2
    echo "  Go cover profile: $GO_PROFILE" >&2
    echo "  lcov tracefile:   $LCOV_FILE" >&2
    exit 127
fi

# WARN-but-continue when only one side has data: lets `make -C compiler
# coverage && coverage_gate.sh` still enforce the compiler half. CI invokes
# `make coverage` first so both sides land together; this is for ergonomics.
[[ -f "$GO_PROFILE" ]] || { echo "WARN: Go cover profile missing ($GO_PROFILE); compiler/ thresholds NOT enforced this run" >&2; GO_PROFILE=""; }
[[ -f "$LCOV_FILE"  ]] || { echo "WARN: lcov tracefile missing ($LCOV_FILE); runtime/ thresholds NOT enforced this run" >&2; LCOV_FILE=""; }

export GADA_GATE_CONFIG="$CONFIG"
export GADA_GATE_ROOT="$ROOT"
export GADA_GATE_GO_PROFILE="$GO_PROFILE"
export GADA_GATE_LCOV="$LCOV_FILE"

exec python3 - <<'PY'
import os
import re
import sys
import tomllib
from collections import defaultdict
from pathlib import Path

CONFIG = os.environ['GADA_GATE_CONFIG']
ROOT = Path(os.environ['GADA_GATE_ROOT']).resolve()
GO_PROFILE = os.environ.get('GADA_GATE_GO_PROFILE') or None
LCOV = os.environ.get('GADA_GATE_LCOV') or None

# --- Go cover profile parser ------------------------------------------------
# Format reference: golang.org/x/tools/cover (Profile struct).
#
#   <import-path>/<file>:<sline>.<scol>,<eline>.<ecol> <numStmts> <count>
#
# `-coverpkg=./...` causes every test binary in the module to instrument
# every package, so the same block legitimately appears multiple times in
# the merged profile (once per test binary). Standard semantics: a block
# is "covered" if its execution count is > 0 in ANY of its occurrences.
# We dedup on the block key and keep the max observed count — exactly
# the rule `go tool cover -func` itself applies.
#
# File paths come back as Go import paths
# (e.g. github.com/gada-lang/gada/compiler/cmd/gada/main.go).
# Translate to repo-relative by locating /compiler/ or /runtime/ inside the
# import path; the suffix is what the threshold prefixes match against.
GO_BLOCK_RE = re.compile(r'^(.+):(\d+)\.(\d+),(\d+)\.(\d+)\s+(\d+)\s+(\d+)$')


def go_path_to_repo_relative(go_path: str) -> str:
    for marker in ('/compiler/', '/runtime/'):
        idx = go_path.find(marker)
        if idx >= 0:
            return go_path[idx + 1:]
    # Already repo-relative or absolute — pass through unchanged.
    return go_path


def parse_go_profile(path: str) -> dict[str, tuple[int, int]]:
    blocks: dict[tuple, tuple[int, int]] = {}
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('mode:'):
                continue
            m = GO_BLOCK_RE.match(line)
            if not m:
                continue
            file_ = m.group(1)
            sline, scol, eline, ecol = (int(m.group(i)) for i in (2, 3, 4, 5))
            n = int(m.group(6))
            cnt = int(m.group(7))
            key = (file_, sline, scol, eline, ecol)
            if key in blocks:
                prev_n, prev_cnt = blocks[key]
                blocks[key] = (prev_n, max(prev_cnt, cnt))
            else:
                blocks[key] = (n, cnt)

    per_file: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for (file_, *_), (n, cnt) in blocks.items():
        rel = go_path_to_repo_relative(file_)
        per_file[rel][1] += n
        if cnt > 0:
            per_file[rel][0] += n
    return {k: (v[0], v[1]) for k, v in per_file.items()}


# --- lcov parser ------------------------------------------------------------
# Parses DA: records explicitly so we can apply per-file line exclusions
# (the documented escape valve in coverage_thresholds.toml's [[exclude]]
# section) before aggregating into the (LH, LF) summary that the gate
# scores against. lcov's own LH/LF totals don't honour the exclusions
# because the lcov 2.x `--filter region` pipeline relies on source-side
# LCOV_EXCL_* markers, which need source readability and a specific
# capture-time configuration we deliberately keep out of the build path.
def parse_lcov(path: str, exclusions: dict[str, set[int]]) -> dict[str, tuple[int, int]]:
    per_file: dict[str, tuple[int, int]] = {}
    cur_file: str | None = None
    cur_rel: str | None = None
    cur_excl: set[int] = set()
    cur_lh = 0
    cur_lf = 0
    root_str = str(ROOT)
    with open(path) as f:
        for raw in f:
            line = raw.rstrip('\r\n')
            if line.startswith('SF:'):
                cur_file = line[3:]
                cur_rel = cur_file
                if cur_rel.startswith(root_str + os.sep):
                    cur_rel = cur_rel[len(root_str) + 1:]
                cur_excl = exclusions.get(cur_rel, set())
                cur_lh = cur_lf = 0
            elif line.startswith('DA:'):
                # DA:<line>,<count>[,<checksum>]
                payload = line[3:]
                parts = payload.split(',')
                if len(parts) < 2:
                    continue
                try:
                    ln = int(parts[0])
                    cnt = int(parts[1])
                except ValueError:
                    continue
                if ln in cur_excl:
                    continue  # silently drop excluded line
                cur_lf += 1
                if cnt > 0:
                    cur_lh += 1
            elif line == 'end_of_record':
                if cur_rel is not None:
                    per_file[cur_rel] = (cur_lh, cur_lf)
                cur_file = None
                cur_rel = None
                cur_excl = set()
                cur_lh = cur_lf = 0
    return per_file


# --- main -------------------------------------------------------------------
with open(CONFIG, 'rb') as f:
    cfg = tomllib.load(f)
thresholds = cfg.get('threshold', [])
if not thresholds:
    print(f"ERROR: no [[threshold]] entries in {CONFIG}", file=sys.stderr)
    sys.exit(127)

# [[exclude]] entries: per-file line numbers the gate should drop from
# both numerator and denominator. The TOML schema is a list of tables
# with `file = "<repo-relative path>"` + `lines = [<int>, ...]`. Multiple
# entries for the same file accumulate (so reviewers can group exclusions
# by reason without re-listing the file).
exclusions: dict[str, set[int]] = {}
for ex in cfg.get('exclude', []):
    f = ex.get('file')
    lines = ex.get('lines', [])
    if not f or not isinstance(lines, list):
        print(f"ERROR: malformed [[exclude]] entry in {CONFIG}: {ex}", file=sys.stderr)
        sys.exit(127)
    exclusions.setdefault(f, set()).update(int(n) for n in lines)

per_file: dict[str, tuple[int, int]] = {}
if GO_PROFILE:
    per_file.update(parse_go_profile(GO_PROFILE))
if LCOV:
    # lcov entries take precedence for runtime/ paths since the .lcov file
    # is the authoritative Ada coverage source (Go cover profile never
    # touches Ada files, so there's no actual collision here, but be
    # explicit so a future cross-build can't regress this silently).
    per_file.update(parse_lcov(LCOV, exclusions))

print(f"=== coverage gate: {len(thresholds)} thresholds, {len(per_file)} files ===")
for f in sorted(per_file):
    cov, tot = per_file[f]
    pct = 100.0 * cov / tot if tot else 0.0
    print(f"  file: {pct:6.2f}%  ({cov:>4}/{tot:<4})  {f}")
print()

failures: list[tuple[str, float, float, int, int, int]] = []
for t in thresholds:
    pref = t['path']
    min_pct = float(t['minimum_lines_pct'])
    matched = [(f, c, n) for f, (c, n) in per_file.items() if f.startswith(pref)]
    total_cov = sum(c for _, c, _ in matched)
    total_tot = sum(n for _, _, n in matched)
    if total_tot == 0:
        print(f"  SKIP: {pref!r} matched 0 lines (artefact missing or no source under prefix)")
        continue
    pct = 100.0 * total_cov / total_tot
    status = 'PASS' if pct >= min_pct else 'FAIL'
    print(f"  {status}: {pref!r:42s} {pct:6.2f}%  (>= {min_pct:.2f}%, {total_cov}/{total_tot} lines, {len(matched)} files)")
    if status == 'FAIL':
        failures.append((pref, pct, min_pct, len(matched), total_cov, total_tot))

if failures:
    print()
    print("=== coverage gate: FAILED ===")
    for pref, pct, min_pct, _, _, _ in failures:
        print(f"FAIL: {pref} {pct:.2f}% < {min_pct:.2f}%")
    sys.exit(1)

print()
print("=== coverage gate: PASSED ===")
sys.exit(0)
PY
