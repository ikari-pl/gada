package emit

import (
	"fmt"

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
func (e *emitter) emitStructTypes() error {
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
		if len(st.Fields) == 0 {
			e.println("type " + name + " is null record;")
			continue
		}
		e.println("type " + name + " is record")
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
