package emit

import (
	"fmt"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// Type-metadata emission (Phase 4 item 2c).
//
// For every `type` declaration in the file the compiler emits, at module
// init, a `Gada.Reflect.Types.Make (…)` + per-field `Add_Field` +
// `Gada.Reflect.Registry.Register_Type (…)` sequence so the runtime
// reflect surface can hand the descriptor back from TypeOf. Every type a
// descriptor *links* to (a struct field's type, a slice/chan element, a
// map key/value) is itself registered, with a per-program Type_Id, so
// the links resolve via Lookup — the same way Go's reflect.TypeOf(int)
// is a real Type.
//
// Ids are assigned deterministically: the defined types first in source
// order, then the referenced (built-in / composite) types in
// first-encountered order. Id 0 (No_Type) is reserved as the
// unregistered sentinel and is never assigned.

// typeMetaField is one resolved struct field: the field name and the
// Type_Id its type was assigned.
type typeMetaField struct {
	Name   string
	TypeID int
}

// typeMetaEntry is one type to register at module init.
type typeMetaEntry struct {
	ID     int
	Name   string // Go-facing name: "int", "Point", "[]int", …
	Kind   string // Ada Type_Kind literal: "Int_Kind", "Struct_Kind", …
	Fields []typeMetaField
	Elem   int // 0 == No_Type (Slice/Pointer/Chan element, Map value)
	Key    int // 0 == No_Type (Map key)
}

// typeMetaSet accumulates entries keyed by a canonical type string, in
// assignment order, so each distinct type is registered exactly once.
type typeMetaSet struct {
	byKey map[string]*typeMetaEntry
	order []string
	next  int
}

func newTypeMetaSet() *typeMetaSet {
	return &typeMetaSet{byKey: map[string]*typeMetaEntry{}, next: 1}
}

// entries returns the registration list in Id order.
func (s *typeMetaSet) entries() []typeMetaEntry {
	out := make([]typeMetaEntry, 0, len(s.order))
	for _, k := range s.order {
		out = append(out, *s.byKey[k])
	}
	return out
}

// metaTypeKind maps an IR type to its Ada Type_Kind literal. Defined
// types (TypeDecl) take the kind of their underlying — a `type Celsius
// float64` has Float_Kind, matching Go's reflect.Kind.
func metaTypeKind(t ir.Type) (string, error) {
	switch t.(type) {
	case *ir.IntType:
		return "Int_Kind", nil
	case *ir.StringType:
		return "String_Kind", nil
	case *ir.BoolType:
		return "Bool_Kind", nil
	case *ir.Float64Type:
		return "Float_Kind", nil
	case *ir.SliceType:
		return "Slice_Kind", nil
	case *ir.MapType:
		return "Map_Kind", nil
	case *ir.ChanType:
		return "Chan_Kind", nil
	case *ir.StructType:
		return "Struct_Kind", nil
	default:
		return "", fmt.Errorf("emit: no reflect Kind for type %T", t)
	}
}

// metaTypeKey is the canonical dedup/identity string for a built-in or
// composite type — also its Go-facing reflect Name.
func metaTypeKey(t ir.Type) (string, error) {
	switch t := t.(type) {
	case *ir.IntType:
		return "int", nil
	case *ir.StringType:
		return "string", nil
	case *ir.BoolType:
		return "bool", nil
	case *ir.Float64Type:
		return "float64", nil
	case *ir.SliceType:
		e, err := metaTypeKey(t.Elem)
		if err != nil {
			return "", err
		}
		return "[]" + e, nil
	case *ir.ChanType:
		e, err := metaTypeKey(t.Elem)
		if err != nil {
			return "", err
		}
		return "chan " + e, nil
	case *ir.MapType:
		k, err := metaTypeKey(t.Key)
		if err != nil {
			return "", err
		}
		v, err := metaTypeKey(t.Value)
		if err != nil {
			return "", err
		}
		return "map[" + k + "]" + v, nil
	default:
		return "", fmt.Errorf("emit: no reflect type key for %T", t)
	}
}

// fillComposite resolves the element / key / field links of a composite
// type t onto entry, interning each linked type. Scalars match no case
// and leave entry untouched (a named scalar like Celsius has no links).
// This is the single home for the link-resolution error paths, shared
// by internType (referenced composites) and collectTypeMeta's pass 2
// (the named type's underlying).
func (s *typeMetaSet) fillComposite(entry *typeMetaEntry, t ir.Type) error {
	switch t := t.(type) {
	case *ir.SliceType:
		id, err := s.internType(t.Elem)
		if err != nil {
			return err
		}
		entry.Elem = id
	case *ir.ChanType:
		id, err := s.internType(t.Elem)
		if err != nil {
			return err
		}
		entry.Elem = id
	case *ir.MapType:
		kid, err := s.internType(t.Key)
		if err != nil {
			return err
		}
		vid, err := s.internType(t.Value)
		if err != nil {
			return err
		}
		entry.Key = kid
		entry.Elem = vid
	case *ir.StructType:
		for _, f := range t.Fields {
			id, err := s.internType(f.Type)
			if err != nil {
				return err
			}
			entry.Fields = append(entry.Fields,
				typeMetaField{Name: f.Name, TypeID: id})
		}
	}
	return nil
}

// internType ensures t (a built-in or composite, never a TypeDecl's
// named identity) has an entry and returns its Id, recursing through
// element / key / field links so they are registered too.
func (s *typeMetaSet) internType(t ir.Type) (int, error) {
	key, err := metaTypeKey(t)
	if err != nil {
		return 0, err
	}
	if e, ok := s.byKey[key]; ok {
		return e.ID, nil
	}
	kind, err := metaTypeKind(t)
	if err != nil {
		return 0, err
	}
	// Reserve the Id before recursing so a self-referential composite
	// can't loop.
	entry := &typeMetaEntry{ID: s.next, Name: key, Kind: kind}
	s.next++
	s.byKey[key] = entry
	s.order = append(s.order, key)
	if err := s.fillComposite(entry, t); err != nil {
		return 0, err
	}
	return entry.ID, nil
}

// collectTypeMeta builds the registration list for every TypeDecl in
// decls. Defined types are assigned Ids first (source order) so their
// identity is stable regardless of which built-ins they happen to
// reference; referenced types are interned as their links are resolved.
func collectTypeMeta(decls []ir.Decl) (*typeMetaSet, error) {
	set := newTypeMetaSet()

	// Pass 1: reserve an Id + entry for each defined type, keyed by its
	// declared name (defined types share the Go name namespace). A
	// defined type takes the kind of its underlying (Celsius -> Float).
	defined := make([]*typeMetaEntry, 0)
	for _, d := range decls {
		td, ok := d.(*ir.TypeDecl)
		if !ok {
			continue
		}
		if _, seen := set.byKey[td.Name]; seen {
			return nil, fmt.Errorf("emit: duplicate type declaration %q", td.Name)
		}
		kind, err := metaTypeKind(td.Underlying)
		if err != nil {
			return nil, err
		}
		entry := &typeMetaEntry{ID: set.next, Name: td.Name, Kind: kind}
		set.next++
		set.byKey[td.Name] = entry
		set.order = append(set.order, td.Name)
		defined = append(defined, entry)
	}

	// Pass 2: resolve each defined type's links (struct fields, or a
	// slice/map/chan underlying's element/key), interning referenced
	// types — which get Ids after the defined ones. Scalars no-op.
	di := 0
	for _, d := range decls {
		td, ok := d.(*ir.TypeDecl)
		if !ok {
			continue
		}
		if err := set.fillComposite(defined[di], td.Underlying); err != nil {
			return nil, err
		}
		di++
	}
	return set, nil
}

// emitTypeMetadata writes the module-init registration sequence for the
// collected entries inside a `declare … begin … end;` block. The caller
// places it in the package body's elaboration part (or the main
// procedure's prologue). Indent is owned by the caller.
func (e *emitter) emitTypeMetadata(entries []typeMetaEntry) {
	e.println("declare")
	e.indent++
	e.println("Meta : Gada.Reflect.Types.Type_Descriptor;")
	e.indent--
	e.println("begin")
	e.indent++
	for _, m := range entries {
		e.println(fmt.Sprintf("--  %s", m.Name))
		mk := fmt.Sprintf(
			"Meta := Gada.Reflect.Types.Make (Id => %d, Name => %q, Kind => Gada.Reflect.Types.%s",
			m.ID, m.Name, m.Kind)
		if m.Elem != 0 {
			mk += fmt.Sprintf(", Elem => %d", m.Elem)
		}
		if m.Key != 0 {
			mk += fmt.Sprintf(", Key => %d", m.Key)
		}
		mk += ");"
		e.println(mk)
		for _, f := range m.Fields {
			e.println(fmt.Sprintf(
				"Gada.Reflect.Types.Add_Field (Meta, %q, Field_Type => %d);",
				f.Name, f.TypeID))
		}
		e.println("Gada.Reflect.Registry.Register_Type (Meta);")
	}
	e.indent--
	e.println("end;")
}
