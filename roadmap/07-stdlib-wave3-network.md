# Phase 7 — Stdlib wave 3: network

[← Phase 6](06-stdlib-wave2.md) · [Index](README.md) · Next: [Phase 8 →](08-stdlib-wave4-crypto.md)

**Status:** `DONE` (opened 2026-11-26, closed 2026-11-27, CI green on f9ceb5e, run 45991722582)
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

- [x] **Stdlib package: `net/http` (server side)** (done 2026-11-27, CI green on f9ceb5e)
      *Files:* `runtime/src/gada-std-http.{ads,adb}`, `runtime/tests/stdlib/http_suite.{ads,adb}` (suite `stdlib.net.http`)
      *Verify:* `make stdlib-test PKG=net.http`
      *Done when:* met — `Listen_And_Serve` with a stoppable accept loop
      (Stop self-connects to wake a blocked Accept_K, which holds the
      listener lock), `Read_Request` (request line, headers incl.
      Content-Length, body), buffered `Response_Writer`, mux with "/"
      catch-all, 400/404 paths, and a Serve_One exception handler that
      closes the conn so a panicking handler can never wedge a client.
      runtime/ 100% gate green (exclusions with rationale in
      runtime/COVERAGE.md). CI surfaced and fixed a header-loop Index
      base bug (slice-relative vs absolute — CONSTRAINT_ERROR on any
      multi-header request) and the last-header-line parse arm.

- [x] **Stdlib package: `net/http` (client side)** (done 2026-11-27, CI green on f9ceb5e)
      *Files:* `runtime/src/gada-std-http.{ads,adb}` (extension)
      *Verify:* `make stdlib-test PKG=net.http` (Test_Client_404 /
      Test_Client_Errors / Test_Client_Echo)
      *Done when:* met — `Get` / `Post` / `Client.Get` / `Client.Post`
      over `Do_Request` (dial, request write, read-until-EOF, status
      parse), `Response` record; error paths (bad scheme, empty host,
      refused dial, malformed responses) all covered. Compiler:
      `io.ReadAll(r.Body)`/`(resp.Body)` lower to a direct `Body_K`
      assign + `No_Error` (emitIOReadAllBody, both the `:=` and `=`
      out-call paths), and `http.Post(url, ct, bytes.NewReader(b))`
      unwraps to the Byte_Slice (translate).

- [x] **`http_echo` example** (done 2026-11-27, CI green on f9ceb5e)
      *Files:* `examples/http_echo/main.go`, `examples/http_echo/serve/main.go`, `examples/http_echo/integration_test.sh`
      *Verify:* `make example HELLO=http_echo` and `./examples/http_echo/integration_test.sh`
      *Done when:* met — exit criterion satisfied in CI: the serve
      variant listens on 127.0.0.1:8080, curl POSTs a JSON payload and
      gets `{"N":42,"On":true,"R":0.5}` with status 200; the combo
      example runs client+server in-process. Also fixed en route:
      `Gada.Std.Time.Sleep` added (the port lacked it), JSON marshalers
      now emitted before handler bodies in the Main_Types layout.

- [x] **`json_roundtrip` example** (done 2026-11-27, CI green on f9ceb5e)
      *Files:* `examples/json_roundtrip/main.go`, `examples/json_roundtrip/expected_output.txt`
      *Verify:* `make example HELLO=json_roundtrip`
      *Done when:* met — `make example HELLO=json_roundtrip` OK in CI;
      multi-field struct round-trips through `json.Marshal` →
      `json.Unmarshal` and matches the expected output.
