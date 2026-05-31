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

  Decomposed 2026-05-31: the emission has no IR to work from yet —
  `type` declarations are still rejected at translate
  (`translate.go`'s GenDecl arm defers Var/Const/Type), and there is no
  `*ir.TypeDecl` / struct-type node. And there is nothing to emit
  `Register_Type` *calls against* until the runtime grows a registry.
  Split into three focused slices, each with its own verify; the parent
  ticks when all three do and the parent's `-run TypeMeta` golden passes.

  - [ ] **(a) IR + translate: `type` declarations**
        *Files:* `compiler/internal/ir/ir.go` (`*ir.TypeDecl` Decl
        variant + an `*ir.StructType` Type variant carrying named
        fields; JSON round-trip + sealed-interface + missing-field
        guards), `compiler/internal/ir/ir_test.go`,
        `compiler/internal/translate/translate.go` (GenDecl `token.TYPE`
        arm → `transTypeDecl`, handling `type N struct {…}` and named
        scalar `type N <scalar>`), `compiler/internal/translate/testdata/type_decl.{go,golden.json}`.
        *Verify:* `cd compiler && go test ./internal/ir/... ./internal/translate/... -run 'TestCorpus|Type'`
        *Done when:* `type Point struct { X, Y int }` and a named scalar
        `type Celsius float64` round-trip through translate as
        `*ir.TypeDecl`; directional/unsupported underlyings reject with
        a clear error rather than silently dropping.

  - [ ] **(b) Runtime — `Gada.Reflect` type registry**
        *Files:* `runtime/src/gada-reflect.ads`/`.adb` (extend the
        namespace parent with `Register_Type (T : Types.Type_Descriptor)`
        and `Lookup (Id : Types.Type_Id) return Types.Type_Descriptor`
        over a process-wide table keyed by Type_Id),
        `runtime/tests/reflect_suite.{ads,adb}`.
        *Verify:* `make -C runtime test PKG=reflect`
        *Done when:* a `Register_Type` then `Lookup (Id)` round-trips the
        descriptor; an unknown Id returns an Invalid_Kind descriptor (Go's
        zero `reflect.Type`); double-register of the same Id is defined
        (last-wins or rejected) and tested; coverage 100%. This is the
        store the emitted module-init calls populate and that item 3's
        `TypeOf` reads.

  - [ ] **(c) emit: `typemeta.go` — `Register_Type` calls at module init**
        *Files:* `compiler/internal/emit/typemeta.go`, golden tests
        (`compiler/internal/emit/testdata/type_decl.golden.adb`).
        *Verify:* `cd compiler && go test ./internal/emit/... -run TypeMeta`
        *Done when:* every `*ir.TypeDecl` in the file emits a
        `Make (…)` + per-field `Add_Field` + per-method `Add_Method` +
        `Gada.Reflect.Register_Type (…)` sequence in the module's
        elaboration/init, with Type_Ids assigned per defined type and
        field/elem/key links resolved to those Ids.

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
