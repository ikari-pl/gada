package emit

import (
	"fmt"
	"strings"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// Interface type emission (Phase 4 item 5b-i).
//
// A Go interface type becomes an Ada interface type — the tag-dispatched
// contract the Hybrid model builds native dispatch on (items 5c/5d). For
// `type Stringer interface { String() string }` the emitter writes
//
//	type Stringer is interface;
//	function String (Self : Stringer) return String is abstract;
//
// one abstract operation per method (a `procedure` when the method
// returns nothing). The empty `interface{}` (Go's `any`) is a bare
// `type X is interface;` with no operations. These declarations are
// emitted before the struct records (a record that derives an interface
// — item 5b-ii — needs it declared already), so emitTypeDecls sequences
// interfaces then structs.

// fileHasInterfaces reports whether the file declares any interface type.
func (e *emitter) fileHasInterfaces() bool {
	for _, d := range e.file.Decls {
		if td, ok := d.(*ir.TypeDecl); ok {
			if _, ok := td.Underlying.(*ir.InterfaceType); ok {
				return true
			}
		}
	}
	return false
}

// fileHasTypeDecls reports whether the file declares any interface or
// struct type — the two kinds the declarative part's type section emits.
func (e *emitter) fileHasTypeDecls() bool {
	return e.fileHasInterfaces() || e.fileHasStructs()
}

// emitTypeDecls emits the file's interface types then its struct types,
// separated by a blank line when both are present. Interfaces come first
// so a record that derives one (item 5b-ii) sees it already declared.
// Indent is owned by the caller.
func (e *emitter) emitTypeDecls() error {
	hasI := e.fileHasInterfaces()
	if hasI {
		if err := e.emitInterfaceTypes(); err != nil {
			return err
		}
	}
	if hasI && e.fileHasStructs() {
		e.println("")
	}
	if e.fileHasStructs() {
		if err := e.emitStructTypes(); err != nil {
			return err
		}
	}
	return nil
}

// emitInterfaceTypes writes one Ada interface type declaration per Go
// interface type in the file, in source order, each followed by its
// abstract operation specs. Indent is owned by the caller.
func (e *emitter) emitInterfaceTypes() error {
	for _, d := range e.file.Decls {
		td, ok := d.(*ir.TypeDecl)
		if !ok {
			continue
		}
		it, ok := td.Underlying.(*ir.InterfaceType)
		if !ok {
			continue
		}
		e.println("type " + adaIdent(td.Name) + " is interface;")
		for _, m := range it.Methods {
			spec, err := e.interfaceMethodSpec(td.Name, m)
			if err != nil {
				return err
			}
			e.println(spec)
		}
	}
	return nil
}

// interfaceMethodSpec renders one interface method as an Ada abstract
// operation controlled by the interface type: a `function … is
// abstract;` for a single-result method, a `procedure … is abstract;`
// for a result-less one. The interface type is the controlling first
// parameter `Self`. Go's multi-result methods have no direct Ada
// function form, so 2+ results are rejected loudly.
func (e *emitter) interfaceMethodSpec(ifaceName string, m *ir.MethodSig) (string, error) {
	params := []string{"Self : " + adaIdent(ifaceName)}
	for i, p := range m.Params {
		t, err := typeName(p.Type)
		if err != nil {
			return "", err
		}
		params = append(params, methodParamName(p.Name, i)+" : "+t)
	}
	plist := " (" + strings.Join(params, "; ") + ")"
	name := adaIdent(m.Name)
	switch len(m.Results) {
	case 0:
		return "procedure " + name + plist + " is abstract;", nil
	case 1:
		rt, err := typeName(m.Results[0].Type)
		if err != nil {
			return "", err
		}
		return "function " + name + plist + " return " + rt + " is abstract;", nil
	default:
		return "", fmt.Errorf("emit: interface method %s has %d results; an Ada function returns one value (multi-result interface methods not supported)", m.Name, len(m.Results))
	}
}

// methodParamName gives an Ada name to a method parameter: the Go name
// when present, else a synthetic `Arg_<n>` (Go interface methods and
// unnamed parameters carry no name, but Ada parameters must be named).
func methodParamName(goName string, index int) string {
	if goName != "" {
		return adaIdent(goName)
	}
	return fmt.Sprintf("Arg_%d", index+1)
}

// Interface satisfaction emission (Phase 4 item 4c-ii).
//
// Under the Hybrid interface model, native Ada tagged types carry the
// actual dispatch (items 5–6); this file emits the *introspection* half.
// For every (concrete defined type, interface defined type) pair in the
// file the compiler proves structurally satisfied — the concrete type's
// method set ⊇ the interface's, matched by name and signature — it emits
// a `Gada.Reflect.Interfaces.Register` call at module init, populating
// the runtime satisfaction registry (item 4c-i) that answers a
// reflect-style "does C implement I?".
//
// Satisfaction is computed independent of Type_Id assignment so the
// with-clause pre-pass (which only needs to know *whether* any pair
// exists) and the emitter (which resolves Ids from the metadata set)
// share one function.

// namePair is a proven (concrete, interface) satisfaction by type name.
type namePair struct {
	Concrete string
	Iface    string
}

// satisfiedPairs returns every (concrete, interface) name pair in decls
// the compiler proves satisfied. Only non-interface defined types are
// considered as the concrete side; interface-to-interface satisfaction
// (embedding / wider-implements-narrower) is deferred. A concrete type
// satisfies the empty interface (`any`) vacuously.
func satisfiedPairs(decls []ir.Decl) []namePair {
	type ifaceDef struct {
		name    string
		methods []*ir.MethodSig
	}
	var ifaces []ifaceDef
	var concretes []string
	methodsByType := map[string][]*ir.Function{}

	for _, d := range decls {
		switch n := d.(type) {
		case *ir.TypeDecl:
			if it, ok := n.Underlying.(*ir.InterfaceType); ok {
				ifaces = append(ifaces, ifaceDef{n.Name, it.Methods})
			} else {
				concretes = append(concretes, n.Name)
			}
		case *ir.Function:
			// A *value* type's method set excludes pointer-receiver
			// methods — `func (p *T)` is in *T's set, not T's. We model
			// only the value type as the concrete side, so a pointer
			// receiver does not count toward its satisfaction. (Pointer-
			// type satisfaction needs *T as its own reflect type, which
			// rides item 5.)
			if n.Receiver != nil && !n.Receiver.Pointer {
				methodsByType[n.Receiver.Type] =
					append(methodsByType[n.Receiver.Type], n)
			}
		}
	}

	var pairs []namePair
	for _, c := range concretes {
		for _, iface := range ifaces {
			if methodSetSatisfies(methodsByType[c], iface.methods) {
				pairs = append(pairs, namePair{Concrete: c, Iface: iface.name})
			}
		}
	}
	return pairs
}

// methodSetSatisfies reports whether the concrete method set provides a
// matching method (name + signature) for every method the interface
// requires. An empty requirement is satisfied vacuously (Go's `any`).
func methodSetSatisfies(concrete []*ir.Function, required []*ir.MethodSig) bool {
	for _, m := range required {
		matched := false
		for _, fn := range concrete {
			if sigMatches(m, fn) {
				matched = true
				break
			}
		}
		if !matched {
			return false
		}
	}
	return true
}

// sigMatches reports whether the concrete method fn implements the
// interface method m: same name, and identical parameter and result
// type lists (receiver and parameter *names* are irrelevant to the Go
// method-set match, only the types).
func sigMatches(m *ir.MethodSig, fn *ir.Function) bool {
	return m.Name == fn.Name &&
		paramTypesMatch(m.Params, fn.Params) &&
		paramTypesMatch(m.Results, fn.Results)
}

// paramTypesMatch compares two parameter lists by type only, using the
// canonical type key. A type with no key (one metaTypeKey rejects)
// cannot be proven equal, so it conservatively fails the match.
func paramTypesMatch(a, b []*ir.Param) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		ka, ea := metaTypeKey(a[i].Type)
		kb, eb := metaTypeKey(b[i].Type)
		if ea != nil || eb != nil || ka != kb {
			return false
		}
	}
	return true
}

// emitInterfaceSatisfaction emits a Register call per proven pair,
// resolving each side's Type_Id from the metadata set. Indent is owned
// by the caller (it shares the module-init block with the metadata).
func (e *emitter) emitInterfaceSatisfaction(set *typeMetaSet, pairs []namePair) {
	for _, p := range pairs {
		c, cok := set.byKey[p.Concrete]
		i, iok := set.byKey[p.Iface]
		if !cok || !iok {
			// Both sides are defined types interned in the same set, so
			// this cannot happen; guard rather than emit a bad Id.
			continue
		}
		e.println(fmt.Sprintf("--  %s satisfies %s", p.Concrete, p.Iface))
		e.println(fmt.Sprintf(
			"Gada.Reflect.Interfaces.Register (Concrete => %d, Iface => %d);",
			c.ID, i.ID))
	}
}
