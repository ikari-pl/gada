# Phase 10 — Mixed Ada/Go codebases

[← Phase 9](09-verification-spark.md) · [Index](README.md) · Next: [Phase 11 →](11-validation-1.0.md)

**Status:** `NOT_STARTED`
**Prerequisites:** [Phase 5](05-stdlib-wave1.md) `DONE`
**Goal:** Make transpiled Go modules `with`-able by Ada, and Ada
packages importable by Go. Establish the bridging metadata that maps
Go types to Ada types and vice versa.
**Exit criterion:** an Ada program in `examples/mixed_ada_caller`
calls `Gada.Std.Encoding.Json.Marshal` on an Ada record and gets back
a JSON string.

## Items

- [ ] **ADR — Ada/Go type bridging table**
      *Files:* `docs/adr/0030-type-bridging.md`
      *Verify:* ADR is `accepted` with the full type-mapping table.
      *Done when:* mapping covers `int*`, `uint*`, `float*`, `string`/`String`, `[]byte`/`Stream_Element_Array`, structs/records, slices/`Vector`, maps/`Hashed_Map`, channels/protected entries.

- [ ] **Compiler — emit Ada-friendly public API**
      *Files:* `compiler/internal/emit/api.go`
      *Verify:* golden tests
      *Done when:* the transpiler emits Ada specs (`.ads`) that wrap Go public functions with idiomatic Ada parameter modes.

- [ ] **`gada-import` directive — Go calling Ada**
      *Files:* `compiler/internal/translate/gada_import.go`, `compiler/internal/emit/gada_import.go`
      *Verify:* `cd compiler && go test ./internal/... -run GadaImport`
      *Done when:* `//go:gada import "Foo"` exposes the Ada package `Foo` as Go-callable.

- [ ] **`mixed_ada_caller` example**
      *Files:* `examples/mixed_ada_caller/main.adb`, `examples/mixed_ada_caller/calling.go`
      *Verify:* `make example HELLO=mixed_ada_caller`
      *Done when:* the Ada program builds, links the transpiled Go module, calls into it, prints expected output.

- [ ] **`mixed_go_caller` example**
      *Files:* `examples/mixed_go_caller/calling.go`, `examples/mixed_go_caller/ada_lib.adb`
      *Verify:* `make example HELLO=mixed_go_caller`
      *Done when:* the Go program calls into an Ada library and prints expected output.
