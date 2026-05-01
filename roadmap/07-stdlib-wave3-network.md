# Phase 7 — Stdlib wave 3: network

[← Phase 6](06-stdlib-wave2.md) · [Index](README.md) · Next: [Phase 8 →](08-stdlib-wave4-crypto.md)

**Status:** `NOT_STARTED`
**Prerequisites:** [Phase 6](06-stdlib-wave2.md) `DONE`, [Phase 4](04-interfaces-reflection.md) `DONE`
**Goal:** Port `net`, `net/http`, `encoding/json`. This is where GADA
proves it can run real-world Go libraries: `encoding/json` exercises
reflection end-to-end, `net/http` exercises everything.
**Exit criterion:** `examples/http_echo` runs an HTTP server on port
8080, accepts requests, echoes JSON, and runs in CI under
`integration-test` driving curl against it.

## Items

- [ ] **Stdlib package: `net`**
      *Files:* `stdlib/net/`
      *Verify:* `make stdlib-test PKG=net`
      *Done when:* `Dial`, `Listen`, TCP and UDP, `LookupHost`, `IP` parsing all correct; coverage ≥ 90%.

- [ ] **Stdlib package: `encoding/json`**
      *Files:* `stdlib/encoding/json/`
      *Verify:* `make stdlib-test PKG=encoding.json`
      *Done when:* `Marshal`, `Unmarshal` round-trip arbitrary structs (driven by `Gada.Reflect`); coverage ≥ 95%.

- [ ] **Stdlib package: `net/http` (server side)**
      *Files:* `stdlib/net/http/`
      *Verify:* `make stdlib-test PKG=net.http`
      *Done when:* `ListenAndServe`, `Handler`, `Request`, `ResponseWriter` correct for a non-trivial subset; coverage ≥ 85%.

- [ ] **Stdlib package: `net/http` (client side)**
      *Files:* `stdlib/net/http/` (extension)
      *Verify:* `make stdlib-test PKG=net.http.client`
      *Done when:* `http.Get`, `http.Post`, `http.Client` correct against a local test server.

- [ ] **`http_echo` example**
      *Files:* `examples/http_echo/main.go`, `examples/http_echo/integration_test.sh`
      *Verify:* `make example HELLO=http_echo` and `./examples/http_echo/integration_test.sh`
      *Done when:* the server starts, curl roundtrips a JSON payload, output matches expected.

- [ ] **`json_roundtrip` example** (deferred from Phase 4)
      *Files:* `examples/json_roundtrip/main.go`, `examples/json_roundtrip/expected_output.txt`
      *Verify:* `make example HELLO=json_roundtrip`
      *Done when:* a struct with multiple field types round-trips through `json.Marshal` → `json.Unmarshal` and equals the original by deep comparison.
