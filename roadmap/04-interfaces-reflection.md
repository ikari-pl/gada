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

- [x] **Compiler — emit type metadata for every defined type**

  Decomposed 2026-05-31: the emission has no IR to work from yet —
  `type` declarations are still rejected at translate
  (`translate.go`'s GenDecl arm defers Var/Const/Type), and there is no
  `*ir.TypeDecl` / struct-type node. And there is nothing to emit
  `Register_Type` *calls against* until the runtime grows a registry.
  Split into three focused slices, each with its own verify; the parent
  ticks when all three do and the parent's `-run TypeMeta` golden passes.

  - [x] **(a) IR + translate: `type` declarations**
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
        *Done 2026-05-31:* IR adds `*ir.TypeDecl{Name, Underlying Type}`
        (Decl variant) and `*ir.StructType{Fields []*StructField}` (Type
        variant), with `StructField{Name, Type}` carrying each named
        field. Full JSON round-trip: `TypeDecl` / `StructType` join the
        decl / type kind-dispatch switches, and the three new
        Marshal/Unmarshal pairs guard their interface children
        (`TypeDecl missing underlying`, `StructField missing type`, plus
        bad-child propagation). Translate's GenDecl arm grows a
        `token.TYPE` case → `transTypeDecl`, and `transType` grows an
        `*ast.StructType` arm (`transStructType`) that expands a grouped
        `X, Y int` field into one StructField per name and rejects
        embedded/anonymous fields. `type Celsius float64` and
        `type Point struct { X, Y int }` round-trip (corpus fixture
        `type_decl`); a func-typed underlying and an embedded field both
        reject with clear errors. The obsolete `top type → Phase 1`
        rejection test is replaced by those two. Gates green: runtime
        100%, ir.go 97.11%, translate 95.77%, emit 95.66%, compiler
        95.03%.

  - [x] **(b) Runtime — `Gada.Reflect` type registry**
        *Files:* `runtime/src/gada-reflect-registry.{ads,adb}`,
        `runtime/tests/reflect_suite.{ads,adb}`.
        *Verify:* `make -C runtime test PKG=reflect`
        *Done when:* a `Register_Type` then `Lookup (Id)` round-trips the
        descriptor; an unknown Id returns an Invalid_Kind descriptor (Go's
        zero `reflect.Type`); double-register of the same Id is defined
        (last-wins or rejected) and tested; coverage 100%. This is the
        store the emitted module-init calls populate and that item 3's
        `TypeOf` reads.
        *Done 2026-05-31:* Lives in `Gada.Reflect.Registry`, **not** the
        `Gada.Reflect` parent as first planned: an Ada parent spec may
        not `with` its own child, and the registry API mentions
        `Gada.Reflect.Types.Type_Descriptor`, so it must sit in a sibling
        child. `Register_Type` / `Lookup` front a protected `Store`
        wrapping an `Ordered_Maps` table keyed by `Type_Id` (Ordered, so
        no hash function — Type_Id derives from Natural). `Register` is a
        protected procedure and uses `Include` (last-wins on a duplicate
        Id); `Lookup` is a protected function (concurrent goroutine
        reads are safe) returning the stored descriptor, or
        `Make (No_Type, "", Invalid_Kind)` — Go's zero `reflect.Type` —
        for an unregistered Id. Three AUnit cases (round-trip,
        unregistered-is-Invalid, duplicate-last-wins) cover the body 100%
        (8/8); runtime/ stays 100% (814/814). Same parent-can't-with-
        child constraint will apply to item 3's TypeOf/ValueOf — they
        ship as a child too, not in `gada-reflect.ads`.

  - [x] **(c) emit: `typemeta.go` — `Register_Type` calls at module init**
        *Files:* `compiler/internal/emit/typemeta.go`, golden tests
        (`compiler/internal/emit/testdata/type_decl.golden.adb`).
        *Verify:* `cd compiler && go test ./internal/emit/... -run TypeMeta`
        *Done when:* every `*ir.TypeDecl` in the file emits a
        `Make (…)` + per-field `Add_Field` + per-method `Add_Method` +
        `Gada.Reflect.Register_Type (…)` sequence in the module's
        elaboration/init, with Type_Ids assigned per defined type and
        field/elem/key links resolved to those Ids.
        *Done 2026-06-22:* `typemeta.go` walks the file's `*ir.TypeDecl`s
        in two passes — pass 1 reserves a per-program `Type_Id` for each
        defined type in source order (so a type's identity is stable
        regardless of which built-ins it references), pass 2 resolves
        each one's links. A shared `fillComposite` helper is the single
        home for the slice/chan element, map key+value, and struct-field
        interning (and their error paths), used by both the defined-type
        pass and `internType` (which reserves an Id *before* recursing so
        a self-referential composite can't loop). Every *referenced* type
        — a struct field's type, a slice/chan element, a map key/value —
        is itself registered with its own Id and Go-facing name
        (`"int"`, `"[]int"`, `"map[int]string"`, …), so the descriptor
        links resolve through `Lookup` exactly as Go's
        `reflect.TypeOf(int)` is a real `Type`. Emission wraps the
        sequence in a `declare … begin … end;` block placed in the
        package body's elaboration part (or the main procedure's
        prologue); `needsReflect` gates the `with Gada.Reflect.Types;` /
        `with Gada.Reflect.Registry;` clauses so a file with no `type`
        decls links neither. Corpus golden `type_decl` covers a named
        scalar (`Celsius`→Float), a struct with two int fields
        (`Point`→int Id reused), and the interned `int`. Unit tests add
        scalar/struct, scalar-element composites (slice/map/chan with
        Elem/Key emission), nested composites (`[][]int`, `[]chan int`,
        `[]map[int]string`, `[]float64` — the only shape that drives
        `metaTypeKey`'s recursive arms), and eight rejection cases
        (duplicate name, nil underlying, struct field nil/anon-struct,
        and nested nil at slice/chan/map-key/map-value). `metaTypeKey`,
        `metaTypeKind`, `fillComposite`, `collectTypeMeta`,
        `emitTypeMetadata` all 100%; the two residual `internType`
        branches are unreachable defensive error checks after
        `metaTypeKey` has already validated the type (its domain ⊆
        `metaTypeKind`'s, and `fillComposite` re-interns the exact
        children the key walk validated). emit/ aggregate 95.4%
        (≥ 95 gate); go vet + golangci-lint clean.

- [x] **GADA.Reflect.TypeOf / ValueOf**
      *Files:* `runtime/src/gada-reflect-values.ads`,
      `runtime/src/gada-reflect-values.adb`,
      `runtime/tests/reflect_values_suite.{ads,adb}` (registered in
      `runtime/tests/test_runner.adb` under `PKG=reflect.values`).
      *Verify:* `make -C runtime test PKG=reflect.values`
      *Done when:* `Type_Of`, `Value_Of`, `Kind`, `Field`, `Method` all
      return values matching Go's `reflect` semantics; coverage 100%.

      Corrected 2026-06-25 (roadmap originally listed
      `gada-reflect.{ads,adb}` + `test_reflect.adb` + `PKG=reflect`):

      - **Child, not the parent.** The TypeOf/ValueOf surface references
        `Gada.Reflect.Types` and `Gada.Reflect.Registry`, and an Ada
        parent spec may not `with` its own child — the same constraint
        that put the registry in `Gada.Reflect.Registry` (item 2b). It
        ships as a sibling child, `Gada.Reflect.Values`, *not* in
        `gada-reflect.ads`. `PKG=reflect` is already the registry suite's
        filter, so the new suite filters under `reflect.values`.
      - **Runtime-only item.** No compiler files: the API is built and
        AUnit-tested directly. Lowering a Go `reflect.TypeOf(x)` /
        `reflect.ValueOf(x)` *call* to these entry points is a later
        concern (it needs the static operand Type_Id at the call site,
        or — for an operand that is already an interface value — the
        interface representation from items 4/5).
      - **`Value` is a SPARK-friendly discriminated record**, not a
        boxed `Any` (no universal value box exists in the runtime yet,
        and one would drag in `unsafe`/tagged machinery the verifiable
        subset rejects). It carries the operand's `Type_Id` plus, for
        the scalar kinds, the datum: `Int` (Long_Long_Integer), `Float`
        (Long_Float), `Bool`, `String` (Unbounded_String). `Value_Of` is
        overloaded per scalar so the compiler picks by static operand
        type; a type-only `Value_Of (Id)` covers the composite kinds.
        Accessors mirror Go's `reflect.Value`: `Kind`, `Type_Of (V)`
        (→ descriptor), and `To_Int` / `To_Float` / `To_Bool` /
        `To_String` (each raises `Constraint_Error` on a kind mismatch,
        Go's panic on `Value.Int()` of a non-int). Value-side composite
        *data* walking (field values, slice indexing) is post-1.0 per
        AGENTS.md non-goals; the *type*-side walk (`Num_Fields` /
        `Field_*` / `Num_Methods` / `Method_Name`) already ships on
        `Type_Descriptor` and is what the `iface_dispatch` exit example
        enumerates.

      *Done 2026-06-25:* `Gada.Reflect.Values` ships `Type_Of (Id)`
      (reflect.TypeOf — a thin read over `Registry.Lookup`, Invalid_Kind
      for an unregistered Id), a flat private `Value` record (Type_Id +
      one slot per scalar kind, no discriminant / no access — the
      verifiable-subset-friendly shape), four overloaded scalar
      `Value_Of` constructors (the Ada datum type fixes the reflect
      Kind) plus a type-only `Value_Of (Id)` whose Kind comes from the
      registered descriptor, and the `reflect.Value` accessors `Kind`,
      `Type_Of (V)`, and `To_Int` / `To_Float` / `To_Bool` / `To_String`
      (each a raise-expression that yields the datum on a kind match and
      `Constraint_Error` otherwise — Go's panic on `Value.Int()` of a
      non-int). The schema names are reached via a non-leaking `use
      Gada.Reflect.Types` rather than re-exported subtypes, so a caller
      that `use`s both packages sees each name once. Four AUnit cases
      (`PKG=reflect.values`) cover Type_Of round-trip + the unregistered
      path, all five Value_Of forms with their accessors, the composite
      type-only box, and a Constraint_Error probe on each scalar
      accessor mismatch — `gada-reflect-values.adb` 100% (34/34),
      runtime/ stays 100% (850/850). The Go-call lowering of
      `reflect.TypeOf` / `reflect.ValueOf` to these entry points rides a
      later item (it needs the operand's static Type_Id, or the
      interface representation from items 4/5).

- [ ] **Interface satisfaction tables**

  **Design — Hybrid (chosen 2026-06-25).** Go interface dispatch maps onto
  Ada in two coordinated representations the compiler keeps in sync:

  - *Native Ada tagged types drive real calls.* Each Go interface becomes
    an Ada `interface` type; each concrete type the compiler finds
    satisfying it becomes a tagged type (`is new … and I`) with
    `overriding` method bodies. `iface.M (args)` is then a dispatching
    call and `x.(T)` a membership test — Ada's own vtable, no hand-rolled
    itable. This *emission* lands in items 5–6, where it is exercised.
  - *A satisfaction registry answers introspection.* The runtime
    `Gada.Reflect.Interfaces` records each (concrete, interface) pair and
    the concrete type's method names, so `reflect.TypeOf (x)` method
    enumeration and "does C satisfy I" queries are O(1). **This item owns
    the registry and the IR foundations both halves need.**

  Decomposed 2026-06-25: interfaces and methods are not in the IR yet —
  `ir.Function` carries no receiver and translate *drops* every method
  (the `d.Recv /= nil` arm), and there is no interface-type node.
  Structural satisfaction needs both method sets, so the foundations come
  first; the parent ticks when all three sub-items do.

  - [x] **(a) IR + translate: interface types**
        *Files:* `compiler/internal/ir/ir.go` (`*ir.InterfaceType` Type
        variant + an `*ir.MethodSig` carrying name / params / results;
        JSON round-trip + sealed-interface + missing-field guards),
        `compiler/internal/translate/translate.go` (`transType`
        `*ast.InterfaceType` arm), `compiler/internal/translate/testdata`.
        *Verify:* `cd compiler && go test ./internal/ir/... ./internal/translate/... -run 'TestCorpus|Interface'`
        *Done when:* `type Stringer interface { String () string }` and
        the empty `interface{}` (Go's `any`) round-trip as
        `*ir.InterfaceType`; an embedded interface rejects with a clear
        error rather than silently dropping.
        *Done 2026-06-25:* IR adds `*ir.InterfaceType{Methods []*MethodSig}`
        (Type variant) and `*ir.MethodSig{Name, Params, Results}` reusing
        `*Param`, both with `kind`-tagged Marshal/Unmarshal and an
        `InterfaceType` arm in `unmarshalType`. Translate's `transType`
        grows an `*ast.InterfaceType` arm → `transInterfaceType`, which
        lowers each method's signature via the existing `transFieldList`
        and rejects embedded interfaces (a field with no names). Corpus
        fixture `interface_decl` round-trips `Stringer` (one parameterless
        string method), `ReadWriter` (named param + multi-value result,
        and a second method), and the empty `interface{}` (`any`, no
        methods). Rejections covered: embedded interface, and a method
        with an unsupported param / result type; a synthetic non-FuncType
        interface field pins the defensive branch. ir.go 96.75%,
        translate/ 95.75% (both ≥ gate); go vet + golangci-lint clean.
        Methods-on-concrete-types (4b) and satisfaction (4c) build on this.

  - [ ] **(b) IR + translate: methods (receivers)**
        *Files:* `compiler/internal/ir/ir.go` (`Function.Receiver *Param`,
        nil for a free function; round-trip), `compiler/internal/translate/translate.go`
        (stop filtering `d.Recv`, attach the receiver, surface the method
        through `File`), testdata.
        *Verify:* `cd compiler && go test ./internal/ir/... ./internal/translate/... -run 'TestCorpus|Method'`
        *Done when:* `func (p Point) String () string` round-trips as an
        `*ir.Function` with a non-nil Receiver naming Point; a pointer
        receiver round-trips, or rejects with a clear error if pointer
        receivers are deferred.

  - [ ] **(c) satisfaction registry + emission**
        *Files:* `runtime/src/gada-reflect-interfaces.{ads,adb}`,
        `runtime/tests/reflect_interfaces_suite.{ads,adb}` (registered in
        `test_runner.adb` under `PKG=reflect.interfaces`),
        `compiler/internal/emit/interface.go`, golden tests.
        *Verify:* `make -C runtime test PKG=reflect.interfaces` +
        `cd compiler && go test ./internal/emit/... -run Interface`
        *Done when:* the compiler computes structural satisfaction for
        every (concrete type, interface) pair in the file and emits a
        `Register` call per pair at module init; the concrete type's
        descriptor gains its methods via `Add_Method` (closing the loop
        item 2c left open — reflect method enumeration); the runtime
        `Satisfies (Concrete, Iface)` and method-enumeration lookups are
        O(1); runtime coverage 100%, emit ≥ 95%.

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
