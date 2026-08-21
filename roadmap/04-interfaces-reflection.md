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

- [x] **Interface satisfaction tables**

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

  - [x] **(b) IR + translate: methods (receivers)**
        *Files:* `compiler/internal/ir/ir.go` (`Function.Receiver *Receiver`,
        nil for a free function; round-trip), `compiler/internal/translate/translate.go`
        (stop filtering `d.Recv`, attach the receiver, surface the method
        through `File`), testdata.
        *Verify:* `cd compiler && go test ./internal/ir/... ./internal/translate/... -run 'TestCorpus|Method'`
        *Done when:* `func (p Point) String () string` round-trips as an
        `*ir.Function` with a non-nil Receiver naming Point; a pointer
        receiver round-trips, or rejects with a clear error if pointer
        receivers are deferred.
        *Done 2026-06-25:* `Function` grows `Receiver *Receiver`, where
        `*ir.Receiver{Name, Type string, Pointer bool}` holds the receiver
        var name, the *named type* the method is declared on, and pointer-
        ness — the type is held by name (all 4c's satisfaction check needs
        to attach a method to its concrete type), so no general named-type
        node is required yet. The field is `omitempty` in `Function`'s
        JSON, so free-function goldens are untouched and only methods
        carry it. Translate drops the `d.Recv /= nil` reject and
        `transFunc` populates the receiver via `transReceiver`, which
        accepts a bare named receiver (`Point`) or a pointer receiver
        (`*Point`) and rejects generic receivers (`Point[T]`). Corpus
        fixture `method_decl` round-trips a value-receiver method, a
        pointer-receiver method (both naming `Counter`), and a free
        function (nil Receiver). Two synthetic ASTs pin transReceiver's
        generic-receiver defensive branches. `transReceiver` 100%, ir.go
        96.64%, translate/ 95.90%; go vet + golangci-lint clean. Method
        *emission* (the tagged-type bodies) and `Add_Method` population
        ride 4c / item 5.

  - [x] **(c) satisfaction registry + emission**

    Decomposed 2026-06-25 into the runtime store and the compiler
    emission, mirroring 2b → 2c (registry first, then the calls that
    populate it). The parent ticks when both do.

    - [x] **(c-i) runtime `Gada.Reflect.Interfaces` registry**
          *Files:* `runtime/src/gada-reflect-interfaces.{ads,adb}`,
          `runtime/tests/reflect_interfaces_suite.{ads,adb}` (registered
          in `test_runner.adb` under `PKG=reflect.interfaces`).
          *Verify:* `make -C runtime test PKG=reflect.interfaces`
          *Done when:* `Register (Concrete, Iface)` records a satisfaction
          pair and `Satisfies (Concrete, Iface)` answers membership in
          O(1) (a hashed store, protected for concurrent goroutine
          reads); a `No_Type` operand on either side is rejected
          (Constraint_Error), as in the type registry; coverage 100%.
          *Done 2026-06-25:* `Register` / `Satisfies` front a protected
          `Store` wrapping a `Hashed_Sets` of a `Pair{Concrete, Iface}`
          record (hash mixes the two Type_Ids order-sensitively, so a
          pair and its reverse are distinct facts). `Register` uses
          `Include` (idempotent re-registration) and raises
          `Constraint_Error` if either operand is `No_Type`; `Satisfies`
          is a protected function (concurrent goroutine reads) returning
          `Contains` — O(1). Four AUnit cases (`PKG=reflect.interfaces`):
          round-trip, unregistered + directional asymmetry, idempotent
          double-register, and the No_Type rejection on each side.
          `gada-reflect-interfaces.adb` 100% (13/13); runtime/ stays 100%
          (867/867). 4c-ii emits the `Register` calls against this.

    - [x] **(c-ii) compiler satisfaction computation + emission**
          *Files:* `compiler/internal/emit/interface.go`, golden tests
          (`compiler/internal/emit/testdata`).
          *Verify:* `cd compiler && go test ./internal/emit/... -run Interface`
          *Done when:* the compiler computes structural satisfaction
          (a concrete type's method set ⊇ an interface's, by name +
          signature) for every (concrete, interface) pair in the file and
          emits a `Gada.Reflect.Interfaces.Register` call per satisfied
          pair at module init; the concrete type's descriptor gains its
          methods via `Add_Method` (closing the loop item 2c left open —
          reflect method enumeration); emit ≥ 95%.
          *Done 2026-06-25:* `interface.go`'s `satisfiedPairs` gathers the
          file's interfaces (TypeDecls over `*ir.InterfaceType`) and each
          concrete type's receiver methods, then for every (concrete,
          interface) pair checks `methodSetSatisfies` — every interface
          method has a concrete method of the same name and identical
          param/result type lists (`metaTypeKey` canonicalises each type;
          the empty `interface{}` is satisfied vacuously). It is computed
          independent of Type_Id, so the with-clause pre-pass
          (`needsIfaceReg`) and the emitter share it. `metaTypeKind` gains
          the `Interface_Kind` case; `collectTypeMeta` a third pass that
          attaches each type's method names (interface signatures, or a
          concrete's receiver funcs) so `emitTypeMetadata` emits
          `Add_Method` — finally populating the reflect method list item
          2c left empty. `emitInterfaceSatisfaction` writes one
          `Gada.Reflect.Interfaces.Register (Concrete => …, Iface => …)`
          per pair into the module-init block. Method *bodies* are skipped
          in the subprogram loops (dispatch is item 5). Corpus golden
          `iface_satisfy` (Point implements Stringer) shows Add_Method on
          both descriptors + the Register call; `TestInterfaceSatisfaction`
          covers the match, the empty interface, and the missing-method /
          wrong-result / wrong-arity rejections. Only *value*-receiver
          methods count toward a value type's method set (both for
          satisfaction and the descriptor) — a `func (p *T)` is in *T's
          set, not T's; pointer-type satisfaction (`*T` as its own reflect
          type) rides item 5. emit/ 95.41%, interface.go 97.62%,
          typemeta.go 98.45%; go vet + golangci-lint clean.

- [x] **Compiler emission — interface method calls** — all four
      sub-items done (5a structs, 5b interfaces, 5c methods, 5d dispatch).

  Decomposed 2026-06-26: the one-line "emit a dispatching call" presumes
  a Go-type → Ada-type emission layer that **does not exist** — structs,
  interfaces, and methods have only ever been emitted as *reflect
  metadata* (item 2/4), never as usable Ada types. Under the Hybrid model
  (native Ada tagged dispatch) that layer must come first. Split into four
  sub-items; the parent ticks when all four do. All target the
  `package main` programs in scope, where types live in the `Main`
  procedure's declarative part (no `.ads`/spec split needed yet;
  multi-package struct visibility is deferred). Boundaries may refine as
  each lands.

  - [x] **(5a) struct types → Ada records** — all sub-items done
        (5a-i type declarations, 5a-ii values, 5a-iii zero/partial fill).

    Split 2026-06-26 into the type declaration (5a-i, emit-only — the
    struct IR already exists from items 2a/4a) and the value use (5a-ii,
    full-stack — struct literals have no IR node and translate rejects
    them). Tagged-ness + the `and Interface` derivation ride 5b.

    - [x] **(5a-i) struct type declarations**
          *Files:* `compiler/internal/emit/struct.go`, golden tests.
          *Verify:* `cd compiler && go test ./internal/emit/... -run Struct`
          *Done when:* a struct `TypeDecl` emits an Ada record type in the
          enclosing unit's declarative part (the `Main` procedure for a
          `package main`, the package body otherwise); an empty struct
          emits `is null record`.
          *Done 2026-06-26:* `emitStructTypes` writes one record per Go
          struct type (`type Point is record X : Integer; Y : Integer; end
          record;`), field types via the existing `typeName`; an empty
          struct emits `type Empty is null record;` (a fieldless record is
          illegal Ada). Wired into both `emitPackageBody` and
          `emitMainProcedure` at the top of the declarative part, with the
          blank-line bookkeeping. Goldens: `type_decl` / `iface_satisfy`
          (Point gains its record; the named scalar Celsius and the
          Stringer interface stay metadata-only — named-scalar and
          interface type emission are separate) and a new `package main`
          fixture `struct_main` (record in `Main` + the empty-struct
          `null record`). struct.go 100%, emit/ 95.58%; vet + lint clean.

    - [x] **(5a-ii) struct values — literals + field access**
          *Files:* `compiler/internal/ir/ir.go` (`*ir.StructLit`),
          `compiler/internal/translate/translate.go` (`transCompositeLit`
          struct arm), `compiler/internal/emit`, golden tests.
          *Verify:* `cd compiler && go test ./internal/emit/... ./internal/translate/... -run 'Struct|TestCorpus'`
          *Done when:* a *complete* composite literal `Point{X: 1, Y: 2}`
          lowers to an Ada named/positional aggregate and a field access
          `p.X` emits as `P.X`, so a struct-using program round-trips end
          to end. (`TestCorpus` — not matched by `-run Struct` alone — is
          the test that diffs the `struct_values` golden, so the verify
          command names it explicitly.)
          *Done 2026-08-17:* new `*ir.StructLit{TypeName, Fields}` +
          `*ir.StructLitField{Name, Value}` (kind-tagged JSON, `typeName`
          missing-child guard, a required-`value` guard — a struct field
          value is never optional, unlike a MapEntry — golangci
          exclusion, direct Unmarshal error-path tests mirroring
          `TestMapEntryDirect`). `transCompositeLit` gains an `*ast.Ident`
          arm via `transStructFields`, handling the keyed (`Point{X:1}`)
          and positional (`Point{1,2}`) forms and rejecting a
          keyed/positional mix or a non-ident key; an *anonymous* struct
          literal (`*ast.StructType`) stays rejected (no named Ada record
          to name).
          Emit consults the declared field set (`structByName`) to stay
          **correct-or-loud** — an Ada record aggregate must supply a
          value for every component (RM 4.3.1), which Go literals need
          not: `emitStructLit` renders a qualified aggregate for a
          *complete* keyed (`Point'(X => 1, Y => 2)`) or multi-field
          positional (`Point'(3, 4)`) literal, emits the **named** form
          `Tick'(N => 7)` for a *single* positional field (a
          one-component positional aggregate `Tick'(7)` is a qualified
          expression in Ada, not an aggregate), and `Empty'(null record)`
          for a genuinely fieldless struct. `inferDeclType` types a `:=`
          struct-literal decl by its named type; `emitSelector` runs the
          field through `adaIdent` so a lowercase Go field (`p.count`)
          lines up with the capitalised record component 5a-i emits.
          Corpus fixture `struct_values` proves the round trip (complete
          keyed + multi-field positional + single-field positional +
          field access via `fmt.Println`); the empty-struct,
          lowercase-field, and every rejection branch are pinned by
          direct emit unit tests. emit/ + translate/ ≥95%, runtime/ 100%;
          vet + lint + gate clean.
          *Rejected loudly, not mis-emitted* (each a clear emit
          diagnostic, no silent-broken Ada — deferred correctness is
          [[5a-iii]]): a zero-value `Point{}` or partial `Point{X: 1}`
          literal of a non-empty struct (needs the omitted fields' Go
          zero values), and a composite literal on a non-struct/undeclared
          named type (`type Ints []int; Ints{…}` — without *types.Info*
          the translator cannot tell it from a struct, so emit fails when
          the name resolves to no struct TypeDecl).

    - [x] **(5a-iii) struct values — zero-value & partial literals**
          *Files:* `compiler/internal/emit`, golden tests.
          *Verify:* `cd compiler && go test ./internal/emit/... ./internal/translate/... -run 'Struct|TestCorpus'`
          *Done when:* a zero-value `Point{}` and a partial `Point{X: 1}`
          literal lower to a *complete* Ada aggregate whose omitted scalar
          components carry each field's Go zero value (int→0, bool→False,
          float→0.0), so `emitStructLit` no longer rejects them (see the
          5a-ii "rejected loudly" note). Surfaced by the item-5a-ii code
          review (2026-08-17): emit must synthesise a value for every
          record component, which needs per-field-type zero-value
          emission — its own atomic unit rather than a rushed rider on
          5a-ii. (Non-scalar and `string` fields are out of scope — see
          the correct-or-loud note below; their zeroes — empty
          slice/map, nil chan, nested-struct aggregate — ride the later
          item that makes those valid record components.)
          *Done 2026-08-17:* `emitStructLit` fills a keyed/empty literal
          by iterating the *declared* field set: a provided value where
          the literal names the field, `zeroValueFor(field.Type)`
          otherwise, so `Config{}` → `Config'(Width => 0, Height => 0,
          Depth => 0)` and `Config{Width: 80}` → `Config'(Width => 80,
          Height => 0, Depth => 0)` — omitted fields zeroed in declared
          order (Ada named associations are order-independent, so a
          reordered `Point{Y: 9}` still fills correctly). Zero values are
          *explicit* Go zeroes, not Ada's `<>` box (which would leave a
          scalar uninitialised, not zero): int→`0`, bool→`False`,
          string→`""`, float64→`0.0`. New corpus fixture `struct_zero`
          proves zero + partial fill end to end; the non-int scalar
          spellings and declared-vs-literal order are pinned by
          `TestStructZeroFill`. emit/ 95.64%, translate/ 96.13%,
          runtime/ 100%; vet + lint + gate clean.
          *Scoped to scalar fields, made correct-or-loud (code review
          2026-08-17):* struct fields lower to valid Ada only for
          `int`/`bool`/`float64` (definite scalar components with a
          synthesisable zero). A new `validStructFieldType` gate — shared
          by `emitStructTypes` (the record declaration) and `zeroValueFor`
          (the fill), so they stay in lockstep — rejects the rest at the
          struct's *declaration*, before any literal: a `string` field
          (an unconstrained `String` record component is invalid Ada) and
          a slice/map/chan field (its `Slices_Of_<T>`/`Maps_Of_…`/
          `Channels_Of_<T>` instantiation is not driven from struct
          fields — `recordTypeInTree` does not recurse into a
          `StructType`). This closes the silent-breakage the review found:
          previously a `string`/slice field emitted an uncompilable
          record component into a byte-checked golden. `zeroValueFor`
          reuses the existing `zeroLiteralOf` for the literal spelling
          (no third copy of the scalar zero table). The `struct_zero`
          fixture now carries `bool`+`float` fields, so a compiling golden
          exercises those components and their zero fills end to end.
          Lifting `string` (bounded/constrained component) and the
          composite fields (field-type collection walk + non-scalar
          zeroes) rides a later item.

  - [x] **(5b) interface types → Ada interface types** — both sub-items
        done (5b-i interface declarations + abstract ops, 5b-ii
        satisfying-record derivation + overriding specs).
        *Files:* `compiler/internal/emit/emit.go`, golden tests.
        *Verify:* the two sub-items' commands (a bare `-run Iface`
        matches no test); to run both halves at once:
        `cd compiler && go test ./internal/emit/... ./internal/translate/... -run 'Iface|Interface|Overriding|TestCorpus'`
        *Done when:* a `type Stringer interface { String() string }` emits
        `type Stringer is interface; function String (Self : Stringer)
        return … is abstract;`, and each satisfying concrete type's
        record gains the `and Stringer` interface derivation with the
        `overriding` method specs.

        Decomposed 2026-08-17 into the two halves, which share a
        method-signature renderer (a `MethodSig`/receiver → Ada
        `function`/`procedure` spec with a controlling first parameter)
        but touch different emission sites. 5b emits *specs only* — the
        `overriding` bodies (5c) and the first real gnat compile (item 7)
        follow; until 5c the emitted unit is intentionally incomplete
        (a declared primitive op with no body), which the byte-checked
        goldens capture without compiling.

    - [x] **(5b-i) interface type declarations + abstract ops**
          *Files:* `compiler/internal/emit/interface.go`, golden tests.
          *Verify:* `cd compiler && go test ./internal/emit/... ./internal/translate/... -run 'Iface|Interface|TestCorpus'`
          *Done when:* each `type X interface { M(...) R }` TypeDecl emits
          `type X is interface;` followed by one abstract operation per
          method — `function M (Self : X; …) return R is abstract;` (1
          result) or `procedure M (Self : X; …) is abstract;` (0 results)
          — in the enclosing unit's declarative part. The empty
          `interface{}` emits a bare `type X is interface;`. A method with
          2+ results is rejected loudly (Ada functions return one value).
          *Done 2026-08-17:* `emitInterfaceTypes` writes each interface as
          `type X is interface;` plus one `interfaceMethodSpec` per
          method (function for a single result, procedure for none), the
          interface as the controlling `Self` parameter; an unnamed method
          parameter gets a synthetic `Arg_<n>` (Ada parameters must be
          named). Interfaces are emitted before structs — a record that
          derives one (5b-ii) needs it declared already — via a new
          `emitTypeDecls` unit that replaced the `hasStructs` type slot in
          both `emitMainProcedure` and `emitPackageBody` with a `hasTypes`
          umbrella, keeping the declarative-part blank-line bookkeeping in
          one place. New corpus fixture `interface_types` (parameterless
          function, function + procedure with params, empty interface);
          the multi-result rejection and unnamed-param + typeName error
          paths are pinned by `TestInterfaceMethodSpec` /
          `TestInterfaceTypeEmitError`. interface.go 97.78%, emit/ 95.71%;
          vet + lint + gate clean. Specs only — the `overriding` bodies
          ride 5c, so the emitted unit is intentionally incomplete (a
          declared abstract op with no concrete override until 5b-ii adds
          the derivation and 5c the bodies); the byte-checked goldens
          capture the text without compiling.

    - [x] **(5b-ii) satisfying records derive the interface(s)**
          *Files:* `compiler/internal/emit/struct.go`, golden tests.
          *Verify:* `cd compiler && go test ./internal/emit/... ./internal/translate/... -run 'Iface|Overriding|TestCorpus'`
          *Done when:* a struct that satisfies ≥1 interface (per
          `satisfiedPairs`) emits its record as `type C is new I1 [and I2
          …] with record … end record;` (or `with null record;` when
          fieldless), tagged and deriving each satisfied interface, each
          followed by the `overriding` spec of every method it implements
          from those interfaces. A struct that satisfies no interface
          stays the plain untagged record 5a-i emits.
          *Done 2026-08-17:* `emitStructTypes` consults `satisfiedPairs`
          and, for a satisfying struct, emits the tagged derivation
          header (`is new Reader and Writer with record …` / `with null
          record;`) plus `overridingSpecs` — one `overriding` op per
          distinct interface method the type implements, in
          interface-then-method source order, deduped by name (a method
          shared by two derived interfaces is overridden once), each spec
          mirroring the concrete method's signature with its receiver as
          the controlling first parameter (`overriding function Read
          (B : Buffer) return Integer;`). Reuses `dispatchOpSpec` with
          5b-i. New corpus fixture `iface_multi` (Buffer derives Reader +
          Writer with a shared Close; Nop derives Reader with a null
          record); `iface_satisfy`'s Point now derives Stringer.
          `overridingSpecs` dedup / missing-method-skip / multi-result
          error paths pinned by `TestOverridingSpecs`. vet + lint + gate
          clean. Specs only — the overriding *bodies* ride 5c, so the
          emitted unit is intentionally incomplete (a declared primitive
          op with no body) until then; the byte-checked goldens capture it
          without compiling.
          *Code-review fixes (2026-08-17, PR #40):* (a) a method-less
          interface (`type Any interface{}`) is excluded from *derivation*
          — every type satisfies it vacuously, so deriving it would flip
          every struct in the file from an untagged record to a tagged
          type for no dispatch; the empty interface still emits its bare
          declaration and its reflect-registry satisfaction (`ifacesFor`
          filters by method count; fixture `iface_empty`). (b) A method
          parameter whose Ada form collides case-insensitively with the
          controlling `Self` (a Go param named `self`) — or with another
          param (`x`/`X`) — is uniquified (`Self_2`) so the spec compiles
          (`dispatchOpSpec` via `uniqueParamName`). (c) `valueMethodsByType`
          is now shared with `satisfiedPairs` (one definition of the
          value-type method set, no drift). Unnamed receiver → `Self` and
          the pointer-receiver exclusion are now directly tested.
          *Deferred (SPARK):* the emitted `interface`/tagged types use Ada
          dynamic dispatch, which the verifiable-subset target
          (`-mode=spark`, Pure Goal 4) restricts; making the Hybrid
          dispatch SPARK-compatible (or gating it out under spark mode) is
          an open question for the profile/verification work, not this
          item.

  - [x] **(5c) methods → overriding subprograms**
        *Files:* `compiler/internal/emit/emit.go`, golden tests.
        *Verify:* `cd compiler && go test ./internal/emit/... ./internal/translate/... -run 'Method|Iface|SubpHeader|TestCorpus'`
        *Done when:* each `func (p Point) M(args) …` emits the body of the
        corresponding `overriding` subprogram (the dispatch operation
        whose spec 5b declared), with the receiver as the controlling
        first parameter. Closes the loop 4c-ii left open (method bodies
        were skipped).
        *Done 2026-08-18:* the two subprogram-emission loops
        (`emitPackageBody`, `emitMainProcedure`) no longer skip methods;
        `overridingMethods` selects exactly the value-receiver methods
        whose (concrete, method) 5b-ii declared an overriding spec for
        (receiver type derives ≥1 method-bearing interface, method name
        matches one of those interfaces' methods), and `subpHeader`
        renders a method as `overriding function/procedure Name (Recv :
        Type; …) [return R] is` — the *same* `dispatchOpSpec` the 5b spec
        used, tail ` is` instead of `;`, so spec and body match exactly.
        The body reuses the whole `emitSubprogram` machinery (decls,
        defers, panic handler, `end Name;`); the receiver reaches the
        body as an ordinary identifier, so `b.data` → `B.Data`. With this
        the interface unit is finally *complete* — `iface_satisfy`
        (Point.String → `return "pt"`) and `iface_multi` (Buffer.Read →
        `return B.Data`, Nop.Read → `return 0`, the rest `null`) each emit
        a tagged type, its abstract op, the overriding spec, and now the
        matching body, forming compilable Ada (first gnat compile still
        rides item 7). A method on a non-deriving type stays reflect-only:
        `method_decl` (new emit fixture) emits `Counter` as a plain record
        and a body for the free function `Zero` only — `Get` is excluded
        (its direct-call emission rides a later item). `subpHeader`'s
        method path (named/unnamed receiver, signature error) pinned by
        `TestSubpHeaderMethod`; `overridingMethods` 100%. vet + lint +
        gate clean.
        *Code-review fixes (2026-08-18, PR #41):* (a) a method whose
        parameter name folds case-insensitively onto the receiver or
        another parameter is now rejected loudly (`paramsCollide` in
        `subpHeader`) — the header uniquifies such a name (`Self_2`,
        `X_2`, from the 5b Self-collision fix) but the *body* references
        parameters by their original Go name, so a rename would silently
        bind the wrong argument; honouring it (a Go-name → Ada-name alias
        table) rides the later item that brings direct method calls.
        (b) The `package main` overriding-method path (`emitMainProcedure`,
        previously 0 executions) is now covered by a fixture
        (`iface_main`: Gauge derives Meter, `Value` body nested in `Main`
        before the `G` var freezes Gauge). (c) `overridingSpecs` (5b-ii)
        and `overridingMethods` (5c) now share `overridingFuncsFor`, one
        definition of which methods override, so the spec and body sets
        cannot diverge. emit/ 96.00%, translate/ 96.13%, runtime/ 100%.

  - [x] **(5d) interface method calls → dispatching calls**
        *Files:* `compiler/internal/{ir,translate,emit}`, golden tests.
        *Verify:* `cd compiler && go test ./internal/emit/... ./internal/translate/... -run 'Dispatch|TypeName|TestCorpus'`
        *Done when:* `iface.Method(args)` on an interface-typed value emits
        a dispatching call on the `'Class` view, resolved at run time by
        Ada's own tag — the Hybrid "native vtable" in place of a
        hand-rolled itable.
        *Done 2026-08-18:* the missing Go-type → Ada-type primitive for a
        *named* type reference now exists — new `*ir.NamedType{Name}` (a
        bare non-builtin type identifier: an interface- or struct-typed
        parameter/result), produced by `transType` for any identifier
        that is not a supported scalar and not an unsupported Go builtin
        (the wider numerics / complex / byte / rune / error / any, which
        stay loud errors). `emit.typeName` became a method (with
        `dispatchOpSpec`) so it can resolve a `NamedType` against the
        file's declarations: an interface name renders the class-wide
        `Name'Class` view — the operand type on which an Ada call
        dispatches (RM 3.9.2) — a struct name the plain record type, and a
        name that is neither a loud error. The call site needed no new
        form: a method call `s.Speak()` already lowers to the Ada
        prefixed-view `S.Speak`, which *is* a dispatching call when `S` is
        class-wide. New fixture `dispatch_call` (`func describe(s Speaker)
        { s.Speak() }` → `procedure Describe (S : Speaker'Class) is begin
        S.Speak; end;`). `typeName`'s interface/struct/undefined arms
        pinned by `TestTypeNameNamed`; `NamedType` JSON round-trip +
        missing-name guard in ir. vet + lint + gate clean.
        *Code-review fixes (2026-08-18, PR #42):* (a) `NamedType` made a
        struct-typed parameter expressible, and a method call on one whose
        method is *not* an interface method (a plain method on a
        non-deriving type — no emitted subprogram) previously emitted a
        dangling `C.Get`. `emitCallStmt` now rejects such a call loudly
        (guarded by `dispatchMethodNames`, the set of interface method
        names — the only callable ones); a direct call to a non-dispatch
        method rides a later item. `s.Speak()` on an interface value is
        unaffected. (b) New fixture `struct_param` proves the struct arm
        of `typeName`'s `NamedType` resolution end to end (`func area(p
        Point) int { return p.X }` → `function Area (P : Point) return
        Integer`). (c) The `unsupportedBuiltinType` denylist is now
        table-tested per entry (all 18), and a named-scalar/undefined
        `NamedType` gets an accurate emit diagnostic instead of a
        misleading "not a declared struct or interface". emit/ 96.02%,
        translate/ 96.15%, runtime/ 100%.
        *Not yet (rides item 7's end-to-end example / later items):* a
        `var s I = concrete` local (`*ast.DeclStmt` is still unsupported;
        only `:=` infers a *concrete* type); a method call in *expression*
        position (`x := s.String()` — call-as-expression needs
        *types.Info*); and passing a concrete value to an interface
        parameter (Ada widens a specific type to its class-wide view
        automatically, so `describe(Sink'(…))` should already compile once
        argument emission for it lands).

- [ ] **Compiler emission — type assertions and type switches**
      *Files:* `compiler/internal/{ir,translate,emit}`, golden tests
      *Verify:* `cd compiler && go test ./internal/emit/... -run Assert`
      *Done when:* `x.(T)`, `x.(T, ok)`, `switch x := y.(type) { ... }` all emit correctly.

  Decomposed 2026-08-21: three forms, each greenfield (no IR node, no
  translate/emit path existed), sharing the class-wide operand and tag
  machinery. The parent ticks when all three do.

  - [x] **(6a) single-value assertion `x.(T)`**
        *Files:* `compiler/internal/{ir,translate,emit}`, golden tests.
        *Verify:* `cd compiler && go test ./internal/emit/... ./internal/translate/... -run 'Assert|TypeAssert|TestCorpus'`
        *Done when:* `v := x.(T)` on an interface-typed value lowers to the
        Ada view conversion `T (X)` and binds v to T.
        *Done 2026-08-21:* new `*ir.TypeAssert{X, Type, CommaOK}` (kind-
        tagged JSON, x/type missing-child guards); `transExpr` lowers
        `*ast.TypeAssertExpr` (rejecting the `x.(type)` guard shape, which
        is a type switch); `emitTypeAssert` renders the view conversion
        `T (X)` — converting a class-wide operand to a specific type in
        its class checks the tag (RM 4.6) and raises Constraint_Error on a
        mismatch (Go panics; a faithful Gada.Core panic rides a later
        item), and `inferDeclType` binds a `:=` assertion to the asserted
        type. `typeName`/`inferDeclType` are now methods (NamedType
        resolution). Fixture `type_assert` (`d := s.(Dog); return d.Legs`
        → `D : Dog := Dog (S); return D.Legs;`), integrating the interface
        param (5d) + tagged type (5b/5c) + assertion. `emitTypeAssert`
        comma-ok/error arms pinned by `TestEmitTypeAssert`; `TypeAssert`
        round-trips in ir. emit/ 96.05%, translate/ 96.02%, runtime/
        100%; vet + lint + gate clean.
        *Correct-or-loud:* only a concrete struct target is a valid Ada
        view conversion of a class-wide operand, so `emitTypeAssert`
        rejects an interface target (`x.(I)` is a does-it-implement check,
        not a down-conversion), a named-scalar/builtin target (`Integer
        (X)` on a class-wide operand is not a legal conversion), and a
        non-named target — each a loud error, deferred to a later item —
        rather than emit invalid Ada.

  - [ ] **(6b) comma-ok assertion `v, ok := x.(T)`**
        *Files:* `compiler/internal/emit`, golden tests.
        *Verify:* `cd compiler && go test ./internal/emit/... -run Assert`
        *Done when:* `v, ok := x.(T)` lowers to a membership test
        (`OK := X in T'Class`) plus a guarded view conversion at statement
        position, so ok reports the match without raising. (`transAssign`
        already flips `TypeAssert.CommaOK` for the 2-LHS shape; emit's
        statement-position lowering — mirroring the comma-ok chan receive
        — is the work.)

  - [ ] **(6c) type switch `switch x := y.(type) { ... }`**
        *Files:* `compiler/internal/{ir,translate,emit}`, golden tests.
        *Verify:* `cd compiler && go test ./internal/emit/... -run Assert`
        *Done when:* a type switch lowers to a chain of membership tests
        (`if X in T1'Class then … elsif X in T2'Class then … else …`),
        with the switch variable viewed as each case's type inside its
        arm.

- [ ] **`iface_dispatch` example**
      *Files:* `examples/iface_dispatch/main.go`, `examples/iface_dispatch/expected_output.txt`
      *Verify:* `make example HELLO=iface_dispatch`
      *Done when:* example exercises 3+ types implementing 2 interfaces with reflection-based method enumeration; output matches expected.

> **Note on json_roundtrip:** A reflection-end-to-end exit example
> using `encoding/json` is appropriate but depends on Phase 7's
> `encoding/json` port. It is therefore staged into Phase 7. Phase 4's
> exit example is `iface_dispatch`, which is reflection-complete
> without requiring a JSON encoder.
