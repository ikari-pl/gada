# Phase 4 — Interfaces & reflection

[← Phase 3](03-concurrency.md) · [Index](README.md) · Next: [Phase 5 →](05-stdlib-wave1.md)

**Status:** `IN_PROGRESS` (opened 2026-05-30)
**Prerequisites:** [Phase 2](02-core-runtime.md) `DONE` ([Phase 3](03-concurrency.md) not strictly required)
**Goal:** Implement Go interface dispatch (structural at compile time,
nominal at runtime) and the `reflect` package's common surface
(`TypeOf`, `ValueOf`, `Kind`, struct field/method walk).
**Exit criterion:** `make example HELLO=iface_dispatch` exercises 3+
types implementing 2 interfaces with reflection-based method
enumeration; output matches the expected fixture.

## Items

- [x] **Type metadata schema**
      *Files:* `runtime/src/gada-reflect.ads` (namespace parent),
      `runtime/src/gada-reflect-types.ads`,
      `runtime/src/gada-reflect-types.adb`,
      `runtime/tests/reflect_types_suite.{ads,adb}`
      (the roadmap's original `gada-reflect-type.ads` would map to package
      `Gada.Reflect.Type`, but `type` is an Ada reserved word — the
      schema ships as `Gada.Reflect.Types`).
      *Verify:* `make -C runtime test PKG=reflect.type`
      *Done when:* type records carry name, kind, fields, methods, and are equality-comparable.
      *Done 2026-05-30:* `Gada.Reflect` is a namespace parent; the schema
      ships as `Gada.Reflect.Types`. `Type_Descriptor` is a private value
      carrying a `Type_Id` (per-program identity the compiler assigns),
      `Name`, a `Type_Kind` (the Go reflect.Kind subset GADA supports —
      literals suffixed `_Kind` to dodge the `interface` reserved word
      and the `String`/`Float` predefined names), ordered `Add_Field` /
      `Add_Method` lists, and `Elem` / `Key` Type_Id links for the
      composite kinds (Slice/Pointer/Chan element, Map value+key). Types
      reference each other *by Id*, not by embedding, so the table is
      flat and cycle-safe. The predefined `"="` is deep value equality
      across all components (Unbounded_String by content, the field /
      method vectors element-wise) — that is the equality-comparable
      contract; type identity is `Id (A) = Id (B)`. Five AUnit cases
      (scalar, struct fields+methods, composite elem/key, value
      equality, out-of-range Constraint_Error) cover the package 100%
      (28/28 body lines); runtime/ stays 100% (806/806). `make ci`
      green. The TypeOf/ValueOf entry points and the compiler's
      Register_Type emission (later items) build on this.

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
