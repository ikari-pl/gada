#!/usr/bin/env bash
#
#  run_tests.sh — build and execute the AUnit harness for the Gada runtime.
#
#  Usage:
#     cd runtime && tests/run_tests.sh           # run every registered suite
#     cd runtime && tests/run_tests.sh core.io   # run only the Gada.Core.IO suite
#
#  An optional first positional argument is forwarded to the AUnit test
#  runner as a suite-name filter. Empty / absent = run all suites.
#
#  This wrapper exists to paper over a macOS Sequoia (Darwin 25+) dyld
#  regression: GNAT 15 + gprbuild 25 emit two identical LC_RPATH load
#  commands pointing at the toolchain's lib directory, and the modern
#  dyld aborts on duplicate LC_RPATH entries with SIGABRT (exit 134).
#  We strip the duplicate post-link with `install_name_tool -delete_rpath`.
#
#  On Linux / older macOS, the install_name_tool step is a no-op (the
#  rpath simply isn't there) and the harness runs unmodified.
#
#  Verify contract: this script exits 0 iff every AUnit assertion passes.

set -euo pipefail

#  Resolve script-relative paths so we can be run from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$(dirname "$SCRIPT_DIR")"

cd "$RUNTIME_DIR"

#  Build via Alire so AUnit and the GNAT toolchain resolve correctly.
alr exec -- gprbuild -P tests/aunit_harness.gpr

BIN="tests/obj/test_runner"

#  macOS-only rpath cleanup. Look for the GNAT toolchain rpath and, if it
#  appears more than once, delete it once so dyld stops aborting.
if [[ "$(uname)" == "Darwin" ]]; then
   DUP_RPATH="${HOME}/.local/share/alire/toolchains/gnat_native_15.1.2_60748c54/lib"
   COUNT=$(otool -l "$BIN" | awk -v p="$DUP_RPATH" '/^ +path /{ if ($2 == p) c++ } END { print c+0 }')
   if [[ "$COUNT" -gt 1 ]]; then
      install_name_tool -delete_rpath "$DUP_RPATH" "$BIN" 2>/dev/null || true
   fi
fi

#  Run; bubble up the exit code. The optional first arg (e.g. "core.io")
#  is forwarded as a suite-name filter; the runner treats an empty or
#  missing arg as "run every registered suite".
exec "$BIN" "${1:-}"
