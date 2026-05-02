// Package emit produces Ada source from GADA IR.
//
// Phase 1 scope mirrors the corpus in
// compiler/internal/translate/testdata: package-level functions made
// of assignments, ifs, classic-or-infinite for-loops, returns, and
// calls; expressions over the four basic types int / string / bool /
// float64; and a single recognised standard-library call,
// `fmt.Println`. Anything outside that subset returns an explicit
// "not supported in Phase 1" error rather than producing silently
// wrong Ada.
//
// Output shape, one Ada compilation unit per ir.File:
//
//   - Go `package main` becomes a standalone subprogram, `procedure
//     Main is ... end Main;`. If the file contains a `func main()`
//     (no params, no results), its body forms the procedure body and
//     any other top-level functions become nested subprograms.
//     Otherwise the procedure body is `null;` and every Go func is
//     nested.
//   - Any other package becomes an Ada package body, `package body P
//     is ... end P;`, with each top-level Go func emitted as a
//     sibling subprogram.
//
// Type mapping: int→Integer, string→String, bool→Boolean,
// float64→Long_Float.
//
// `:=` assignments at the head of a function body are hoisted into
// the declarative region; subsequent plain `=` becomes Ada `:=`. The
// trivial integer for-loop pattern
// `for i := S; i < E; i = i + 1 { ... }` is recognised and emitted as
// `for I in S .. E - 1 loop ... end loop;`. The bare `for { ... }`
// becomes Ada `loop ... end loop;`.
//
// `fmt.Println(...)` is rewritten to `Println (...)` and a top-of-
// file `with Gada.Core.IO; use Gada.Core.IO;` is added when the file
// imports "fmt".
//
// Identifier policy: Go names are first-letter-capitalised so they
// look canonically Ada. A name whose lowercase form is an Ada reserved
// word (e.g. Go `loop`) gains a `_K` suffix to avoid the collision.
package emit

import (
	_ "embed"
	"fmt"
	"io"
	"strconv"
	"strings"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// ProjectTemplate is the text/template body of the GNAT project file
// the `gada build` driver renders alongside emitted Ada sources. It
// is exposed as a string so the driver in compiler/cmd/gada can fill
// it without depending on an on-disk path. The fields are:
//
//	{{.ProjectName}}    Ada project name (also the .gpr base name)
//	{{.RuntimeProject}} Path (without extension) to gada_core.gpr
//	{{.SourceDir}}      Directory holding emitted .adb / .ads files
//	{{.ObjectDir}}      gprbuild's object directory
//	{{.ExecDir}}        Where the produced binary lands
//	{{.MainFile}}       Main subprogram's source file (e.g. "main.adb")
//
//go:embed template.gpr.tmpl
var ProjectTemplate string

// Package writes the Ada compilation unit for the given IR package
// to w. Phase 1 expects the package to contain exactly one file; the
// translator currently produces one *ir.File per Go source file, so
// this contract holds end-to-end.
func Package(p *ir.Package, w io.Writer) error {
	if p == nil {
		return fmt.Errorf("emit: nil package")
	}
	if len(p.Files) != 1 {
		return fmt.Errorf("emit: expected exactly one file, got %d", len(p.Files))
	}
	e := newEmitter(p.Name, p.Files[0])
	if err := e.run(); err != nil {
		return err
	}
	_, err := io.WriteString(w, e.buf.String())
	return err
}

// emitter accumulates Ada source into buf with a current indent
// level. Errors are sticky on err and silence further work via the
// guards in emitStmt / emitExpr / etc.
//
// Phase 2 added these cross-cutting maps:
//
//   - sliceElems[k]  = first ir.Type seen with Ada base name k
//     (e.g. "Integer" → *ir.IntType{}). Drives the
//     `package Slices_Of_<T> is new …` instantiation
//     list emitted at the top of the decl region;
//     one entry per distinct element type per file.
//   - sliceElemOrder = insertion-ordered list of element-type keys,
//     so the emitted Ada is deterministic regardless
//     of map iteration order.
//   - mapPairs[k]    = first *ir.MapType seen with canonical pair key
//     k = "<KAdaName>_To_<VAdaName>". Drives the
//     `package Maps_Of_<K>_To_<V> is new …` block
//     emitted alongside the slice instantiations.
//   - mapPairOrder   = insertion-ordered list of pair keys (stable
//     output regardless of Go map iteration).
//   - localTypes     = subprogram-local name → declared type. Built
//     from the active function's params and from
//     Define-true `:=` assigns at the head of its
//     body. Read by IndexExpr / SliceExpr / the
//     slice-typed BuiltinCalls (append/len/cap) and
//     by the map-side IndexExpr / range / delete /
//     len so they can pick the right
//     Slices_Of_<T> or Maps_Of_<K>_To_<V> for
//     dispatch.
type emitter struct {
	pkgName string
	file    *ir.File

	buf    strings.Builder
	indent int

	needsCoreIO    bool
	needsCoreDefer bool // any DeferStmt seen → emit `with Gada.Core.Defer;`
	needsCorePanic bool // any panic/recover BuiltinCall seen → emit `with Gada.Core.Panic;` and `package Panic_Of_Integer is new ...`
	sliceElems     map[string]ir.Type
	sliceElemOrder []string
	mapPairs       map[string]*ir.MapType
	mapPairOrder   []string
	localTypes     map[string]ir.Type
	rangeCounter   int
	err            error
}

func newEmitter(pkg string, f *ir.File) *emitter {
	e := &emitter{
		pkgName:    pkg,
		file:       f,
		sliceElems: map[string]ir.Type{},
		mapPairs:   map[string]*ir.MapType{},
	}
	for _, imp := range f.Imports {
		if imp == "fmt" {
			e.needsCoreIO = true
		}
	}
	e.collectSliceElems()
	return e
}

// collectSliceElems walks the file's IR to surface every element type
// that appears under any *ir.SliceType (in params/results) or
// *ir.SliceLit (in expressions). It runs once at construction time so
// the with-clause and instantiation block can be emitted before any
// subprogram body. Slice-of-slice (`[][]T`) recurses through Elem
// naturally; the leaf record is keyed by its Ada base name.
func (e *emitter) collectSliceElems() {
	for _, d := range e.file.Decls {
		fn, ok := d.(*ir.Function)
		if !ok {
			continue
		}
		for _, p := range fn.Params {
			e.recordTypeInTree(p.Type)
		}
		for _, p := range fn.Results {
			e.recordTypeInTree(p.Type)
		}
		e.walkStmts(fn.Body)
	}
}

func (e *emitter) recordTypeInTree(t ir.Type) {
	if t == nil {
		return
	}
	switch t := t.(type) {
	case *ir.SliceType:
		e.recordSliceElem(t.Elem)
		e.recordTypeInTree(t.Elem)
	case *ir.MapType:
		e.recordMapPair(t)
		e.recordTypeInTree(t.Key)
		e.recordTypeInTree(t.Value)
	}
}

// recordMapPair adds m to mapPairs/mapPairOrder if its (K, V) shape
// is fresh. The canonical key is "<KName>_To_<VName>", computed from
// elemBaseName so unsupported key/value types fail fast at the
// pre-scan rather than deep inside per-call dispatch.
func (e *emitter) recordMapPair(m *ir.MapType) {
	key, err := mapPairKey(m)
	if err != nil {
		e.fail(err)
		return
	}
	if _, present := e.mapPairs[key]; !present {
		e.mapPairs[key] = m
		e.mapPairOrder = append(e.mapPairOrder, key)
	}
}

func (e *emitter) recordSliceElem(elem ir.Type) {
	name, err := elemBaseName(elem)
	if err != nil {
		// Surface the typed error at the pre-scan point so unsupported
		// element types fail fast (e.g. slice-of-slice in Phase 2).
		// Without this, the eventual instantiation block would silently
		// omit the offending type and the per-call emit later would
		// report a more confusing "cannot determine instantiation"
		// secondary failure.
		e.fail(err)
		return
	}
	if _, present := e.sliceElems[name]; !present {
		e.sliceElems[name] = elem
		e.sliceElemOrder = append(e.sliceElemOrder, name)
	}
}

func (e *emitter) walkStmts(stmts []ir.Stmt) {
	for _, s := range stmts {
		e.walkStmt(s)
	}
}

func (e *emitter) walkStmt(s ir.Stmt) {
	switch s := s.(type) {
	case *ir.Assign:
		for _, x := range s.LHS {
			e.walkExpr(x)
		}
		for _, x := range s.RHS {
			e.walkExpr(x)
		}
	case *ir.If:
		e.walkExpr(s.Cond)
		e.walkStmts(s.Then)
		e.walkStmts(s.Else)
	case *ir.For:
		e.walkStmt(s.Init)
		e.walkExpr(s.Cond)
		e.walkStmt(s.Post)
		e.walkStmts(s.Body)
	case *ir.Return:
		for _, x := range s.Results {
			e.walkExpr(x)
		}
	case *ir.Call:
		e.walkExpr(s.Fun)
		for _, x := range s.Args {
			e.walkExpr(x)
		}
	case *ir.ExprStmt:
		e.walkExpr(s.X)
	case *ir.BuiltinCall:
		if s.Name == "panic" || s.Name == "recover" {
			e.needsCorePanic = true
		}
		for _, x := range s.Args {
			e.walkExpr(x)
		}
	case *ir.RangeStmt:
		e.walkExpr(s.X)
		e.walkStmts(s.Body)
	case *ir.DeferStmt:
		e.needsCoreDefer = true
		e.walkStmt(s.Call)
	case nil:
		// optional Init/Post on bare for {}.
	}
}

func (e *emitter) walkExpr(x ir.Expr) {
	switch x := x.(type) {
	case *ir.SliceLit:
		e.recordSliceElem(x.Elem)
		e.recordTypeInTree(x.Elem)
		for _, el := range x.Elems {
			e.walkExpr(el)
		}
	case *ir.MapLit:
		e.recordMapPair(&ir.MapType{Key: x.Key, Value: x.Value})
		e.recordTypeInTree(x.Key)
		e.recordTypeInTree(x.Value)
		for _, ent := range x.Entries {
			e.walkExpr(ent.Key)
			e.walkExpr(ent.Value)
		}
	case *ir.IndexExpr:
		e.walkExpr(x.X)
		e.walkExpr(x.Index)
	case *ir.SliceExpr:
		e.walkExpr(x.X)
		e.walkExpr(x.Low)
		e.walkExpr(x.High)
	case *ir.BuiltinCall:
		if x.Name == "panic" || x.Name == "recover" {
			e.needsCorePanic = true
		}
		for _, a := range x.Args {
			e.walkExpr(a)
		}
	case *ir.BinOp:
		e.walkExpr(x.X)
		e.walkExpr(x.Y)
	case *ir.UnaryOp:
		e.walkExpr(x.X)
	case *ir.Selector:
		e.walkExpr(x.X)
	}
}

func (e *emitter) run() error {
	if e.needsCoreIO {
		e.println("with Gada.Core.IO; use Gada.Core.IO;")
	}
	if len(e.sliceElemOrder) > 0 {
		e.println("with Gada.Core.Slices;")
	}
	if len(e.mapPairOrder) > 0 {
		e.println("with Gada.Core.Maps;")
		e.println("with Gada.Core.Hash;")
	}
	if e.needsCoreDefer {
		e.println("with Gada.Core.Defer;")
	}
	if e.needsCorePanic {
		e.println("with Gada.Core.Panic;")
	}
	if e.needsCoreIO || len(e.sliceElemOrder) > 0 || len(e.mapPairOrder) > 0 ||
		e.needsCoreDefer || e.needsCorePanic {
		e.println("")
	}
	if e.pkgName == "main" {
		e.emitMainProcedure()
	} else {
		e.emitPackageBody()
	}
	return e.err
}

// emitSliceInstantiations writes one `package Slices_Of_<T> is new
// Gada.Core.Slices (Element_Type => <T>);` line per distinct element
// type collected in collectSliceElems. The element-name keys are
// already the elemBaseName output (recordSliceElem keys them), so no
// re-derivation is needed here. Caller owns indent depth; output is
// unconditional once sliceElemOrder is non-empty. The
// Element_Is_Atomic formal stays at its default of False — Phase 2
// is correctness-first; the atomic-allocator optimisation flips on
// when type-info plumbing in a later phase can prove element types
// are pointer-free.
func (e *emitter) emitSliceInstantiations() {
	for _, k := range e.sliceElemOrder {
		e.println("package Slices_Of_" + k +
			" is new Gada.Core.Slices (Element_Type => " + k + ");")
	}
}

// emitMapInstantiations writes one
// `package Maps_Of_<K>_To_<V> is new Gada.Core.Maps (...)` block per
// distinct (K, V) pair collected by the pre-scan. The Hash formal is
// the matching Gada.Core.Hash plug-in; the Default_Value matches
// Go's zero value for V (0 / False / 0.0). The "=" formal binds to
// the predefined operator by default — overridden only when V grows
// to user-defined types in a later phase.
func (e *emitter) emitMapInstantiations() {
	for _, key := range e.mapPairOrder {
		m := e.mapPairs[key]
		kName, vName, hash, def := mapPairAdaParts(m)
		// Multi-line aggregate is the showcase form: one parameter
		// per line, aligned column for the "=>" — reads like the
		// runtime spec it instantiates.
		e.println("package Maps_Of_" + key + " is new Gada.Core.Maps")
		e.println("  (Key_Type      => " + kName + ",")
		e.println("   Value_Type    => " + vName + ",")
		e.println("   Hash          => " + hash + ",")
		e.println("   Default_Value => " + def + ");")
	}
}

// emitPanicInstantiation writes the per-program
// `package Panic_Of_Integer is new Gada.Core.Panic (...)` block.
// Phase 2 fixes the panic payload type at Integer — Go's `panic(v)`
// with a non-int v (string literal, struct, interface{}) waits for
// Phase 4's `Gada.Reflect.Any` shim to land. With Any in place this
// becomes `package Panic_Of_Any is new Gada.Core.Panic (Payload_Type
// => Gada.Reflect.Any, Default => Gada.Reflect.Nil);`.
func (e *emitter) emitPanicInstantiation() {
	e.println("package Panic_Of_Integer is new Gada.Core.Panic")
	e.println("  (Payload_Type => Integer,")
	e.println("   Default      => 0);")
}

// mapPairKey returns the canonical "<KName>_To_<VName>" suffix used
// for the Maps_Of_… package instantiation. Both K and V must be
// supported map-key/value base types (Phase 2 = Integer, Boolean,
// Long_Float). String requires Unbounded_String wrapping and
// SipHash-1-3, both deferred to Phase 4 — `docs/imperfections.md`
// tracks the lift.
func mapPairKey(m *ir.MapType) (string, error) {
	kName, err := mapKeyBaseName(m.Key)
	if err != nil {
		return "", err
	}
	vName, err := mapValueBaseName(m.Value)
	if err != nil {
		return "", err
	}
	return kName + "_To_" + vName, nil
}

// mapPairAdaParts returns (K, V, Hash, Default_Value) Ada strings for
// m's (K, V) pair. Pre-validated: the caller has already accepted
// the pair via recordMapPair, so this only covers the
// Phase-2-supported types.
func mapPairAdaParts(m *ir.MapType) (string, string, string, string) {
	kName, _ := mapKeyBaseName(m.Key)
	vName, _ := mapValueBaseName(m.Value)
	return kName, vName,
		"Gada.Core.Hash.Hash_" + kName,
		mapDefaultLiteral(m.Value)
}

// mapKeyBaseName accepts only types whose hash plug-in already ships
// in Gada.Core.Hash. String keys await Phase 4's SipHash-1-3 plus
// Unbounded_String wrapping.
func mapKeyBaseName(t ir.Type) (string, error) {
	switch t.(type) {
	case *ir.IntType:
		return "Integer", nil
	case *ir.BoolType:
		return "Boolean", nil
	case *ir.Float64Type:
		return "Long_Float", nil
	case *ir.StringType:
		return "", fmt.Errorf("emit: map keys of type string await Phase 4 (SipHash-1-3 + Unbounded_String)")
	}
	return "", fmt.Errorf("emit: unsupported map key type %T", t)
}

// mapValueBaseName accepts the same set as keys: the runtime's
// Value_Type generic formal is `is private` and so must be definite,
// which String is not. Once Unbounded_String wrapping lands the
// restriction lifts to "any definite Ada type".
func mapValueBaseName(t ir.Type) (string, error) {
	switch t.(type) {
	case *ir.IntType:
		return "Integer", nil
	case *ir.BoolType:
		return "Boolean", nil
	case *ir.Float64Type:
		return "Long_Float", nil
	case *ir.StringType:
		return "", fmt.Errorf("emit: map values of type string await Phase 4 (Unbounded_String wrapping)")
	}
	return "", fmt.Errorf("emit: unsupported map value type %T", t)
}

// mapDefaultLiteral returns the Ada literal for Go's zero value of
// V. Used as the runtime generic's Default_Value formal so a `Get`
// on an absent key returns the matching zero (Go semantics).
func mapDefaultLiteral(v ir.Type) string {
	switch v.(type) {
	case *ir.IntType:
		return "0"
	case *ir.BoolType:
		return "False"
	case *ir.Float64Type:
		return "0.0"
	}
	// recordMapPair has already filtered unsupported value types via
	// mapValueBaseName, so this is unreachable on a well-formed run.
	return "0"
}

// mapPkgFor returns the "Maps_Of_K_To_V" prefix for a known map
// type. The MapType has already been validated by mapPairKey at
// pre-scan time, so any error here would indicate a programming
// bug — bubble it back so the test surface flags it.
func mapPkgFor(m *ir.MapType) (string, error) {
	key, err := mapPairKey(m)
	if err != nil {
		return "", err
	}
	return "Maps_Of_" + key, nil
}

// elemBaseName maps a slice-element IR type to its Ada base name —
// the suffix used by the per-element-type instantiation
// `Slices_Of_<base> is new Gada.Core.Slices (...)`.
//
// Phase 2 supports only the four basic element types. Slice-of-slice
// (`[][]T`) is rejected here because the emitter would need to
// dependency-order multiple instantiations (`Slices_Of_Integer`
// before `Slices_Of_Slices_Of_Integer`) and Phase 2's golden corpus
// does not exercise that shape; the rejection surfaces a clean
// error instead of letting a dotted Ada package name (which is
// illegal as an identifier) leak into emitted source. Map / struct
// / named-type elements lift in their own phase items.
func elemBaseName(t ir.Type) (string, error) {
	switch t.(type) {
	case *ir.IntType:
		return "Integer", nil
	case *ir.StringType:
		return "String", nil
	case *ir.BoolType:
		return "Boolean", nil
	case *ir.Float64Type:
		return "Long_Float", nil
	}
	return "", fmt.Errorf("emit: unsupported slice element type %T", t)
}

// slicePkgFor returns the Slices_Of_<T> instantiation prefix for a
// slice whose element type is elem (e.g. *ir.IntType → "Slices_Of_Integer").
// Used by every slice-dispatching emit site (SliceLit / IndexExpr /
// SliceExpr / append / len / cap).
func slicePkgFor(elem ir.Type) (string, error) {
	t, err := elemBaseName(elem)
	if err != nil {
		return "", err
	}
	return "Slices_Of_" + t, nil
}

// println writes a single line, prefixed with the current indent
// (three spaces per level — matches the runtime style). An empty
// string emits a bare newline with no indentation, used for the
// blank lines that separate sections.
func (e *emitter) println(s string) {
	if s == "" {
		e.buf.WriteByte('\n')
		return
	}
	for i := 0; i < e.indent; i++ {
		e.buf.WriteString("   ")
	}
	e.buf.WriteString(s)
	e.buf.WriteByte('\n')
}

func (e *emitter) fail(err error) {
	if e.err == nil {
		e.err = err
	}
}

// findMain returns the file's `func main()` (no params, no results)
// if any; otherwise nil. Only useful when pkgName == "main".
func (e *emitter) findMain() *ir.Function {
	for _, d := range e.file.Decls {
		fn, ok := d.(*ir.Function)
		if !ok {
			continue
		}
		if fn.Name == "main" && len(fn.Params) == 0 && len(fn.Results) == 0 {
			return fn
		}
	}
	return nil
}

// emitMainProcedure handles every Go `package main` file: it produces
// `procedure Main is <nested-subs + hoisted-decls> begin <main-body>
// end Main;`. With no nested subprograms and no hoisted declarations
// the layout collapses to the tight `procedure Main is begin ... end
// Main;` form.
func (e *emitter) emitMainProcedure() {
	main := e.findMain()
	var others []*ir.Function
	for _, d := range e.file.Decls {
		fn, ok := d.(*ir.Function)
		if !ok {
			e.fail(fmt.Errorf("emit: top-level %T not supported in Phase 1", d))
			return
		}
		if fn != main {
			others = append(others, fn)
		}
	}

	var mainDecls []*ir.Assign
	var mainBody []ir.Stmt
	if main != nil {
		mainDecls, mainBody = splitDecls(main.Body)
	}

	hasSlices := len(e.sliceElemOrder) > 0
	hasMaps := len(e.mapPairOrder) > 0
	hasPanic := e.needsCorePanic
	hasDeclSection := hasSlices || hasMaps || hasPanic || len(others) > 0 || len(mainDecls) > 0

	e.println("procedure Main is")
	if hasDeclSection {
		e.println("")
	}

	e.indent++
	if hasSlices {
		e.emitSliceInstantiations()
	}
	if hasSlices && hasMaps {
		e.println("")
	}
	if hasMaps {
		e.emitMapInstantiations()
	}
	if (hasSlices || hasMaps) && hasPanic {
		e.println("")
	}
	if hasPanic {
		e.emitPanicInstantiation()
	}
	if (hasSlices || hasMaps || hasPanic) && (len(others) > 0 || len(mainDecls) > 0) {
		e.println("")
	}
	for i, fn := range others {
		if i > 0 {
			e.println("")
		}
		e.emitSubprogram(fn)
	}
	if len(others) > 0 && len(mainDecls) > 0 {
		e.println("")
	}
	if main != nil {
		e.populateLocals(main)
	}
	for _, a := range mainDecls {
		e.emitVarDecl(a)
	}
	e.indent--

	if hasDeclSection {
		e.println("")
	}

	e.println("begin")
	e.indent++
	if len(mainBody) == 0 {
		e.println("null;")
	} else {
		for _, s := range mainBody {
			e.emitStmt(s)
		}
	}
	e.indent--
	e.println("end Main;")
}

// emitPackageBody handles non-main packages: emits `package body P
// is ... end P;` with one sibling subprogram per top-level Go func.
func (e *emitter) emitPackageBody() {
	pkg := adaIdent(e.pkgName)

	var fns []*ir.Function
	for _, d := range e.file.Decls {
		fn, ok := d.(*ir.Function)
		if !ok {
			e.fail(fmt.Errorf("emit: top-level %T not supported in Phase 1", d))
			return
		}
		fns = append(fns, fn)
	}

	hasSlices := len(e.sliceElemOrder) > 0
	hasMaps := len(e.mapPairOrder) > 0
	hasPanic := e.needsCorePanic

	e.println("package body " + pkg + " is")
	if hasSlices || hasMaps || hasPanic || len(fns) > 0 {
		e.println("")
	}

	e.indent++
	if hasSlices {
		e.emitSliceInstantiations()
	}
	if hasSlices && hasMaps {
		e.println("")
	}
	if hasMaps {
		e.emitMapInstantiations()
	}
	if (hasSlices || hasMaps) && hasPanic {
		e.println("")
	}
	if hasPanic {
		e.emitPanicInstantiation()
	}
	if (hasSlices || hasMaps || hasPanic) && len(fns) > 0 {
		e.println("")
	}
	for i, fn := range fns {
		if i > 0 {
			e.println("")
		}
		e.emitSubprogram(fn)
	}
	e.indent--

	if hasSlices || hasMaps || len(fns) > 0 {
		e.println("")
	}
	e.println("end " + pkg + ";")
}

// populateLocals walks fn's signature and the leading run of `:=`
// declarations to populate e.localTypes for the subprogram's scope.
// It is called once per subprogram before any body-stmt emit so
// IndexExpr / SliceExpr / slice-typed BuiltinCall emit sites can
// resolve their dispatch by looking up an Ident's declared type.
func (e *emitter) populateLocals(fn *ir.Function) {
	e.localTypes = map[string]ir.Type{}
	for _, p := range fn.Params {
		if p.Name != "" && p.Type != nil {
			e.localTypes[p.Name] = p.Type
		}
	}
	for _, s := range fn.Body {
		a, ok := s.(*ir.Assign)
		if !ok || !a.Define {
			break
		}
		if len(a.LHS) != 1 || len(a.RHS) != 1 {
			continue
		}
		id, ok := a.LHS[0].(*ir.Ident)
		if !ok {
			continue
		}
		if t, ok := inferRHSType(a.RHS[0]); ok {
			e.localTypes[id.Name] = t
		}
	}
}

// inferRHSType returns the IR type of a `:=` RHS when it can be
// determined statically without consulting *types.Info. Phase 2
// handles literals (already covered by inferDeclType) and slice
// composite literals (whose element type is on the node). Other
// cases bow out so populateLocals leaves the var off the map and
// downstream emit will fall back to its existing error path.
func inferRHSType(x ir.Expr) (ir.Type, bool) {
	switch x := x.(type) {
	case *ir.Lit:
		switch x.Kind {
		case ir.LitInt:
			return &ir.IntType{}, true
		case ir.LitString:
			return &ir.StringType{}, true
		case ir.LitBool:
			return &ir.BoolType{}, true
		case ir.LitFloat:
			return &ir.Float64Type{}, true
		}
	case *ir.SliceLit:
		return &ir.SliceType{Elem: x.Elem}, true
	case *ir.MapLit:
		return &ir.MapType{Key: x.Key, Value: x.Value}, true
	}
	return nil, false
}

// emitSubprogram writes one function or procedure body, with its
// hoisted declarations and statement body.
//
// Phase 2 lift: defer sites in fn.Body get pulled out and emitted in
// the declarative region as one nested closure procedure plus one
// `Defer_Block (Op => Closure'Access)` per site. Ada finalises the
// declared blocks in reverse-of-declaration order at scope exit
// *including under exception unwind*, so the emit gets Go's LIFO
// `defer`-during-panic semantics with no defer-chain bookkeeping
// at runtime.
//
// If the function calls panic or recover, the body is wrapped in
// `begin … exception when Panicking => …; end;` per ADR-0007's
// per-function panic-recover wrapper contract. The handler re-raises
// iff `Is_Panicking` is still True, matching Go's "if no deferred
// call recovered, the panic propagates" rule.
func (e *emitter) emitSubprogram(fn *ir.Function) {
	if e.err != nil {
		return
	}
	e.populateLocals(fn)
	header, name, ok := e.subpHeader(fn)
	if !ok {
		return
	}
	e.println(header)

	decls, body := splitDecls(fn.Body)
	defers := collectDefers(fn.Body)
	usesPanic := bodyUsesPanicOrRecover(fn.Body)

	e.indent++
	for _, a := range decls {
		e.emitVarDecl(a)
	}
	for i, d := range defers {
		e.emitDeferClosure(i+1, d)
	}
	if len(defers) > 0 {
		// Defer_Block declarations come *after* the closure procedures
		// they reference (Ada's "declare before use" rule applies here
		// even though the access value is taken via 'Access).
		for i := range defers {
			n := i + 1
			e.println(fmt.Sprintf("Defer_%d : Gada.Core.Defer.Defer_Block (Op => Defer_Closure_%d'Access);", n, n))
		}
	}
	e.indent--

	e.println("begin")

	e.indent++
	if usesPanic {
		// One extra level of nesting for the begin/exception block so
		// the handler's `raise` propagates out of the wrapper without
		// dragging the whole function with it on a successful return.
		e.println("begin")
		e.indent++
	}
	// `null;` filler when the body would otherwise emit nothing — Ada
	// requires at least one statement between `begin` and `end`. The
	// emit-stmt path for DeferStmt is silent (defers are hoisted to
	// the declarative region), so a function whose only statements are
	// defers also lands here.
	emittedAny := false
	if len(body) > 0 {
		for _, s := range body {
			if _, isDefer := s.(*ir.DeferStmt); !isDefer {
				emittedAny = true
			}
			e.emitStmt(s)
		}
	}
	if !emittedAny {
		e.println("null;")
	}
	if usesPanic {
		e.indent--
		e.println("exception")
		e.indent++
		e.println("when Panic_Of_Integer.Panicking =>")
		e.indent++
		e.println("if Panic_Of_Integer.Is_Panicking then")
		e.indent++
		e.println("raise;")
		e.indent--
		e.println("end if;")
		// For functions that return a value, the exception path also
		// has to terminate with a return; emit a default return of the
		// result type's zero value. Procedures fall through to `end;`.
		if len(fn.Results) == 1 {
			zero := zeroLiteralOf(fn.Results[0].Type)
			e.println("return " + zero + ";")
		}
		e.indent -= 2
		e.println("end;")
	}
	e.indent--

	e.println("end " + name + ";")
}

// collectDefers returns every DeferStmt under body in source order
// (depth-first; nested defers inside if / for / range bodies are
// hoisted to the enclosing function — Go semantics: defer is bound
// to the *function* scope, not the lexical block).
func collectDefers(body []ir.Stmt) []*ir.DeferStmt {
	var out []*ir.DeferStmt
	var walk func([]ir.Stmt)
	walk = func(ss []ir.Stmt) {
		for _, s := range ss {
			switch s := s.(type) {
			case *ir.DeferStmt:
				out = append(out, s)
			case *ir.If:
				walk(s.Then)
				walk(s.Else)
			case *ir.For:
				walk(s.Body)
			case *ir.RangeStmt:
				walk(s.Body)
			}
		}
	}
	walk(body)
	return out
}

// bodyUsesPanicOrRecover walks body for any panic/recover BuiltinCall.
// Per-function flag drives whether the body needs the per-function
// panic-recover wrapper.
func bodyUsesPanicOrRecover(body []ir.Stmt) bool {
	var found bool
	var walkExpr func(ir.Expr)
	var walkStmt func(ir.Stmt)
	walkExpr = func(x ir.Expr) {
		if found || x == nil {
			return
		}
		switch x := x.(type) {
		case *ir.BuiltinCall:
			if x.Name == "panic" || x.Name == "recover" {
				found = true
				return
			}
			for _, a := range x.Args {
				walkExpr(a)
			}
		case *ir.BinOp:
			walkExpr(x.X)
			walkExpr(x.Y)
		case *ir.UnaryOp:
			walkExpr(x.X)
		case *ir.IndexExpr:
			walkExpr(x.X)
			walkExpr(x.Index)
		case *ir.SliceExpr:
			walkExpr(x.X)
			walkExpr(x.Low)
			walkExpr(x.High)
		case *ir.SliceLit:
			for _, e := range x.Elems {
				walkExpr(e)
			}
		case *ir.MapLit:
			for _, ent := range x.Entries {
				walkExpr(ent.Key)
				walkExpr(ent.Value)
			}
		case *ir.Selector:
			walkExpr(x.X)
		}
	}
	walkStmt = func(s ir.Stmt) {
		if found || s == nil {
			return
		}
		switch s := s.(type) {
		case *ir.BuiltinCall:
			if s.Name == "panic" || s.Name == "recover" {
				found = true
				return
			}
			for _, a := range s.Args {
				walkExpr(a)
			}
		case *ir.Assign:
			for _, x := range s.LHS {
				walkExpr(x)
			}
			for _, x := range s.RHS {
				walkExpr(x)
			}
		case *ir.If:
			walkExpr(s.Cond)
			for _, t := range s.Then {
				walkStmt(t)
			}
			for _, t := range s.Else {
				walkStmt(t)
			}
		case *ir.For:
			walkStmt(s.Init)
			walkExpr(s.Cond)
			walkStmt(s.Post)
			for _, t := range s.Body {
				walkStmt(t)
			}
		case *ir.Return:
			for _, x := range s.Results {
				walkExpr(x)
			}
		case *ir.Call:
			walkExpr(s.Fun)
			for _, x := range s.Args {
				walkExpr(x)
			}
		case *ir.ExprStmt:
			walkExpr(s.X)
		case *ir.RangeStmt:
			walkExpr(s.X)
			for _, t := range s.Body {
				walkStmt(t)
			}
		case *ir.DeferStmt:
			walkStmt(s.Call)
		}
	}
	for _, s := range body {
		walkStmt(s)
		if found {
			return true
		}
	}
	return false
}

// emitDeferClosure writes one nested parameterless procedure that the
// matching Defer_Block's Op formal will call at scope exit. n is the
// 1-based source-order index of the defer site within the enclosing
// function.
func (e *emitter) emitDeferClosure(n int, d *ir.DeferStmt) {
	e.println(fmt.Sprintf("procedure Defer_Closure_%d is", n))
	e.println("begin")
	e.indent++
	switch c := d.Call.(type) {
	case *ir.Call:
		e.emitCallStmt(c)
	case *ir.BuiltinCall:
		e.emitBuiltinStmt(c)
	default:
		e.fail(fmt.Errorf("emit: defer holds unexpected stmt %T", d.Call))
	}
	e.indent--
	e.println(fmt.Sprintf("end Defer_Closure_%d;", n))
}

// zeroLiteralOf returns the Ada literal for the zero value of t. Used
// by the per-function panic-recover wrapper's exception path so a
// value-returning function still terminates with `return`. Mirrors the
// runtime instantiation defaults so a `recover()`-rescued function
// returns the same value its callers would observe on a normal-flow
// short-circuit.
func zeroLiteralOf(t ir.Type) string {
	switch t.(type) {
	case *ir.IntType:
		return "0"
	case *ir.BoolType:
		return "False"
	case *ir.Float64Type:
		return "0.0"
	case *ir.StringType:
		return `""`
	}
	return "0"
}

// subpHeader returns the Ada header line for fn ("function Foo (...)
// return T is" or "procedure Bar (...) is"), the (renamed) Ada
// identifier, and ok=false if any part of the signature is
// unsupported.
func (e *emitter) subpHeader(fn *ir.Function) (string, string, bool) {
	name := adaIdent(fn.Name)

	var params string
	if len(fn.Params) > 0 {
		ps := make([]string, 0, len(fn.Params))
		for _, p := range fn.Params {
			t, err := typeName(p.Type)
			if err != nil {
				e.fail(err)
				return "", name, false
			}
			ps = append(ps, adaIdent(p.Name)+" : "+t)
		}
		params = " (" + strings.Join(ps, "; ") + ")"
	}

	if len(fn.Results) == 0 {
		return "procedure " + name + params + " is", name, true
	}
	if len(fn.Results) > 1 {
		e.fail(fmt.Errorf("emit: multi-value return on %s not supported in Phase 1", fn.Name))
		return "", name, false
	}
	rt, err := typeName(fn.Results[0].Type)
	if err != nil {
		e.fail(err)
		return "", name, false
	}
	return "function " + name + params + " return " + rt + " is", name, true
}

// splitDecls peels the leading run of `Assign{Define:true}` off the
// front of body and returns them separately. Any `:=` later in the
// body falls through to emitAssign and is rejected as a Phase 1
// limitation.
func splitDecls(body []ir.Stmt) ([]*ir.Assign, []ir.Stmt) {
	var decls []*ir.Assign
	i := 0
	for i < len(body) {
		a, ok := body[i].(*ir.Assign)
		if !ok || !a.Define {
			break
		}
		decls = append(decls, a)
		i++
	}
	return decls, body[i:]
}

func (e *emitter) emitVarDecl(a *ir.Assign) {
	if e.err != nil {
		return
	}
	if len(a.LHS) != 1 || len(a.RHS) != 1 {
		e.fail(fmt.Errorf("emit: multi-value := not supported in Phase 1"))
		return
	}
	id, ok := a.LHS[0].(*ir.Ident)
	if !ok {
		e.fail(fmt.Errorf("emit: := lhs must be a plain identifier in Phase 1"))
		return
	}
	typ, err := inferDeclType(a.RHS[0])
	if err != nil {
		e.fail(err)
		return
	}
	rhs := e.emitExpr(a.RHS[0])
	e.println(adaIdent(id.Name) + " : " + typ + " := " + rhs + ";")
}

// inferDeclType maps a `:=` RHS to its Ada type name. Phase 1
// supported literal RHS; Phase 2 also accepts a slice composite
// literal (whose element type is on the node, so no *types.Info
// plumbing is needed). Anything else still defers — full RHS-typing
// arrives with the type-info plumbing in a later phase.
func inferDeclType(x ir.Expr) (string, error) {
	switch x := x.(type) {
	case *ir.Lit:
		switch x.Kind {
		case ir.LitInt:
			return "Integer", nil
		case ir.LitString:
			return "String", nil
		case ir.LitBool:
			return "Boolean", nil
		case ir.LitFloat:
			return "Long_Float", nil
		}
		return "", fmt.Errorf("emit: unknown literal kind %q", x.Kind)
	case *ir.SliceLit:
		pkg, err := slicePkgFor(x.Elem)
		if err != nil {
			return "", err
		}
		return pkg + ".Slice", nil
	case *ir.MapLit:
		pkg, err := mapPkgFor(&ir.MapType{Key: x.Key, Value: x.Value})
		if err != nil {
			return "", err
		}
		return pkg + ".Map", nil
	}
	return "", fmt.Errorf("emit: := requires a literal or composite RHS, got %T", x)
}

// --- statements -----------------------------------------------------------

func (e *emitter) emitStmt(s ir.Stmt) {
	if e.err != nil {
		return
	}
	switch s := s.(type) {
	case *ir.Assign:
		e.emitAssign(s)
	case *ir.If:
		e.emitIf(s)
	case *ir.For:
		e.emitFor(s)
	case *ir.Return:
		e.emitReturn(s)
	case *ir.Call:
		e.emitCallStmt(s)
	case *ir.ExprStmt:
		e.emitExprStmt(s)
	case *ir.BuiltinCall:
		e.emitBuiltinStmt(s)
	case *ir.RangeStmt:
		e.emitRangeStmt(s)
	case *ir.DeferStmt:
		// Hoisted to the declarative region by emitSubprogram (one
		// closure + one Defer_Block per site, declared in source
		// order). The body walk reaches here only if a DeferStmt is
		// encountered outside the head of a function body — which
		// emitSubprogram should have already collected. Skip silently.
	default:
		e.fail(fmt.Errorf("emit: unsupported stmt %T", s))
	}
}

// emitBuiltinStmt handles statement-position BuiltinCalls. The only
// stmt-position cases Phase 2 emits are `delete(m, k)` (side-effecting
// map mutation) and `panic(x)` (deferred to Item 8). Anything else
// falls through to the expression dispatch followed by a semicolon.
func (e *emitter) emitBuiltinStmt(b *ir.BuiltinCall) {
	switch b.Name {
	case "delete":
		expr := e.emitMapBuiltin(b)
		if expr == "" {
			return
		}
		e.println(expr + ";")
	case "panic":
		if len(b.Args) != 1 {
			e.fail(fmt.Errorf("emit: panic takes exactly 1 arg, got %d", len(b.Args)))
			return
		}
		v := e.emitExpr(b.Args[0])
		e.println("Panic_Of_Integer.Do_Panic (" + v + ");")
	default:
		e.fail(fmt.Errorf("emit: builtin %q at statement position not supported in Phase 2", b.Name))
	}
}

func (e *emitter) emitAssign(a *ir.Assign) {
	if a.Define {
		e.fail(fmt.Errorf("emit: := outside head of function body not supported in Phase 1"))
		return
	}
	if len(a.LHS) != 1 || len(a.RHS) != 1 {
		e.fail(fmt.Errorf("emit: multi-value assignment not supported in Phase 1"))
		return
	}
	// Special case: `m[k] = v` on a map type lowers to a runtime
	// `Insert (M, K, V)` call rather than a `:=` assignment to a
	// non-existent l-value. The map's `Get` always returns by-value;
	// you can't assign to it.
	if ix, ok := a.LHS[0].(*ir.IndexExpr); ok {
		if pkg, ok := e.mapPkgForExpr(ix.X); ok {
			m := e.emitExpr(ix.X)
			k := e.emitExpr(ix.Index)
			v := e.emitExpr(a.RHS[0])
			e.println(pkg + ".Insert (" + m + ", " + k + ", " + v + ");")
			return
		}
	}
	lhs := e.emitExpr(a.LHS[0])
	rhs := e.emitExpr(a.RHS[0])
	e.println(lhs + " := " + rhs + ";")
}

func (e *emitter) emitIf(s *ir.If) {
	cond := e.emitExpr(s.Cond)
	e.println("if " + cond + " then")
	e.indent++
	for _, t := range s.Then {
		e.emitStmt(t)
	}
	e.indent--
	e.emitElseChain(s.Else)
}

// emitElseChain handles the `else` / `elsif` cascade. A single
// nested *ir.If becomes `elsif`; everything else becomes a plain
// `else` block. The recursion folds chains of `else if` statements
// into a single Ada if/elsif/else/end-if construct.
func (e *emitter) emitElseChain(els []ir.Stmt) {
	if len(els) == 0 {
		e.println("end if;")
		return
	}
	if len(els) == 1 {
		if nested, ok := els[0].(*ir.If); ok {
			e.println("elsif " + e.emitExpr(nested.Cond) + " then")
			e.indent++
			for _, t := range nested.Then {
				e.emitStmt(t)
			}
			e.indent--
			e.emitElseChain(nested.Else)
			return
		}
	}
	e.println("else")
	e.indent++
	for _, s := range els {
		e.emitStmt(s)
	}
	e.indent--
	e.println("end if;")
}

func (e *emitter) emitReturn(r *ir.Return) {
	if len(r.Results) == 0 {
		e.println("return;")
		return
	}
	if len(r.Results) > 1 {
		e.fail(fmt.Errorf("emit: multi-value return not supported in Phase 1"))
		return
	}
	e.println("return " + e.emitExpr(r.Results[0]) + ";")
}

func (e *emitter) emitFor(f *ir.For) {
	// Bare `for { ... }`.
	if f.Init == nil && f.Cond == nil && f.Post == nil {
		e.println("loop")
		e.indent++
		if len(f.Body) == 0 {
			e.println("null;")
		} else {
			for _, s := range f.Body {
				e.emitStmt(s)
			}
		}
		e.indent--
		e.println("end loop;")
		return
	}
	// Trivial integer for: `for V := S; V < E; V = V + 1 { ... }`.
	if v, start, end, ok := matchTrivialFor(f); ok {
		header := "for " + adaIdent(v) +
			" in " + e.emitExpr(start) +
			" .. " + e.emitBinOperand(end) +
			" - 1 loop"
		e.println(header)
		e.indent++
		if len(f.Body) == 0 {
			e.println("null;")
		} else {
			for _, s := range f.Body {
				e.emitStmt(s)
			}
		}
		e.indent--
		e.println("end loop;")
		return
	}
	e.fail(fmt.Errorf("emit: only trivial integer for-loops and bare for {} are supported in Phase 1"))
}

// emitRangeStmt lowers `for k, v := range m` over a map to the
// runtime cursor protocol:
//
//	declare
//	   C : Maps_Of_<K>_To_<V>.Cursor := Maps_Of_<K>_To_<V>.First (M);
//	begin
//	   while Maps_Of_<K>_To_<V>.Has_Element (M, C) loop
//	      declare
//	         <k> : <K> := Maps_Of_<K>_To_<V>.Key   (M, C);
//	         <v> : <V> := Maps_Of_<K>_To_<V>.Value (M, C);
//	      begin
//	         <body>;
//	      end;
//	      C := Maps_Of_<K>_To_<V>.Next (M, C);
//	   end loop;
//	end;
//
// The outer declare scopes the cursor; the inner declare scopes the
// rebound k/v so the loop body sees fresh bindings each iteration
// (matching Go's `for k, v := range` rebind semantics). When KeyName
// or ValueName is empty (Go's blank identifier or absent), the
// corresponding inner decl is omitted.
//
// Range over slices is *not* yet supported — Phase 2 only lifts the
// map shape because the slice path needs distinct integer-index
// machinery. Range-over-int (`for i := range n`) and range-over-
// channel arrive in their respective phases.
func (e *emitter) emitRangeStmt(s *ir.RangeStmt) {
	pkg, ok := e.mapPkgForExpr(s.X)
	if !ok {
		e.fail(fmt.Errorf("emit: range supports only map values in Phase 2 (got non-Ident or non-map type)"))
		return
	}
	m := e.emitExpr(s.X)

	mt, ok := e.localTypes[s.X.(*ir.Ident).Name].(*ir.MapType)
	if !ok {
		// Should be impossible if mapPkgForExpr returned true, but
		// guard anyway so a future refactor doesn't strand a nil deref.
		e.fail(fmt.Errorf("emit: internal — range X resolved to non-MapType"))
		return
	}
	kAdaName, _ := mapKeyBaseName(mt.Key)
	vAdaName, _ := mapValueBaseName(mt.Value)

	e.rangeCounter++
	cur := fmt.Sprintf("Cursor_%d", e.rangeCounter)

	// Register the loop-bound names in localTypes so any nested
	// reference to k/v (e.g. `_ = k`, `total + v`) types correctly
	// for downstream dispatch.
	if s.KeyName != "" {
		e.localTypes[s.KeyName] = mt.Key
	}
	if s.ValueName != "" {
		e.localTypes[s.ValueName] = mt.Value
	}

	e.println("declare")
	e.indent++
	e.println(cur + " : " + pkg + ".Cursor := " + pkg + ".First (" + m + ");")
	e.indent--
	e.println("begin")
	e.indent++
	e.println("while " + pkg + ".Has_Element (" + m + ", " + cur + ") loop")
	e.indent++
	hasInnerDecls := s.KeyName != "" || s.ValueName != ""
	if hasInnerDecls {
		e.println("declare")
		e.indent++
		if s.KeyName != "" {
			e.println(adaIdent(s.KeyName) + " : constant " + kAdaName +
				" := " + pkg + ".Key (" + m + ", " + cur + ");")
		}
		if s.ValueName != "" {
			e.println(adaIdent(s.ValueName) + " : constant " + vAdaName +
				" := " + pkg + ".Value (" + m + ", " + cur + ");")
		}
		e.indent--
		e.println("begin")
		e.indent++
	}
	if len(s.Body) == 0 {
		e.println("null;")
	} else {
		for _, st := range s.Body {
			e.emitStmt(st)
		}
	}
	if hasInnerDecls {
		e.indent--
		e.println("end;")
	}
	e.println(cur + " := " + pkg + ".Next (" + m + ", " + cur + ");")
	e.indent--
	e.println("end loop;")
	e.indent--
	e.println("end;")
}

// matchTrivialFor recognises the `for V := <start>; V < <end>; V = V
// + 1 { ... }` shape and returns its components. Anything else
// returns ok=false so the caller can fall back to an error.
func matchTrivialFor(f *ir.For) (string, ir.Expr, ir.Expr, bool) {
	initA, ok := f.Init.(*ir.Assign)
	if !ok || !initA.Define || len(initA.LHS) != 1 || len(initA.RHS) != 1 {
		return "", nil, nil, false
	}
	initIdent, ok := initA.LHS[0].(*ir.Ident)
	if !ok {
		return "", nil, nil, false
	}
	v := initIdent.Name

	cond, ok := f.Cond.(*ir.BinOp)
	if !ok || cond.Op != "<" {
		return "", nil, nil, false
	}
	condIdent, ok := cond.X.(*ir.Ident)
	if !ok || condIdent.Name != v {
		return "", nil, nil, false
	}

	postA, ok := f.Post.(*ir.Assign)
	if !ok || postA.Define || len(postA.LHS) != 1 || len(postA.RHS) != 1 {
		return "", nil, nil, false
	}
	postIdent, ok := postA.LHS[0].(*ir.Ident)
	if !ok || postIdent.Name != v {
		return "", nil, nil, false
	}
	postBin, ok := postA.RHS[0].(*ir.BinOp)
	if !ok || postBin.Op != "+" {
		return "", nil, nil, false
	}
	postX, _ := postBin.X.(*ir.Ident)
	postY, _ := postBin.Y.(*ir.Lit)
	if postX == nil || postX.Name != v || postY == nil ||
		postY.Kind != ir.LitInt || postY.Value != "1" {
		return "", nil, nil, false
	}
	return v, initA.RHS[0], cond.Y, true
}

func (e *emitter) emitCallStmt(c *ir.Call) {
	fun := e.emitExpr(c.Fun)
	args := make([]string, 0, len(c.Args))
	for _, a := range c.Args {
		args = append(args, e.emitExpr(a))
	}
	if len(args) == 0 {
		e.println(fun + ";")
		return
	}
	e.println(fun + " (" + strings.Join(args, ", ") + ");")
}

// emitExprStmt renders Go's bare expression-statement (e.g. a stray
// `-x` line) as Ada `null;`. Ada does not allow expression-position
// statements, and Go's `gc` would reject these too — but the corpus
// includes one to exercise the IR path, so we accept it lossily.
func (e *emitter) emitExprStmt(s *ir.ExprStmt) {
	_ = s
	e.println("null;")
}

// --- expressions ----------------------------------------------------------

func (e *emitter) emitExpr(x ir.Expr) string {
	if e.err != nil {
		return ""
	}
	switch x := x.(type) {
	case *ir.Ident:
		return adaIdent(x.Name)
	case *ir.Lit:
		return e.emitLit(x)
	case *ir.BinOp:
		return e.emitBinOp(x)
	case *ir.UnaryOp:
		return e.emitUnaryOp(x)
	case *ir.Selector:
		return e.emitSelector(x)
	case *ir.SliceLit:
		return e.emitSliceLit(x)
	case *ir.MapLit:
		return e.emitMapLit(x)
	case *ir.IndexExpr:
		return e.emitIndexExpr(x)
	case *ir.SliceExpr:
		return e.emitSliceExpr(x)
	case *ir.BuiltinCall:
		return e.emitBuiltinCall(x)
	}
	e.fail(fmt.Errorf("emit: unsupported expr %T", x))
	return ""
}

// emitSliceLit dispatches `[]T{e1, e2, …}` to
// `Slices_Of_<T>.From_Array ([e1, e2, …])` (or `.Empty` if Elems is
// empty — the runtime exposes a zero-cap singleton).
func (e *emitter) emitSliceLit(s *ir.SliceLit) string {
	pkg, err := slicePkgFor(s.Elem)
	if err != nil {
		e.fail(err)
		return ""
	}
	if len(s.Elems) == 0 {
		return pkg + ".Empty"
	}
	parts := make([]string, 0, len(s.Elems))
	for _, el := range s.Elems {
		parts = append(parts, e.emitExpr(el))
	}
	return pkg + ".From_Array ([" + strings.Join(parts, ", ") + "])"
}

// emitIndexExpr dispatches `s[i]` (slice) to
// `Slices_Of_<T>.Element (S, I + 1)` and `m[k]` (map) to
// `Maps_Of_<K>_To_<V>.Get (M, K)`. The slice path translates Go's
// 0-based index to Ada's 1-based via a `+ 1` that GNAT folds to a
// literal at -O2 for constants. The map path is index-equivalent —
// no offset — and returns Default_Value if K is absent (Go zero-
// value semantics).
func (e *emitter) emitIndexExpr(ix *ir.IndexExpr) string {
	if pkg, ok := e.slicePkgForExpr(ix.X); ok {
		x := e.emitExpr(ix.X)
		idx := e.emitExpr(ix.Index)
		return pkg + ".Element (" + x + ", " + idx + " + 1)"
	}
	if pkg, ok := e.mapPkgForExpr(ix.X); ok {
		x := e.emitExpr(ix.X)
		idx := e.emitExpr(ix.Index)
		return pkg + ".Get (" + x + ", " + idx + ")"
	}
	e.fail(fmt.Errorf("emit: cannot determine slice/map instantiation for index expr (Phase 2 supports only Ident-of-known-slice-or-map-type)"))
	return ""
}

// emitMapLit dispatches `map[K]V{k1: v1, k2: v2}` to
// `Maps_Of_<K>_To_<V>.From_Pairs ([(K => k1, V => v1), ...])` and
// the empty-literal form `map[K]V{}` to `Maps_Of_<K>_To_<V>.Make_Map`.
// Make_Map keeps capacity at 0 (deferred allocation) so an empty map
// stays heap-clean until a first insert; From_Pairs pre-sizes to
// Items'Length, saving rehashes on bulk init.
func (e *emitter) emitMapLit(m *ir.MapLit) string {
	pkg, err := mapPkgFor(&ir.MapType{Key: m.Key, Value: m.Value})
	if err != nil {
		e.fail(err)
		return ""
	}
	if len(m.Entries) == 0 {
		return pkg + ".Make_Map"
	}
	parts := make([]string, 0, len(m.Entries))
	for _, ent := range m.Entries {
		parts = append(parts,
			"(K => "+e.emitExpr(ent.Key)+", V => "+e.emitExpr(ent.Value)+")")
	}
	return pkg + ".From_Pairs ([" + strings.Join(parts, ", ") + "])"
}

// emitSliceExpr dispatches `s[lo:hi]` (and the elided forms) to
// `Slices_Of_<T>.Slice_Of (S, Low + 1, High + 1)`. Missing Low →
// constant 1; missing High → `Slices_Of_<T>.Len (S) + 1` (the
// "one past end" sentinel the runtime accepts).
func (e *emitter) emitSliceExpr(s *ir.SliceExpr) string {
	pkg, ok := e.slicePkgForExpr(s.X)
	if !ok {
		e.fail(fmt.Errorf("emit: cannot determine slice instantiation for slice expr (Phase 2 supports only Ident-of-known-slice-type)"))
		return ""
	}
	x := e.emitExpr(s.X)
	var lo, hi string
	if s.Low != nil {
		lo = e.emitExpr(s.Low) + " + 1"
	} else {
		lo = "1"
	}
	if s.High != nil {
		hi = e.emitExpr(s.High) + " + 1"
	} else {
		hi = pkg + ".Len (" + x + ") + 1"
	}
	return pkg + ".Slice_Of (" + x + ", " + lo + ", " + hi + ")"
}

// emitBuiltinCall dispatches the closed Phase 2 set of Go predeclared
// functions to their Slices_Of_<T> / Maps_Of_<K>_To_<V> equivalents.
// `len` is polymorphic between slice and map; the dispatch peeks at
// the first arg's resolved type to decide.
func (e *emitter) emitBuiltinCall(b *ir.BuiltinCall) string {
	switch b.Name {
	case "append", "cap":
		return e.emitSliceBuiltin(b)
	case "len":
		if len(b.Args) == 1 {
			if _, ok := e.mapPkgForExpr(b.Args[0]); ok {
				return e.emitMapBuiltin(b)
			}
		}
		return e.emitSliceBuiltin(b)
	case "delete":
		return e.emitMapBuiltin(b)
	case "recover":
		if len(b.Args) != 0 {
			e.fail(fmt.Errorf("emit: recover takes no args, got %d", len(b.Args)))
			return ""
		}
		return "Panic_Of_Integer.Recover"
	case "panic":
		// panic in expression position is rare in Go (e.g. inside a `||`
		// for short-circuit termination) and Phase 2 does not support
		// it. Phase 4's Any-payload lift will reconsider.
		e.fail(fmt.Errorf("emit: panic in expression position not supported in Phase 2"))
		return ""
	}
	e.fail(fmt.Errorf("emit: builtin %q not supported in Phase 2", b.Name))
	return ""
}

// emitMapBuiltin dispatches `len(m)` and `delete(m, k)`. `delete`
// also has a statement-position emit path in emitMapBuiltinStmt so
// the side-effecting semicolon-terminated form lands correctly when
// it appears inside a statement context (the IR carries it as a
// stmt-position BuiltinCall).
func (e *emitter) emitMapBuiltin(b *ir.BuiltinCall) string {
	if len(b.Args) < 1 {
		e.fail(fmt.Errorf("emit: builtin %q requires at least 1 arg", b.Name))
		return ""
	}
	pkg, ok := e.mapPkgForExpr(b.Args[0])
	if !ok {
		e.fail(fmt.Errorf("emit: cannot determine map instantiation for %q (Phase 2 supports only Ident-of-known-map-type as the first arg)", b.Name))
		return ""
	}
	switch b.Name {
	case "len":
		// emitBuiltinCall guarantees arity==1 before routing here, so
		// no second arity check is needed.
		return pkg + ".Length (" + e.emitExpr(b.Args[0]) + ")"
	case "delete":
		if len(b.Args) != 2 {
			e.fail(fmt.Errorf("emit: delete takes exactly 2 args, got %d", len(b.Args)))
			return ""
		}
		// Expression-position rendering. Statement position calls
		// emitBuiltinStmt above, which adds the semicolon.
		return pkg + ".Delete (" + e.emitExpr(b.Args[0]) + ", " + e.emitExpr(b.Args[1]) + ")"
	}
	// Unreachable: emitBuiltinCall only routes "len" or "delete" here.
	// If a future caller widens the dispatch, the missing case shows up
	// here as an explicit failure rather than silent miscoding.
	e.fail(fmt.Errorf("emit: internal — emitMapBuiltin called with %q", b.Name))
	return ""
}

func (e *emitter) emitSliceBuiltin(b *ir.BuiltinCall) string {
	if len(b.Args) < 1 {
		e.fail(fmt.Errorf("emit: builtin %q requires at least 1 arg", b.Name))
		return ""
	}
	pkg, ok := e.slicePkgForExpr(b.Args[0])
	if !ok {
		e.fail(fmt.Errorf("emit: cannot determine slice instantiation for %q (Phase 2 supports only Ident-of-known-slice-type as the first arg)", b.Name))
		return ""
	}
	switch b.Name {
	case "len":
		if len(b.Args) != 1 {
			e.fail(fmt.Errorf("emit: len takes exactly 1 arg, got %d", len(b.Args)))
			return ""
		}
		return pkg + ".Len (" + e.emitExpr(b.Args[0]) + ")"
	case "cap":
		if len(b.Args) != 1 {
			e.fail(fmt.Errorf("emit: cap takes exactly 1 arg, got %d", len(b.Args)))
			return ""
		}
		return pkg + ".Cap (" + e.emitExpr(b.Args[0]) + ")"
	case "append":
		if len(b.Args) != 2 {
			e.fail(fmt.Errorf("emit: append-of-N values not supported in Phase 2 (got %d args)", len(b.Args)))
			return ""
		}
		return pkg + ".Append (" + e.emitExpr(b.Args[0]) + ", " + e.emitExpr(b.Args[1]) + ")"
	}
	e.fail(fmt.Errorf("emit: internal — emitSliceBuiltin called with %q", b.Name))
	return ""
}

// slicePkgForExpr returns the Slices_Of_<T> prefix for x when x is
// known to evaluate to a slice; ok=false otherwise. Phase 2 resolves
// only bare identifiers (looked up in localTypes); other expression
// shapes need *types.Info plumbing that lands in a later phase.
func (e *emitter) slicePkgForExpr(x ir.Expr) (string, bool) {
	id, ok := x.(*ir.Ident)
	if !ok {
		return "", false
	}
	t, ok := e.localTypes[id.Name]
	if !ok {
		return "", false
	}
	st, ok := t.(*ir.SliceType)
	if !ok {
		return "", false
	}
	pkg, err := slicePkgFor(st.Elem)
	if err != nil {
		return "", false
	}
	return pkg, true
}

// mapPkgForExpr returns the Maps_Of_<K>_To_<V> prefix for x when x
// is known to evaluate to a map; ok=false otherwise. Same constraint
// as slicePkgForExpr: bare-ident-only resolution until type-info
// plumbing arrives.
func (e *emitter) mapPkgForExpr(x ir.Expr) (string, bool) {
	id, ok := x.(*ir.Ident)
	if !ok {
		return "", false
	}
	t, ok := e.localTypes[id.Name]
	if !ok {
		return "", false
	}
	mt, ok := t.(*ir.MapType)
	if !ok {
		return "", false
	}
	pkg, err := mapPkgFor(mt)
	if err != nil {
		return "", false
	}
	return pkg, true
}

func (e *emitter) emitLit(l *ir.Lit) string {
	switch l.Kind {
	case ir.LitInt, ir.LitFloat:
		return l.Value
	case ir.LitBool:
		if l.Value == "true" {
			return "True"
		}
		return "False"
	case ir.LitString:
		unq, err := strconv.Unquote(l.Value)
		if err != nil {
			e.fail(fmt.Errorf("emit: bad string literal %s: %w", l.Value, err))
			return l.Value
		}
		for _, r := range unq {
			if r < 0x20 || r == 0x7F {
				e.fail(fmt.Errorf("emit: control characters in string literals are not supported in Phase 1"))
				return l.Value
			}
		}
		return `"` + strings.ReplaceAll(unq, `"`, `""`) + `"`
	}
	e.fail(fmt.Errorf("emit: unknown literal kind %q", l.Kind))
	return l.Value
}

func (e *emitter) emitBinOp(b *ir.BinOp) string {
	op := translateBinOp(b.Op)
	if op == "" {
		e.fail(fmt.Errorf("emit: unsupported binary op %q", b.Op))
		return ""
	}
	return e.emitBinOperand(b.X) + " " + op + " " + e.emitBinOperand(b.Y)
}

// emitBinOperand emits a sub-expression of a BinOp, parenthesising
// it if it is itself a BinOp. This re-imposes the parentheses the
// translator stripped via *ast.ParenExpr; it is conservative but
// always-correct for Phase 1 precedence.
func (e *emitter) emitBinOperand(x ir.Expr) string {
	s := e.emitExpr(x)
	if _, ok := x.(*ir.BinOp); ok {
		return "(" + s + ")"
	}
	return s
}

func translateBinOp(goOp string) string {
	switch goOp {
	case "+", "-", "*", "/", "<", ">", "<=", ">=":
		return goOp
	case "==":
		return "="
	case "!=":
		return "/="
	case "&&":
		return "and"
	case "||":
		return "or"
	case "%":
		return "mod"
	}
	return ""
}

func (e *emitter) emitUnaryOp(u *ir.UnaryOp) string {
	s := e.emitExpr(u.X)
	if _, ok := u.X.(*ir.BinOp); ok {
		s = "(" + s + ")"
	}
	switch u.Op {
	case "-":
		return "-" + s
	case "+":
		return "+" + s
	case "!":
		return "not " + s
	}
	e.fail(fmt.Errorf("emit: unsupported unary op %q", u.Op))
	return s
}

// emitSelector special-cases `fmt.Println` (the only stdlib symbol
// the Phase 1 corpus uses). Every other selector falls through to a
// dotted Ada reference; that path is exercised in error tests but
// won't produce compilable Ada until later phases plumb proper
// package translation.
func (e *emitter) emitSelector(s *ir.Selector) string {
	if id, ok := s.X.(*ir.Ident); ok && id.Name == "fmt" && s.Sel == "Println" {
		return "Println"
	}
	return e.emitExpr(s.X) + "." + s.Sel
}

// --- identifiers ----------------------------------------------------------

// adaIdent capitalises the first rune of a Go identifier and appends
// `_K` if its lowercase form collides with an Ada reserved word.
// Unlike a trailing underscore (which Ada disallows in identifiers),
// `_K` is always a valid identifier suffix.
func adaIdent(s string) string {
	caps := capitalize(s)
	if isAdaReserved(s) {
		return caps + "_K"
	}
	return caps
}

func capitalize(s string) string {
	if s == "" {
		return s
	}
	r := []rune(s)
	if r[0] >= 'a' && r[0] <= 'z' {
		r[0] = r[0] - 'a' + 'A'
	}
	return string(r)
}

// isAdaReserved tests s (lowercased) against the Ada 2022 reserved
// word list. The list is the union of Ada 83/95/2005/2012/2022
// reserved words.
func isAdaReserved(s string) bool {
	switch strings.ToLower(s) {
	case "abort", "abs", "abstract", "accept", "access", "aliased", "all",
		"and", "array", "at", "begin", "body", "case", "constant", "declare",
		"delay", "delta", "digits", "do", "else", "elsif", "end", "entry",
		"exception", "exit", "for", "function", "generic", "goto", "if",
		"in", "interface", "is", "limited", "loop", "mod", "new", "not",
		"null", "of", "or", "others", "out", "overriding", "package",
		"parallel", "pragma", "private", "procedure", "protected", "raise",
		"range", "record", "rem", "renames", "requeue", "return", "reverse",
		"select", "separate", "some", "subtype", "synchronized", "tagged",
		"task", "terminate", "then", "type", "until", "use", "when", "while",
		"with", "xor":
		return true
	}
	return false
}

// typeName maps an IR type to its Ada surface form. Phase 1's four
// basic types are unchanged; Phase 2 adds *ir.SliceType which lowers
// to the corresponding `Slices_Of_<T>.Slice` instantiation alias.
func typeName(t ir.Type) (string, error) {
	switch t := t.(type) {
	case *ir.IntType:
		return "Integer", nil
	case *ir.StringType:
		return "String", nil
	case *ir.BoolType:
		return "Boolean", nil
	case *ir.Float64Type:
		return "Long_Float", nil
	case *ir.SliceType:
		pkg, err := slicePkgFor(t.Elem)
		if err != nil {
			return "", err
		}
		return pkg + ".Slice", nil
	case *ir.MapType:
		pkg, err := mapPkgFor(t)
		if err != nil {
			return "", err
		}
		return pkg + ".Map", nil
	case nil:
		return "", fmt.Errorf("emit: missing type")
	}
	return "", fmt.Errorf("emit: unsupported type %T", t)
}
