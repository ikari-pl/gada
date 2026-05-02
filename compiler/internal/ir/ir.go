// Package ir defines the GADA intermediate representation: a small,
// typed tree sitting between the Go AST consumer (compiler/internal/translate)
// and the Ada source emitter (compiler/internal/emit).
//
// Phase 1 scope is deliberately narrow — only the constructs needed by
// the `hello, GADA` corpus and the nine other small fixtures listed in
// roadmap/01-minimal-transpiler.md. Each later phase widens the IR; the
// JSON form is the contract that lets golden-file tests catch accidental
// drift in either direction.
//
// Design notes:
//
//   - Sum types (Decl, Stmt, Expr, Type) are sealed Go interfaces. The
//     unexported sentinel method (ir<X>()) prevents non-IR types from
//     pretending to be IR nodes; the `NodeKind() string` method gives
//     every node a stable JSON discriminator.
//   - Each concrete node implements both MarshalJSON and UnmarshalJSON.
//     Marshal embeds the discriminator inline as `"kind":"<NodeName>"`;
//     Unmarshal ignores the kind field on its own type and dispatches
//     via unmarshalDecl/Stmt/Expr/Type for any interface-typed field.
//   - Slice fields preserve nil-vs-empty distinction across round-trip
//     so `reflect.DeepEqual(orig, decoded)` holds for any well-formed
//     input.
package ir

import (
	"encoding/json"
	"fmt"
)

// Package is the top-level IR node: one Go package becomes one Ada
// compilation context. Files are kept distinct because the emitter
// produces one Ada compilation unit per Go file.
type Package struct {
	Name  string
	Files []*File
}

// File represents a single Go source file translated to IR.
type File struct {
	Name    string
	Imports []string
	Decls   []Decl
}

// Decl is the sealed interface for top-level declarations. Phase 1
// only needs Function; later phases will add Var, Const, Type.
type Decl interface {
	irDecl()
	NodeKind() string
}

// Function is a Go top-level `func` declaration.
type Function struct {
	Name    string
	Params  []*Param
	Results []*Param
	Body    []Stmt
}

func (*Function) irDecl()          {}
func (*Function) NodeKind() string { return "Function" }

// Param is one parameter or named result.
//
// Phase 1 keeps it minimal: a name (possibly empty for unnamed
// returns) and a type. Variadic and blank-identifier parameters are
// out of scope until Phase 2.
type Param struct {
	Name string
	Type Type
}

// Stmt is the sealed interface for statements.
type Stmt interface {
	irStmt()
	NodeKind() string
}

// Assign covers both `=` (Define=false) and `:=` (Define=true).
// Multi-value assignments are represented by parallel LHS/RHS slices.
type Assign struct {
	LHS    []Expr
	Define bool
	RHS    []Expr
}

func (*Assign) irStmt()          {}
func (*Assign) NodeKind() string { return "Assign" }

// If is a Go `if`/`else` chain. `else if` is represented by Else
// containing a single nested If.
type If struct {
	Cond Expr
	Then []Stmt
	Else []Stmt
}

func (*If) irStmt()          {}
func (*If) NodeKind() string { return "If" }

// For is the C-style three-clause loop. The bare `for {}` infinite
// form is represented with Init == nil, Cond == nil, Post == nil.
// Range loops are out of Phase 1 scope.
type For struct {
	Init Stmt
	Cond Expr
	Post Stmt
	Body []Stmt
}

func (*For) irStmt()          {}
func (*For) NodeKind() string { return "For" }

// Return carries zero or more result expressions.
type Return struct {
	Results []Expr
}

func (*Return) irStmt()          {}
func (*Return) NodeKind() string { return "Return" }

// Call is a function or method invocation used in statement
// position. Call-as-expression is intentionally deferred until a
// later phase; the corpus does not need it.
type Call struct {
	Fun  Expr
	Args []Expr
}

func (*Call) irStmt()          {}
func (*Call) NodeKind() string { return "Call" }

// ExprStmt wraps a non-call expression used in statement position.
// Rare in practice but cheap to support and lets the AST translator
// stay total.
type ExprStmt struct {
	X Expr
}

func (*ExprStmt) irStmt()          {}
func (*ExprStmt) NodeKind() string { return "ExprStmt" }

// Expr is the sealed interface for expressions.
type Expr interface {
	irExpr()
	NodeKind() string
}

// Ident is a bare identifier reference.
type Ident struct {
	Name string
}

func (*Ident) irExpr()          {}
func (*Ident) NodeKind() string { return "Ident" }

// LitKind enumerates the basic literal categories Phase 1 understands.
type LitKind string

const (
	LitInt    LitKind = "int"
	LitString LitKind = "string"
	LitBool   LitKind = "bool"
	LitFloat  LitKind = "float64"
)

// Lit is a literal. Value is the canonical Go source form so the
// emitter can re-quote it deterministically (e.g. string literals
// keep their surrounding double-quotes; bools are "true"/"false").
type Lit struct {
	Kind  LitKind
	Value string
}

func (*Lit) irExpr()          {}
func (*Lit) NodeKind() string { return "Lit" }

// BinOp is a binary operator expression. Op is the Go-source operator
// string (e.g. "+", "<", "&&"); the emitter translates to the Ada
// equivalent.
type BinOp struct {
	Op string
	X  Expr
	Y  Expr
}

func (*BinOp) irExpr()          {}
func (*BinOp) NodeKind() string { return "BinOp" }

// UnaryOp is a unary operator expression (e.g. "-x", "!ok").
type UnaryOp struct {
	Op string
	X  Expr
}

func (*UnaryOp) irExpr()          {}
func (*UnaryOp) NodeKind() string { return "UnaryOp" }

// Selector is a `pkg.Field` / `obj.Method` reference. Phase 1's only
// real use is `fmt.Println`; later phases generalise to arbitrary
// dotted access.
type Selector struct {
	X   Expr
	Sel string
}

func (*Selector) irExpr()          {}
func (*Selector) NodeKind() string { return "Selector" }

// SliceLit is a Go slice composite literal: `[]T{e1, e2, ...}`. Elem
// is the element type; Elems carries the (possibly empty) initialiser
// list. Used by Phase 2's slice-emission path to dispatch a single
// `Slices_Of_<T>.From_Array ([…])` call.
type SliceLit struct {
	Elem  Type
	Elems []Expr
}

func (*SliceLit) irExpr()          {}
func (*SliceLit) NodeKind() string { return "SliceLit" }

// IndexExpr is `X[Index]`. The same node shape covers slice indexing
// (`s[i]`) and map lookup (`m[k]`); the emitter resolves the
// distinction by inspecting the static type of X via its declaration.
type IndexExpr struct {
	X     Expr
	Index Expr
}

func (*IndexExpr) irExpr()          {}
func (*IndexExpr) NodeKind() string { return "IndexExpr" }

// SliceExpr is `X[Low:High]`. Low or High may be nil to model the
// `s[:j]` / `s[i:]` / `s[:]` shapes; the emitter substitutes 0 for a
// missing Low and `Length(s)` for a missing High.
type SliceExpr struct {
	X    Expr
	Low  Expr
	High Expr
}

func (*SliceExpr) irExpr()          {}
func (*SliceExpr) NodeKind() string { return "SliceExpr" }

// MapEntry is one `K: V` pair inside a `MapLit`. Not a sum-type
// variant — has its own MarshalJSON/UnmarshalJSON pair like *Param.
type MapEntry struct {
	Key   Expr
	Value Expr
}

// MapLit is a Go map composite literal: `map[K]V{k1: v1, k2: v2}`.
// Key and Value carry the element types so the emitter can pick the
// right `Maps_Of_<K>_To_<V>` instantiation without re-walking the
// entries.
type MapLit struct {
	Key     Type
	Value   Type
	Entries []*MapEntry
}

func (*MapLit) irExpr()          {}
func (*MapLit) NodeKind() string { return "MapLit" }

// RangeStmt is Go `for k, v := range x { ... }` (and the elided
// `for k := range x` / `for range x` shapes; empty KeyName/ValueName
// means the corresponding bound was absent or blank-identifier in
// the source). Define discriminates `:=` (true) from `=` (false).
//
// Phase 2 emits range-over-map; range-over-slice arrives when the
// emitter learns the integer-index iteration shape.
type RangeStmt struct {
	KeyName   string
	ValueName string
	Define    bool
	X         Expr
	Body      []Stmt
}

func (*RangeStmt) irStmt()          {}
func (*RangeStmt) NodeKind() string { return "RangeStmt" }

// BuiltinCall is a call to a Go predeclared function. Distinguished
// from Call (which carries an arbitrary Fun expression) so the
// emitter can dispatch by name without re-deriving builtin-ness.
//
// Phase 2 names: "append", "len", "cap" (slice item); "delete" (map
// item); "panic", "recover" (defer/panic item). Each later phase
// widens the recognised set.
//
// The node implements both Stmt and Expr because Go allows bare
// `panic(x)` as a statement and `recover()` as an expression in
// `if r := recover(); r != nil`.
type BuiltinCall struct {
	Name string
	Args []Expr
}

func (*BuiltinCall) irExpr()          {}
func (*BuiltinCall) irStmt()          {}
func (*BuiltinCall) NodeKind() string { return "BuiltinCall" }

// Type is the sealed interface for type references. Phase 1 covers
// the four Go basic types the corpus uses; named, struct, slice,
// map, channel, and function types arrive in later phases.
type Type interface {
	irType()
	NodeKind() string
}

// IntType is Go `int` (translates to Ada `Integer`).
type IntType struct{}

func (*IntType) irType()          {}
func (*IntType) NodeKind() string { return "IntType" }

// StringType is Go `string` (translates to Ada `String`).
type StringType struct{}

func (*StringType) irType()          {}
func (*StringType) NodeKind() string { return "StringType" }

// BoolType is Go `bool` (translates to Ada `Boolean`).
type BoolType struct{}

func (*BoolType) irType()          {}
func (*BoolType) NodeKind() string { return "BoolType" }

// Float64Type is Go `float64` (translates to Ada `Long_Float`).
type Float64Type struct{}

func (*Float64Type) irType()          {}
func (*Float64Type) NodeKind() string { return "Float64Type" }

// SliceType is Go `[]T`. Elem is the element type. Translates to a
// generic instantiation of `Gada.Core.Slices` per element type — the
// emitter tracks one `Slices_Of_<T>` per file.
type SliceType struct {
	Elem Type
}

func (*SliceType) irType()          {}
func (*SliceType) NodeKind() string { return "SliceType" }

// MapType is Go `map[K]V`. Translates to a generic instantiation of
// `Gada.Core.Maps` per (K, V) pair — the emitter tracks one
// `Maps_Of_<K>_To_<V>` per file.
type MapType struct {
	Key   Type
	Value Type
}

func (*MapType) irType()          {}
func (*MapType) NodeKind() string { return "MapType" }

// ---------------------------------------------------------------------------
// JSON marshaling and unmarshaling
//
// Pattern: each concrete node's MarshalJSON serialises an anonymous struct
// whose first field is `"kind":"<NodeName>"` followed by the node's data
// fields. Each interface-typed field is marshaled by the standard library
// (which calls the value's own MarshalJSON), and unmarshaled by reading the
// raw JSON into json.RawMessage and dispatching through unmarshalDecl,
// unmarshalStmt, unmarshalExpr, or unmarshalType.
// ---------------------------------------------------------------------------

func unmarshalDecl(raw json.RawMessage) (Decl, error) {
	var env struct {
		Kind string `json:"kind"`
	}
	if err := json.Unmarshal(raw, &env); err != nil {
		return nil, fmt.Errorf("ir: decoding decl envelope: %w", err)
	}
	switch env.Kind {
	case "Function":
		var n Function
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	default:
		return nil, fmt.Errorf("ir: unknown decl kind %q", env.Kind)
	}
}

func unmarshalStmt(raw json.RawMessage) (Stmt, error) {
	var env struct {
		Kind string `json:"kind"`
	}
	if err := json.Unmarshal(raw, &env); err != nil {
		return nil, fmt.Errorf("ir: decoding stmt envelope: %w", err)
	}
	switch env.Kind {
	case "Assign":
		var n Assign
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "If":
		var n If
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "For":
		var n For
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "Return":
		var n Return
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "Call":
		var n Call
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "ExprStmt":
		var n ExprStmt
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "BuiltinCall":
		var n BuiltinCall
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "RangeStmt":
		var n RangeStmt
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	default:
		return nil, fmt.Errorf("ir: unknown stmt kind %q", env.Kind)
	}
}

func unmarshalExpr(raw json.RawMessage) (Expr, error) {
	var env struct {
		Kind string `json:"kind"`
	}
	if err := json.Unmarshal(raw, &env); err != nil {
		return nil, fmt.Errorf("ir: decoding expr envelope: %w", err)
	}
	switch env.Kind {
	case "Ident":
		var n Ident
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "Lit":
		var n Lit
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "BinOp":
		var n BinOp
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "UnaryOp":
		var n UnaryOp
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "Selector":
		var n Selector
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "SliceLit":
		var n SliceLit
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "IndexExpr":
		var n IndexExpr
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "SliceExpr":
		var n SliceExpr
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "BuiltinCall":
		var n BuiltinCall
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "MapLit":
		var n MapLit
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	default:
		return nil, fmt.Errorf("ir: unknown expr kind %q", env.Kind)
	}
}

func unmarshalType(raw json.RawMessage) (Type, error) {
	var env struct {
		Kind string `json:"kind"`
	}
	if err := json.Unmarshal(raw, &env); err != nil {
		return nil, fmt.Errorf("ir: decoding type envelope: %w", err)
	}
	switch env.Kind {
	case "IntType":
		return &IntType{}, nil
	case "StringType":
		return &StringType{}, nil
	case "BoolType":
		return &BoolType{}, nil
	case "Float64Type":
		return &Float64Type{}, nil
	case "SliceType":
		var n SliceType
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	case "MapType":
		var n MapType
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, err
		}
		return &n, nil
	default:
		return nil, fmt.Errorf("ir: unknown type kind %q", env.Kind)
	}
}

// unmarshalStmtList preserves the nil-vs-empty distinction so
// round-trips remain reflect.DeepEqual-stable.
func unmarshalStmtList(raws []json.RawMessage) ([]Stmt, error) {
	if raws == nil {
		return nil, nil
	}
	out := make([]Stmt, 0, len(raws))
	for _, r := range raws {
		s, err := unmarshalStmt(r)
		if err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, nil
}

func unmarshalExprList(raws []json.RawMessage) ([]Expr, error) {
	if raws == nil {
		return nil, nil
	}
	out := make([]Expr, 0, len(raws))
	for _, r := range raws {
		e, err := unmarshalExpr(r)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, nil
}

// unmarshalOptionalStmt handles a single Stmt field that may be JSON
// null (e.g. For.Init / For.Post on a bare `for {}` loop).
func unmarshalOptionalStmt(raw json.RawMessage) (Stmt, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return nil, nil
	}
	return unmarshalStmt(raw)
}

func unmarshalOptionalExpr(raw json.RawMessage) (Expr, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return nil, nil
	}
	return unmarshalExpr(raw)
}

// --- Package / File / Function / Param ---

func (p *Package) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind  string  `json:"kind"`
		Name  string  `json:"name"`
		Files []*File `json:"files"`
	}{"Package", p.Name, p.Files})
}

func (p *Package) UnmarshalJSON(b []byte) error {
	var aux struct {
		Name  string  `json:"name"`
		Files []*File `json:"files"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	p.Name = aux.Name
	p.Files = aux.Files
	return nil
}

func (f *File) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind    string   `json:"kind"`
		Name    string   `json:"name"`
		Imports []string `json:"imports"`
		Decls   []Decl   `json:"decls"`
	}{"File", f.Name, f.Imports, f.Decls})
}

func (f *File) UnmarshalJSON(b []byte) error {
	var aux struct {
		Name    string            `json:"name"`
		Imports []string          `json:"imports"`
		Decls   []json.RawMessage `json:"decls"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	f.Name = aux.Name
	f.Imports = aux.Imports
	if aux.Decls == nil {
		f.Decls = nil
	} else {
		f.Decls = make([]Decl, 0, len(aux.Decls))
		for _, raw := range aux.Decls {
			d, err := unmarshalDecl(raw)
			if err != nil {
				return err
			}
			f.Decls = append(f.Decls, d)
		}
	}
	return nil
}

func (f *Function) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind    string   `json:"kind"`
		Name    string   `json:"name"`
		Params  []*Param `json:"params"`
		Results []*Param `json:"results"`
		Body    []Stmt   `json:"body"`
	}{"Function", f.Name, f.Params, f.Results, f.Body})
}

func (f *Function) UnmarshalJSON(b []byte) error {
	var aux struct {
		Name    string            `json:"name"`
		Params  []*Param          `json:"params"`
		Results []*Param          `json:"results"`
		Body    []json.RawMessage `json:"body"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	f.Name = aux.Name
	f.Params = aux.Params
	f.Results = aux.Results
	body, err := unmarshalStmtList(aux.Body)
	if err != nil {
		return err
	}
	f.Body = body
	return nil
}

func (p *Param) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		Name string `json:"name"`
		Type Type   `json:"type"`
	}{"Param", p.Name, p.Type})
}

func (p *Param) UnmarshalJSON(b []byte) error {
	var aux struct {
		Name string          `json:"name"`
		Type json.RawMessage `json:"type"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	p.Name = aux.Name
	if len(aux.Type) > 0 && string(aux.Type) != "null" {
		t, err := unmarshalType(aux.Type)
		if err != nil {
			return err
		}
		p.Type = t
	}
	return nil
}

// --- Statements ---

func (a *Assign) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind   string `json:"kind"`
		LHS    []Expr `json:"lhs"`
		Define bool   `json:"define"`
		RHS    []Expr `json:"rhs"`
	}{"Assign", a.LHS, a.Define, a.RHS})
}

func (a *Assign) UnmarshalJSON(b []byte) error {
	var aux struct {
		LHS    []json.RawMessage `json:"lhs"`
		Define bool              `json:"define"`
		RHS    []json.RawMessage `json:"rhs"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	a.Define = aux.Define
	lhs, err := unmarshalExprList(aux.LHS)
	if err != nil {
		return err
	}
	a.LHS = lhs
	rhs, err := unmarshalExprList(aux.RHS)
	if err != nil {
		return err
	}
	a.RHS = rhs
	return nil
}

func (s *If) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		Cond Expr   `json:"cond"`
		Then []Stmt `json:"then"`
		Else []Stmt `json:"else"`
	}{"If", s.Cond, s.Then, s.Else})
}

func (s *If) UnmarshalJSON(b []byte) error {
	var aux struct {
		Cond json.RawMessage   `json:"cond"`
		Then []json.RawMessage `json:"then"`
		Else []json.RawMessage `json:"else"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	cond, err := unmarshalOptionalExpr(aux.Cond)
	if err != nil {
		return err
	}
	s.Cond = cond
	then, err := unmarshalStmtList(aux.Then)
	if err != nil {
		return err
	}
	s.Then = then
	els, err := unmarshalStmtList(aux.Else)
	if err != nil {
		return err
	}
	s.Else = els
	return nil
}

func (s *For) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		Init Stmt   `json:"init"`
		Cond Expr   `json:"cond"`
		Post Stmt   `json:"post"`
		Body []Stmt `json:"body"`
	}{"For", s.Init, s.Cond, s.Post, s.Body})
}

func (s *For) UnmarshalJSON(b []byte) error {
	var aux struct {
		Init json.RawMessage   `json:"init"`
		Cond json.RawMessage   `json:"cond"`
		Post json.RawMessage   `json:"post"`
		Body []json.RawMessage `json:"body"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	init, err := unmarshalOptionalStmt(aux.Init)
	if err != nil {
		return err
	}
	s.Init = init
	cond, err := unmarshalOptionalExpr(aux.Cond)
	if err != nil {
		return err
	}
	s.Cond = cond
	post, err := unmarshalOptionalStmt(aux.Post)
	if err != nil {
		return err
	}
	s.Post = post
	body, err := unmarshalStmtList(aux.Body)
	if err != nil {
		return err
	}
	s.Body = body
	return nil
}

func (s *Return) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind    string `json:"kind"`
		Results []Expr `json:"results"`
	}{"Return", s.Results})
}

func (s *Return) UnmarshalJSON(b []byte) error {
	var aux struct {
		Results []json.RawMessage `json:"results"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	results, err := unmarshalExprList(aux.Results)
	if err != nil {
		return err
	}
	s.Results = results
	return nil
}

func (s *Call) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		Fun  Expr   `json:"fun"`
		Args []Expr `json:"args"`
	}{"Call", s.Fun, s.Args})
}

func (s *Call) UnmarshalJSON(b []byte) error {
	var aux struct {
		Fun  json.RawMessage   `json:"fun"`
		Args []json.RawMessage `json:"args"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	fun, err := unmarshalOptionalExpr(aux.Fun)
	if err != nil {
		return err
	}
	s.Fun = fun
	args, err := unmarshalExprList(aux.Args)
	if err != nil {
		return err
	}
	s.Args = args
	return nil
}

func (s *ExprStmt) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		X    Expr   `json:"x"`
	}{"ExprStmt", s.X})
}

func (s *ExprStmt) UnmarshalJSON(b []byte) error {
	var aux struct {
		X json.RawMessage `json:"x"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	x, err := unmarshalOptionalExpr(aux.X)
	if err != nil {
		return err
	}
	s.X = x
	return nil
}

// --- Expressions ---

func (e *Ident) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		Name string `json:"name"`
	}{"Ident", e.Name})
}

func (e *Ident) UnmarshalJSON(b []byte) error {
	var aux struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	e.Name = aux.Name
	return nil
}

func (e *Lit) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind    string  `json:"kind"`
		LitKind LitKind `json:"litKind"`
		Value   string  `json:"value"`
	}{"Lit", e.Kind, e.Value})
}

func (e *Lit) UnmarshalJSON(b []byte) error {
	var aux struct {
		LitKind LitKind `json:"litKind"`
		Value   string  `json:"value"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	e.Kind = aux.LitKind
	e.Value = aux.Value
	return nil
}

func (e *BinOp) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		Op   string `json:"op"`
		X    Expr   `json:"x"`
		Y    Expr   `json:"y"`
	}{"BinOp", e.Op, e.X, e.Y})
}

func (e *BinOp) UnmarshalJSON(b []byte) error {
	var aux struct {
		Op string          `json:"op"`
		X  json.RawMessage `json:"x"`
		Y  json.RawMessage `json:"y"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	e.Op = aux.Op
	x, err := unmarshalOptionalExpr(aux.X)
	if err != nil {
		return err
	}
	e.X = x
	y, err := unmarshalOptionalExpr(aux.Y)
	if err != nil {
		return err
	}
	e.Y = y
	return nil
}

func (e *UnaryOp) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		Op   string `json:"op"`
		X    Expr   `json:"x"`
	}{"UnaryOp", e.Op, e.X})
}

func (e *UnaryOp) UnmarshalJSON(b []byte) error {
	var aux struct {
		Op string          `json:"op"`
		X  json.RawMessage `json:"x"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	e.Op = aux.Op
	x, err := unmarshalOptionalExpr(aux.X)
	if err != nil {
		return err
	}
	e.X = x
	return nil
}

func (e *Selector) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		X    Expr   `json:"x"`
		Sel  string `json:"sel"`
	}{"Selector", e.X, e.Sel})
}

func (e *Selector) UnmarshalJSON(b []byte) error {
	var aux struct {
		X   json.RawMessage `json:"x"`
		Sel string          `json:"sel"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	x, err := unmarshalOptionalExpr(aux.X)
	if err != nil {
		return err
	}
	e.X = x
	e.Sel = aux.Sel
	return nil
}

// --- Types ---
//
// The four basic types carry no payload, so their JSON form is just
// `{"kind":"<TypeName>"}`. They have no UnmarshalJSON: the dispatcher
// in unmarshalType constructs them directly.

func (*IntType) MarshalJSON() ([]byte, error) {
	return []byte(`{"kind":"IntType"}`), nil
}

func (*StringType) MarshalJSON() ([]byte, error) {
	return []byte(`{"kind":"StringType"}`), nil
}

func (*BoolType) MarshalJSON() ([]byte, error) {
	return []byte(`{"kind":"BoolType"}`), nil
}

func (*Float64Type) MarshalJSON() ([]byte, error) {
	return []byte(`{"kind":"Float64Type"}`), nil
}

func (t *SliceType) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		Elem Type   `json:"elem"`
	}{"SliceType", t.Elem})
}

func (t *SliceType) UnmarshalJSON(b []byte) error {
	var aux struct {
		Elem json.RawMessage `json:"elem"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	if len(aux.Elem) == 0 || string(aux.Elem) == "null" {
		return fmt.Errorf("ir: SliceType missing elem")
	}
	elem, err := unmarshalType(aux.Elem)
	if err != nil {
		return err
	}
	t.Elem = elem
	return nil
}

// --- Slice / Index / Builtin expressions ---

func (e *SliceLit) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind  string `json:"kind"`
		Elem  Type   `json:"elem"`
		Elems []Expr `json:"elems"`
	}{"SliceLit", e.Elem, e.Elems})
}

func (e *SliceLit) UnmarshalJSON(b []byte) error {
	var aux struct {
		Elem  json.RawMessage   `json:"elem"`
		Elems []json.RawMessage `json:"elems"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	if len(aux.Elem) == 0 || string(aux.Elem) == "null" {
		return fmt.Errorf("ir: SliceLit missing elem")
	}
	elem, err := unmarshalType(aux.Elem)
	if err != nil {
		return err
	}
	e.Elem = elem
	elems, err := unmarshalExprList(aux.Elems)
	if err != nil {
		return err
	}
	e.Elems = elems
	return nil
}

func (e *IndexExpr) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind  string `json:"kind"`
		X     Expr   `json:"x"`
		Index Expr   `json:"index"`
	}{"IndexExpr", e.X, e.Index})
}

func (e *IndexExpr) UnmarshalJSON(b []byte) error {
	var aux struct {
		X     json.RawMessage `json:"x"`
		Index json.RawMessage `json:"index"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	x, err := unmarshalOptionalExpr(aux.X)
	if err != nil {
		return err
	}
	e.X = x
	idx, err := unmarshalOptionalExpr(aux.Index)
	if err != nil {
		return err
	}
	e.Index = idx
	return nil
}

func (e *SliceExpr) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		X    Expr   `json:"x"`
		Low  Expr   `json:"low"`
		High Expr   `json:"high"`
	}{"SliceExpr", e.X, e.Low, e.High})
}

func (e *SliceExpr) UnmarshalJSON(b []byte) error {
	var aux struct {
		X    json.RawMessage `json:"x"`
		Low  json.RawMessage `json:"low"`
		High json.RawMessage `json:"high"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	x, err := unmarshalOptionalExpr(aux.X)
	if err != nil {
		return err
	}
	e.X = x
	lo, err := unmarshalOptionalExpr(aux.Low)
	if err != nil {
		return err
	}
	e.Low = lo
	hi, err := unmarshalOptionalExpr(aux.High)
	if err != nil {
		return err
	}
	e.High = hi
	return nil
}

func (e *BuiltinCall) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind string `json:"kind"`
		Name string `json:"name"`
		Args []Expr `json:"args"`
	}{"BuiltinCall", e.Name, e.Args})
}

func (e *BuiltinCall) UnmarshalJSON(b []byte) error {
	var aux struct {
		Name string            `json:"name"`
		Args []json.RawMessage `json:"args"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	e.Name = aux.Name
	args, err := unmarshalExprList(aux.Args)
	if err != nil {
		return err
	}
	e.Args = args
	return nil
}

// --- Map type / literal / range statement ---

func (t *MapType) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind  string `json:"kind"`
		Key   Type   `json:"key"`
		Value Type   `json:"value"`
	}{"MapType", t.Key, t.Value})
}

func (t *MapType) UnmarshalJSON(b []byte) error {
	var aux struct {
		Key   json.RawMessage `json:"key"`
		Value json.RawMessage `json:"value"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	if len(aux.Key) == 0 || string(aux.Key) == "null" {
		return fmt.Errorf("ir: MapType missing key")
	}
	if len(aux.Value) == 0 || string(aux.Value) == "null" {
		return fmt.Errorf("ir: MapType missing value")
	}
	k, err := unmarshalType(aux.Key)
	if err != nil {
		return err
	}
	t.Key = k
	v, err := unmarshalType(aux.Value)
	if err != nil {
		return err
	}
	t.Value = v
	return nil
}

func (e *MapEntry) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind  string `json:"kind"`
		Key   Expr   `json:"key"`
		Value Expr   `json:"value"`
	}{"MapEntry", e.Key, e.Value})
}

func (e *MapEntry) UnmarshalJSON(b []byte) error {
	var aux struct {
		Key   json.RawMessage `json:"key"`
		Value json.RawMessage `json:"value"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	k, err := unmarshalOptionalExpr(aux.Key)
	if err != nil {
		return err
	}
	e.Key = k
	v, err := unmarshalOptionalExpr(aux.Value)
	if err != nil {
		return err
	}
	e.Value = v
	return nil
}

func (e *MapLit) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind    string      `json:"kind"`
		Key     Type        `json:"key"`
		Value   Type        `json:"value"`
		Entries []*MapEntry `json:"entries"`
	}{"MapLit", e.Key, e.Value, e.Entries})
}

func (e *MapLit) UnmarshalJSON(b []byte) error {
	var aux struct {
		Key     json.RawMessage `json:"key"`
		Value   json.RawMessage `json:"value"`
		Entries []*MapEntry     `json:"entries"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	if len(aux.Key) == 0 || string(aux.Key) == "null" {
		return fmt.Errorf("ir: MapLit missing key")
	}
	if len(aux.Value) == 0 || string(aux.Value) == "null" {
		return fmt.Errorf("ir: MapLit missing value")
	}
	k, err := unmarshalType(aux.Key)
	if err != nil {
		return err
	}
	e.Key = k
	v, err := unmarshalType(aux.Value)
	if err != nil {
		return err
	}
	e.Value = v
	e.Entries = aux.Entries
	return nil
}

func (s *RangeStmt) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Kind      string `json:"kind"`
		KeyName   string `json:"keyName"`
		ValueName string `json:"valueName"`
		Define    bool   `json:"define"`
		X         Expr   `json:"x"`
		Body      []Stmt `json:"body"`
	}{"RangeStmt", s.KeyName, s.ValueName, s.Define, s.X, s.Body})
}

func (s *RangeStmt) UnmarshalJSON(b []byte) error {
	var aux struct {
		KeyName   string            `json:"keyName"`
		ValueName string            `json:"valueName"`
		Define    bool              `json:"define"`
		X         json.RawMessage   `json:"x"`
		Body      []json.RawMessage `json:"body"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	s.KeyName = aux.KeyName
	s.ValueName = aux.ValueName
	s.Define = aux.Define
	x, err := unmarshalOptionalExpr(aux.X)
	if err != nil {
		return err
	}
	s.X = x
	body, err := unmarshalStmtList(aux.Body)
	if err != nil {
		return err
	}
	s.Body = body
	return nil
}
