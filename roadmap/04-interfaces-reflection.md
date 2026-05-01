# Phase 4 — Interfaces & reflection

[← Phase 3](03-concurrency.md) · [Index](README.md) · Next: [Phase 5 →](05-stdlib-wave1.md)

**Status:** `NOT_STARTED`
**Prerequisites:** [Phase 2](02-core-runtime.md) `DONE` ([Phase 3](03-concurrency.md) not strictly required)
**Goal:** Implement Go interface dispatch (structural at compile time,
nominal at runtime) and the `reflect` package's common surface
(`TypeOf`, `ValueOf`, `Kind`, struct field/method walk).
**Exit criterion:** `make example HELLO=iface_dispatch` exercises 3+
types implementing 2 interfaces with reflection-based method
enumeration; output matches the expected fixture.

## Items

- [ ] **Type metadata schema**
      *Files:* `runtime/src/gada-reflect-type.ads`, `runtime/src/gada-reflect-type.adb`
      *Verify:* `make -C runtime test PKG=reflect.type`
      *Done when:* type records carry name, kind, fields, methods, and are equality-comparable.

- [ ] **Compiler — emit type metadata for every defined type**
      *Files:* `compiler/internal/emit/typemeta.go`, golden tests
      *Verify:* `cd compiler && go test ./internal/emit/... -run TypeMeta`
      *Done when:* every Go type in input source produces a corresponding `Gada.Reflect.Register_Type (...)` call at module init.

- [ ] **GADA.Reflect.TypeOf / ValueOf**
      *Files:* `runtime/src/gada-reflect.ads`, `runtime/src/gada-reflect.adb`, `runtime/tests/test_reflect.adb`
      *Verify:* `make -C runtime test PKG=reflect`
      *Done when:* `Type_Of`, `Value_Of`, `Kind`, `Field`, `Method` all return values matching Go's `reflect` semantics; coverage 100%.

- [ ] **Interface satisfaction tables**
      *Files:* `runtime/src/gada-reflect-interfaces.ads`, `compiler/internal/emit/interface.go`
      *Verify:* `make test` (cross-cutting)
      *Done when:* compiler emits a satisfaction registration for every (concrete type, interface) pair determinable at compile time; runtime can look up dispatch at O(1).

- [ ] **Compiler emission — interface method calls**
      *Files:* `compiler/internal/emit/dispatch.go`, golden tests
      *Verify:* `cd compiler && go test ./internal/emit/... -run Dispatch`
      *Done when:* `iface.Method(args)` emits an interface-table-indexed call.

- [ ] **Compiler emission — type assertions and type switches**
      *Files:* `compiler/internal/emit/assert.go`, golden tests
      *Verify:* `cd compiler && go test ./internal/emit/... -run Assert`
      *Done when:* `x.(T)`, `x.(T, ok)`, `switch x := y.(type) { ... }` all emit correctly.

- [ ] **`iface_dispatch` example**
      *Files:* `examples/iface_dispatch/main.go`, `examples/iface_dispatch/expected_output.txt`
      *Verify:* `make example HELLO=iface_dispatch`
      *Done when:* example exercises 3+ types implementing 2 interfaces with reflection-based method enumeration; output matches expected.

> **Note on json_roundtrip:** A reflection-end-to-end exit example
> using `encoding/json` is appropriate but depends on Phase 7's
> `encoding/json` port. It is therefore staged into Phase 7. Phase 4's
> exit example is `iface_dispatch`, which is reflection-complete
> without requiring a JSON encoder.
