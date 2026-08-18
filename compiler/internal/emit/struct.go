package emit

import (
	"fmt"
	"strings"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// Struct type emission (Phase 4 item 5a-i).
//
// A Go struct type becomes an Ada record type, declared in the enclosing
// unit's declarative part (the Main procedure for a `package main`, or
// the package body otherwise):
//
//	type Point struct { X, Y int }
//	  -->  type Point is record
//	          X : Integer;
//	          Y : Integer;
//	       end record;
//
// An empty struct has no components, which Ada spells `is null record`
// (a fieldless `record … end record` is illegal). Tagged-ness and the
// `and Interface` derivation for types that satisfy an interface ride
// item 5b; this slice emits the plain value record so structs become
// usable Ada types for the first time.

// fileHasStructs reports whether the file declares any struct type, so
// the caller can manage the declarative-part spacing.
func (e *emitter) fileHasStructs() bool {
	for _, d := range e.file.Decls {
		if td, ok := d.(*ir.TypeDecl); ok {
			if _, ok := td.Underlying.(*ir.StructType); ok {
				return true
			}
		}
	}
	return false
}

// emitStructTypes writes one Ada record type declaration per Go struct
// type in the file, in source order. Indent is owned by the caller.
//
// A struct that satisfies one or more interfaces (item 5b-ii) becomes a
// tagged type deriving them — `type C is new I1 [and I2 …] with record
// … end record;` (or `with null record;` when fieldless) — followed by
// an `overriding` spec for every distinct interface method it
// implements. A struct that satisfies no interface stays the plain
// untagged record of item 5a-i. Bodies for the overriding ops ride 5c.
func (e *emitter) emitStructTypes() error {
	pairs := satisfiedPairs(e.file.Decls)
	ifaceMethods := interfaceMethodsByName(e.file.Decls)
	valueMethods := valueMethodsByType(e.file.Decls)

	for _, d := range e.file.Decls {
		td, ok := d.(*ir.TypeDecl)
		if !ok {
			continue
		}
		st, ok := td.Underlying.(*ir.StructType)
		if !ok {
			continue
		}
		name := adaIdent(td.Name)
		ifaces := ifacesFor(td.Name, pairs, ifaceMethods)

		// Record header: a plain `is record` / `is null record`, or the
		// tagged `is new I1 and I2 with record` derivation.
		header := "type " + name + " is "
		if len(ifaces) > 0 {
			derived := make([]string, len(ifaces))
			for i, in := range ifaces {
				derived[i] = adaIdent(in)
			}
			header += "new " + strings.Join(derived, " and ") + " with "
		}

		if len(st.Fields) == 0 {
			e.println(header + "null record;")
		} else {
			e.println(header + "record")
			e.indent++
			for _, f := range st.Fields {
				if err := validStructFieldType(f.Type); err != nil {
					return fmt.Errorf("emit: struct %s field %q: %w", td.Name, f.Name, err)
				}
				tn, err := typeName(f.Type)
				if err != nil {
					return err
				}
				e.println(adaIdent(f.Name) + " : " + tn + ";")
			}
			e.indent--
			e.println("end record;")
		}

		if len(ifaces) > 0 {
			specs, err := e.overridingSpecs(td.Name, ifaces, ifaceMethods, valueMethods)
			if err != nil {
				return err
			}
			for _, spec := range specs {
				e.println(spec)
			}
		}
	}
	return nil
}

// overridingSpecs returns the `overriding` operation specs a concrete
// type must declare: one per distinct interface method it implements
// across the interfaces it derives, in interface-then-method source
// order, deduplicated by method name (a method shared by two derived
// interfaces is overridden once). Each spec mirrors the concrete
// method's own signature, with its receiver as the controlling first
// parameter; the body rides 5c.
func (e *emitter) overridingSpecs(concrete string, ifaces []string, ifaceMethods map[string][]*ir.MethodSig, valueMethods map[string][]*ir.Function) ([]string, error) {
	ctype := adaIdent(concrete)
	seen := map[string]bool{}
	var specs []string
	for _, in := range ifaces {
		for _, m := range ifaceMethods[in] {
			if seen[m.Name] {
				continue
			}
			seen[m.Name] = true
			fn := findMethod(valueMethods[concrete], m.Name)
			if fn == nil {
				// satisfiedPairs proved concrete implements the interface,
				// so a matching value-receiver method exists; guard rather
				// than emit a spec for a method we cannot render.
				continue
			}
			recv := "Self"
			if fn.Receiver != nil && fn.Receiver.Name != "" {
				recv = adaIdent(fn.Receiver.Name)
			}
			spec, err := dispatchOpSpec("overriding ", recv, ctype, fn.Name, fn.Params, fn.Results, ";")
			if err != nil {
				return nil, err
			}
			specs = append(specs, spec)
		}
	}
	return specs, nil
}

// ifacesFor returns the interfaces a concrete type derives — the
// interfaces it satisfies that carry at least one method — in the source
// order satisfiedPairs produced (interface-declaration order). A
// method-less interface (Go's `any`, or any `interface{}` alias) is
// excluded: every type satisfies it vacuously, so deriving it would flip
// every struct in a file that merely *declares* an empty interface from
// an untagged record (5a-i) to a tagged type, adding taggedness with no
// operation to dispatch. Empty-interface satisfaction still lives in the
// reflect registry (item 4c) — this filter governs only Ada derivation.
func ifacesFor(concrete string, pairs []namePair, ifaceMethods map[string][]*ir.MethodSig) []string {
	var out []string
	for _, p := range pairs {
		if p.Concrete == concrete && len(ifaceMethods[p.Iface]) > 0 {
			out = append(out, p.Iface)
		}
	}
	return out
}

// interfaceMethodsByName indexes each interface type's method set by the
// interface's name.
func interfaceMethodsByName(decls []ir.Decl) map[string][]*ir.MethodSig {
	m := map[string][]*ir.MethodSig{}
	for _, d := range decls {
		if td, ok := d.(*ir.TypeDecl); ok {
			if it, ok := td.Underlying.(*ir.InterfaceType); ok {
				m[td.Name] = it.Methods
			}
		}
	}
	return m
}

// overridingMethods returns the set of value-receiver methods that are
// overriding dispatch operations — the methods 5b-ii declares specs for
// and 5c emits bodies for. A method qualifies when its receiver type
// derives at least one interface (method-less interfaces excluded, per
// ifacesFor) and its name matches a method of one of those interfaces.
// A method on a non-deriving type, or one not part of any derived
// interface, is not `overriding` and is excluded (direct-call emission
// for such methods rides a later item). Keyed by the *ir.Function so the
// emitter can decide per-decl whether to emit a body.
func overridingMethods(decls []ir.Decl) map[*ir.Function]bool {
	pairs := satisfiedPairs(decls)
	ifaceMethods := interfaceMethodsByName(decls)
	valueMethods := valueMethodsByType(decls)
	set := map[*ir.Function]bool{}
	for _, d := range decls {
		td, ok := d.(*ir.TypeDecl)
		if !ok {
			continue
		}
		if _, ok := td.Underlying.(*ir.StructType); !ok {
			continue
		}
		for _, in := range ifacesFor(td.Name, pairs, ifaceMethods) {
			for _, m := range ifaceMethods[in] {
				if fn := findMethod(valueMethods[td.Name], m.Name); fn != nil {
					set[fn] = true
				}
			}
		}
	}
	return set
}

// findMethod returns the function named name from fns, or nil.
func findMethod(fns []*ir.Function, name string) *ir.Function {
	for _, fn := range fns {
		if fn.Name == name {
			return fn
		}
	}
	return nil
}

// validStructFieldType reports whether a Go struct field of type t
// currently lowers to a valid, self-contained Ada record component.
// Integer / Boolean / Long_Float are definite, always-available scalar
// subtypes — valid components with a synthesisable Go zero (see
// zeroValueFor). Two field types are rejected loudly rather than
// mis-emitted:
//
//   - string: an unconstrained `String` record component is illegal Ada
//     (a component of an unconstrained type needs a constraint), so a
//     struct with a string field cannot yet emit a compilable record.
//     A bounded/constrained string component is a later item.
//   - slice / map / chan: the component names a `Slices_Of_<T>` /
//     `Maps_Of_…` / `Channels_Of_<T>` package that the type-collection
//     walk does not instantiate from struct fields (recordTypeInTree
//     does not recurse into a StructType), so the name is undefined at
//     gprbuild time. Lifting this needs the field-type walk plus the
//     non-scalar zero values, tracked together.
//
// Keeping the accepted set in one place lets emitStructTypes (the record
// declaration) and zeroValueFor (the aggregate fill) stay in lockstep:
// a field type is emittable only if its zero is synthesisable.
func validStructFieldType(t ir.Type) error {
	switch t.(type) {
	case *ir.IntType, *ir.BoolType, *ir.Float64Type:
		return nil
	case *ir.StringType:
		return fmt.Errorf("type string not yet supported (an unconstrained String record component is invalid Ada; a bounded string component is a later item)")
	}
	return fmt.Errorf("type %T not yet supported (a slice/map/chan struct field needs its runtime instantiation driven from the field walk)", t)
}
