#!/usr/bin/env bash
# integration_test.sh — curl-driven end-to-end check for the http_echo
# example (roadmap Phase 7 wave 3 item 5): builds the serve-only
# variant on 127.0.0.1:8080, starts it, POSTs a JSON payload with curl,
# and checks the echoed JSON body and 200 status.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

if [ ! -x "$ROOT/compiler/bin/gada" ]; then
  echo "=== building compiler/bin/gada ==="
  (cd "$ROOT/compiler" && go build -o ./bin/gada ./cmd/gada)
fi

echo "=== gada build examples/http_echo/serve ==="
if command -v alr >/dev/null 2>&1; then
  (cd "$ROOT/runtime" && alr -n exec -- "$ROOT/compiler/bin/gada" build "$HERE/serve")
else
  "$ROOT/compiler/bin/gada" build "$HERE/serve"
fi

BIN="$HERE/serve/serve"
"$BIN" &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT

# wait for the port to accept connections (a 404 on / still means up)
for _ in $(seq 1 100); do
  if curl -s -o /dev/null http://127.0.0.1:8080/; then
    break
  fi
  sleep 0.1
done

BODY_FILE="$(mktemp -t gada-echo-body.XXXXXX)"
trap 'kill $SRV 2>/dev/null || true; rm -f "$BODY_FILE"' EXIT
CODE="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' \
  -d '{"N":41,"On":true,"R":0.5}' http://127.0.0.1:8080/echo)"
OUT="$(cat "$BODY_FILE")"
echo "status: $CODE"
echo "body:   $OUT"

if [ "$CODE" != "200" ]; then
  echo "integration_test.sh: expected 200, got $CODE" >&2
  exit 1
fi
if [ "$OUT" != '{"N":42,"On":true,"R":0.5}' ]; then
  echo "integration_test.sh: body mismatch: $OUT" >&2
  exit 1
fi
echo "integration_test.sh OK"
