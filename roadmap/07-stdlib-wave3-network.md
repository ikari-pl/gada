# Phase 7 — Stdlib wave 3: network

[← Phase 6](06-stdlib-wave2.md) · [Index](README.md) · Next: [Phase 8 →](08-stdlib-wave4-crypto.md)

**Status:** `IN_PROGRESS` (opened 2026-11-26)
**Prerequisites:** [Phase 6](06-stdlib-wave2.md) `DONE`, [Phase 4](04-interfaces-reflection.md) `DONE`
**Goal:** Port `net`, `net/http`, `encoding/json`. This is where GADA
proves it can run real-world Go libraries: `encoding/json` exercises
reflection end-to-end, `net/http` exercises everything.
**Exit criterion:** `examples/http_echo` runs an HTTP server on port
8080, accepts requests, echoes JSON, and runs in CI under
`integration-test` driving curl against it.

## Items

- [x] **Stdlib package: `net`** (done 2026-11-26, CI green on 49a4d62)
      *Files:* `runtime/src/gada-std-net.{ads,adb}`, `runtime/tests/stdlib/net_suite.{ads,adb}`, `compiler/internal/{ir/stdlib.go,ir/ir.go,emit/emit.go,translate/translate.go}`
      *Verify:* `make stdlib-test PKG=net`
      *Done when:* `Dial`, `Listen`, TCP and UDP, `LookupHost`, `IP` parsing all correct; coverage ≥ 90%.
      IPv4+IPv6 parse/format (RFC 5952), `Conn`/`Listener`/`Packet_Conn`
      on GNAT.Sockets (v1 = IPv4-only; v6 literals/names yield clean
      errors), `Lookup_Host`, compiler lowering for net-typed method
      calls, `make([]byte, N)`, `[]byte(s)`. Runtime 100%, emit ≥95%,
      translate ≥95%.

- [x] **Stdlib package: `encoding/json`** (done 2026-11-27, CI green on e04571d)
      *Files:* `runtime/src/gada-std-json.{ads,adb}`, `runtime/tests/stdlib/json_suite.{ads,adb}`, `compiler/internal/{ir/stdlib.go,emit/emit.go,translate/translate.go}`
      *Verify:* `make stdlib-test PKG=encoding.json`
      *Done when:* `Marshal`, `Unmarshal` round-trip arbitrary structs (driven by `Gada.Reflect`); coverage ≥ 95%.
      *Sub-items:*
      - [x] **2a: JSON text core + scalar Marshal/Unmarshal** (done 2026-11-27, CI green on c920294) —
            `Gada.Std.Json`: string escape/unescape (incl. `\uXXXX`),
            `Encode_Value`/`Decode_Value` driven by `Gada.Reflect` type
            descriptors (Bool/Int/Float/String kinds), `Marshal` /
            `Unmarshal` two-value out-call shape. Compiler maps
            `encoding/json` → `Gada.Std.Json`; `json.Marshal(x)` /
            `json.Unmarshal(data, &v)` for scalar-typed `x`/`v` lower
            through `Gada.Reflect.Values.Value_Of`.
            *Verify:* `make stdlib-test PKG=encoding.json` + Go unit tests.
      - [x] **2b: struct Marshal/Unmarshal (compiler-specialized)** (done 2026-11-27, CI green on e04571d) —
            the emitter generates a per-struct `Marshal_T` /
            `Unmarshal_T` in the program unit, reading field names from
            the emitted `Gada.Reflect` metadata (`Register_Type` /
            `Add_Field`) and field values from the statically-typed
            record; `json.Marshal(p)` / `json.Unmarshal(data, &p)`
            route to them. Nested structs, slices, maps of string keys,
            `json:"name"` tags.
            *Verify:* Go transpile tests + `make stdlib-test PKG=encoding.json`.

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
