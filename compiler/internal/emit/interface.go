package emit

import (
	"fmt"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

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
			if n.Receiver != nil {
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
