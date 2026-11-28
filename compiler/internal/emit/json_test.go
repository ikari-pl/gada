package emit

import (
	"bytes"
	"strings"
	"testing"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// TestJsonStructMarshalUnmarshal pins the Phase 7 item-2b lowering:
// `json.Marshal(p)` / `json.Unmarshal(b, &q)` on a struct-typed local
// are rewritten to the generated `Json_Marshal_Point (P, B, Err);` /
// `Json_Unmarshal_Point (B, Q, Err);` procedures, which the emitter
// emits into Main's declarative part with per-field encoders/decoders.
func TestJsonStructMarshalUnmarshal(t *testing.T) {
	t.Parallel()
	point := &ir.TypeDecl{
		Name: "Point",
		Underlying: &ir.StructType{Fields: []*ir.StructField{
			{Name: "X", Type: &ir.IntType{}},
			{Name: "On", Type: &ir.BoolType{}},
			{Name: "R", Type: &ir.Float64Type{}},
		}},
	}
	pkg := &ir.Package{Name: "p", Files: []*ir.File{
		{Name: "x.go", Imports: []string{"encoding/json"}, Decls: []ir.Decl{
			point,
			funcMain(
				&ir.Assign{
					LHS:    []ir.Expr{idn("p")},
					Define: true,
					RHS: []ir.Expr{&ir.StructLit{
						TypeName: "Point",
						Fields: []*ir.StructLitField{
							{Name: "X", Value: litInt("3")},
							{Name: "On", Value: &ir.Lit{Kind: ir.LitBool, Value: "true"}},
							{Name: "R", Value: &ir.Lit{Kind: ir.LitFloat, Value: "1.5"}},
						},
					}},
				},
				&ir.Assign{
					LHS:    []ir.Expr{idn("b"), idn("err")},
					Define: true,
					RHS: []ir.Expr{&ir.Call{
						Fun:  &ir.Selector{X: idn("json"), Sel: "Marshal"},
						Args: []ir.Expr{idn("p")},
						ResultTypes: []ir.Type{
							&ir.SliceType{Elem: &ir.ByteType{}},
							&ir.ErrorType{},
						},
					}},
				},
				&ir.Assign{
					LHS:    []ir.Expr{idn("q")},
					Define: true,
					RHS:    []ir.Expr{&ir.ZeroVal{Type: &ir.NamedType{Name: "Point"}}},
				},
				&ir.Assign{
					LHS: []ir.Expr{idn("err")},
					RHS: []ir.Expr{&ir.Call{
						Fun:  &ir.Selector{X: idn("json"), Sel: "Unmarshal"},
						Args: []ir.Expr{idn("b"), idn("q")},
						ResultTypes: []ir.Type{
							&ir.ErrorType{},
						},
					}},
				},
			),
		}},
	}}
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	out := flattenSpaces(buf.String())
	for _, want := range []string{
		"procedure Json_Marshal_Point",
		"procedure Json_Unmarshal_Point",
		"Json_Marshal_Point (P, B, Err);",
		"Json_Unmarshal_Point (B, Q, Err);",
		"Gada.Std.Json.Encode_Int (V.X)",
		"Gada.Std.Json.Encode_Bool (V.On)",
		"Gada.Std.Json.Encode_Float (V.R)",
		"Gada.Std.Json.Parse_Object",
		`To_String (Mem.Key) = "X"`,
		"V.X := Integer (Mem.Val.I);",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
	// The generic overload must NOT be called for the struct operand.
	if strings.Contains(out, "Gada.Std.Json.Marshal (P") {
		t.Errorf("struct Marshal not rewritten:\n%s", out)
	}
}

// TestJsonStructUnsupportedField pins that a struct field of an
// unsupported kind (string — already rejected for record components,
// but belt-and-braces at the json layer) fails loudly at emit time.
func TestJsonStructUnsupportedField(t *testing.T) {
	t.Parallel()
	widget := &ir.TypeDecl{
		Name: "Widget",
		Underlying: &ir.StructType{Fields: []*ir.StructField{
			{Name: "Tag", Type: &ir.StringType{}},
		}},
	}
	pkg := &ir.Package{Name: "p", Files: []*ir.File{
		{Name: "x.go", Imports: []string{"encoding/json"}, Decls: []ir.Decl{
			widget,
			funcMain(
				&ir.Assign{
					LHS:    []ir.Expr{idn("w")},
					Define: true,
					RHS:    []ir.Expr{&ir.ZeroVal{Type: &ir.NamedType{Name: "Widget"}}},
				},
				&ir.Assign{
					LHS:    []ir.Expr{idn("b"), idn("err")},
					Define: true,
					RHS: []ir.Expr{&ir.Call{
						Fun:  &ir.Selector{X: idn("json"), Sel: "Marshal"},
						Args: []ir.Expr{idn("w")},
						ResultTypes: []ir.Type{
							&ir.SliceType{Elem: &ir.ByteType{}},
							&ir.ErrorType{},
						},
					}},
				},
			),
		}},
	}}
	var buf bytes.Buffer
	err := Package(pkg, &buf)
	if err == nil || (!strings.Contains(err.Error(), "unsupported type") &&
		!strings.Contains(err.Error(), "not yet supported")) {
		t.Fatalf("expected loud unsupported-field failure, got %v", err)
	}
}

// TestJsonStructCallArms exercises jsonStructCall's decline/edge arms
// directly: non-selector Fun, non-json package, wrong arity, non-ident
// arg, struct-literal arg, and non-struct named arg.
func TestJsonStructCallArms(t *testing.T) {
	t.Parallel()
	e := &emitter{
		stdlibImports: map[string]string{"json": "Gada.Std.Json"},
		localTypes:    map[string]ir.Type{"p": &ir.NamedType{Name: "Point"}},
		structByName:  map[string]*ir.StructType{"Point": {}},
	}
	call := func(fun ir.Expr, args ...ir.Expr) *ir.Call {
		return &ir.Call{Fun: fun, Args: args}
	}
	sel := func(name string) ir.Expr {
		return &ir.Selector{X: idn("json"), Sel: name}
	}
	// happy path: ident with struct type
	if _, m, ok := e.jsonStructCall(call(sel("Marshal"), idn("p"))); !ok || !m {
		t.Errorf("Marshal(p) not detected")
	}
	if _, m, ok := e.jsonStructCall(call(sel("Unmarshal"), idn("b"), idn("p"))); !ok || m {
		t.Errorf("Unmarshal(b, p) not detected")
	}
	// struct literal arg
	if _, _, ok := e.jsonStructCall(call(sel("Marshal"),
		&ir.StructLit{TypeName: "Point"})); !ok {
		t.Errorf("Marshal(Point{...}) not detected")
	}
	// decline arms
	if _, _, ok := e.jsonStructCall(call(idn("f"), idn("p"))); ok {
		t.Errorf("non-selector Fun accepted")
	}
	if _, _, ok := e.jsonStructCall(call(&ir.Selector{X: idn("fmt"), Sel: "Println"}, idn("p"))); ok {
		t.Errorf("non-json package accepted")
	}
	if _, _, ok := e.jsonStructCall(call(sel("Marshal"))); ok {
		t.Errorf("wrong arity accepted")
	}
	if _, _, ok := e.jsonStructCall(call(sel("Encode"), idn("p"))); ok {
		t.Errorf("unknown member accepted")
	}
	if _, _, ok := e.jsonStructCall(call(sel("Marshal"), idn("b"))); ok {
		t.Errorf("non-struct ident accepted")
	}
}

// TestJsonStructWalkArms pins that the item-2b pre-pass walks nested
// statements (if/for/defer/go) and emits a marshaler per struct type.
func TestJsonStructWalkArms(t *testing.T) {
	t.Parallel()
	mk := func(name string) *ir.TypeDecl {
		return &ir.TypeDecl{Name: name, Underlying: &ir.StructType{
			Fields: []*ir.StructField{{Name: "X", Type: &ir.IntType{}}},
		}}
	}
	pkg := &ir.Package{Name: "p", Files: []*ir.File{
		{Name: "x.go", Imports: []string{"encoding/json"}, Decls: []ir.Decl{
			mk("Point"),
			mk("Size"),
			funcMain(
				&ir.Assign{
					LHS:    []ir.Expr{idn("p")},
					Define: true,
					RHS:    []ir.Expr{&ir.ZeroVal{Type: &ir.NamedType{Name: "Point"}}},
				},
				&ir.Assign{
					LHS:    []ir.Expr{idn("s")},
					Define: true,
					RHS:    []ir.Expr{&ir.ZeroVal{Type: &ir.NamedType{Name: "Size"}}},
				},
				&ir.Assign{
					LHS:    []ir.Expr{idn("b"), idn("err")},
					Define: true,
					RHS: []ir.Expr{&ir.Call{
						Fun:  &ir.Selector{X: idn("json"), Sel: "Marshal"},
						Args: []ir.Expr{idn("p")},
						ResultTypes: []ir.Type{
							&ir.SliceType{Elem: &ir.ByteType{}}, &ir.ErrorType{},
						},
					}},
				},
				&ir.If{
					Cond: &ir.BinOp{Op: "==", X: idn("err"), Y: &ir.Lit{Kind: ir.LitInt, Value: "0"}},
					Then: []ir.Stmt{&ir.Assign{
						LHS: []ir.Expr{idn("b2"), idn("err2")},
						RHS: []ir.Expr{&ir.Call{
							Fun:  &ir.Selector{X: idn("json"), Sel: "Marshal"},
							Args: []ir.Expr{idn("s")},
							ResultTypes: []ir.Type{
								&ir.SliceType{Elem: &ir.ByteType{}},
								&ir.ErrorType{},
							},
						}},
					}},
				},
				&ir.For{
					Body: []ir.Stmt{
						&ir.ExprStmt{X: &ir.Call{
							Fun:  &ir.Selector{X: idn("json"), Sel: "Unmarshal"},
							Args: []ir.Expr{idn("b"), idn("p")},
						}},
					},
				},
			),
		}},
	}}
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	out := flattenSpaces(buf.String())
	for _, want := range []string{
		"procedure Json_Marshal_Point",
		"procedure Json_Marshal_Size",
		"Json_Marshal_Point (P, B, Err);",
		"Json_Marshal_Size (S, B2, Err2);",
		"Json_Unmarshal_Point (B, P, Err);",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}
