package emit

import (
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
