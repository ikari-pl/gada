package emit

import (
	"bytes"
	"strings"
	"testing"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// strSlice is []string in IR.
func strSlice() *ir.SliceType { return &ir.SliceType{Elem: &ir.StringType{}} }

// emitMain runs Package over a main (with the given imports) and
// returns the output with whitespace flattened (survives the 80-col
// wrapper).
func emitMain(t *testing.T, imports []string, body ...ir.Stmt) string {
	t.Helper()
	pkg := &ir.Package{Name: "p", Files: []*ir.File{
		{Name: "x.go", Imports: imports, Decls: []ir.Decl{funcMain(body...)}},
	}}
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	return flattenSpaces(buf.String())
}

// TestStdlibOutCallEmit pins the 2-LHS (T, error) out-call lowering:
// bare decls in the declarative region, the call statement first in
// the body, and dependent := initialisers deferred after it in source
// order.
func TestStdlibOutCallEmit(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"os"},
		&ir.Assign{
			LHS:    []ir.Expr{idn("data"), idn("err")},
			Define: true,
			RHS: []ir.Expr{&ir.Call{
				Fun:  &ir.Selector{X: idn("os"), Sel: "ReadFile"},
				Args: []ir.Expr{&ir.Lit{Kind: ir.LitString, Value: `"f.txt"`}},
				ResultTypes: []ir.Type{
					&ir.SliceType{Elem: &ir.ByteType{}},
					&ir.ErrorType{},
				},
			}},
		},
		&ir.Assign{
			LHS:    []ir.Expr{idn("text")},
			Define: true,
			RHS: []ir.Expr{&ir.BuiltinCall{
				Name: "string",
				Args: []ir.Expr{idn("data")},
			}},
		},
		&ir.If{
			Cond: &ir.BinOp{Op: "!=", X: idn("err"), Y: &ir.Lit{Kind: ir.LitNil}},
			Then: []ir.Stmt{&ir.Return{}},
		},
	)
	for _, want := range []string{
		"Data : Gada.Std.Bytes.Byte_Slice := Gada.Std.Bytes.Byte_Vectors.Empty;",
		"Err : Gada.Std.Errors.Error_Access;",
		`Text : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.To_Unbounded_String ("");`,
		`Text := Ada.Strings.Unbounded.To_Unbounded_String (Gada.Std.Bytes.To_String (Data));`,
		`Gada.Std.OS.Read_File ("f.txt", Data, Err);`,
		"if Err /= null then",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
	// Source order: the out-call must precede the deferred init.
	if strings.Index(out, "Read_File (") > strings.Index(out, "Text :=") {
		t.Errorf("out-call must be drained before dependent inits:\n%s", out)
	}
}

// TestStringSliceEmit pins the []string → String_Vectors lowering:
// index reads wrap in To_String, assigns use Replace_Element with
// To_Unbounded_String, len wraps in Integer, and the var decl uses
// the String_Slice subtype.
func TestStringSliceEmit(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"strings"},
		&ir.Assign{
			LHS:    []ir.Expr{idn("words")},
			Define: true,
			RHS: []ir.Expr{&ir.Call{
				Fun:         &ir.Selector{X: idn("strings"), Sel: "Fields"},
				Args:        []ir.Expr{idn("text")},
				ResultTypes: []ir.Type{strSlice()},
			}},
		},
		&ir.Assign{
			LHS:    []ir.Expr{idn("n")},
			Define: true,
			RHS:    []ir.Expr{&ir.BuiltinCall{Name: "len", Args: []ir.Expr{idn("words")}}},
		},
		&ir.Assign{
			LHS:    []ir.Expr{idn("w")},
			Define: true,
			RHS:    []ir.Expr{&ir.IndexExpr{X: idn("words"), Index: litInt("0")}},
		},
		&ir.Assign{
			LHS: []ir.Expr{&ir.IndexExpr{X: idn("words"), Index: litInt("0")}},
			RHS: []ir.Expr{idn("w")},
		},
	)
	for _, want := range []string{
		"Words : Gada.Std.Strings.String_Slice := Gada.Std.Strings.Fields (Text);",
		"N : Integer := Integer (Gada.Std.Strings.String_Vectors.Length (Words));",
		"W : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.To_Unbounded_String (Ada.Strings.Unbounded.To_String (Gada.Std.Strings.String_Vectors.Element (Words, 0 + 1)));",
		"Gada.Std.Strings.String_Vectors.Replace_Element (Words, 0 + 1, Ada.Strings.Unbounded.To_Unbounded_String (Ada.Strings.Unbounded.To_String (W)));",
		"with Ada.Strings.Unbounded;",
		"with Gada.Std.Strings;",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// TestStringSliceVectorBuiltinsRejected pins the loud failures for
// cap/append on vector-backed slices and non-empty []string literals.
func TestStringSliceVectorBuiltinsRejected(t *testing.T) {
	t.Parallel()
	mk := func(rhs ir.Expr) *ir.Package {
		return &ir.Package{Name: "p", Files: []*ir.File{
			{Name: "x.go", Imports: []string{"strings"}, Decls: []ir.Decl{funcMain(
				&ir.Assign{
					LHS: []ir.Expr{idn("words")}, Define: true,
					RHS: []ir.Expr{&ir.Call{
						Fun:         &ir.Selector{X: idn("strings"), Sel: "Fields"},
						Args:        []ir.Expr{idn("text")},
						ResultTypes: []ir.Type{strSlice()},
					}},
				},
				&ir.Assign{
					LHS: []ir.Expr{idn("x")}, Define: true, RHS: []ir.Expr{rhs},
				},
			)}},
		}}
	}
	cases := []struct {
		name string
		rhs  ir.Expr
		want string
	}{
		{"cap", &ir.BuiltinCall{Name: "cap", Args: []ir.Expr{idn("words")}}, "cap on a []string/[]byte vector"},
		{"append", &ir.BuiltinCall{Name: "append", Args: []ir.Expr{idn("words"), idn("w")}}, "append on a []string/[]byte vector"},
		{"lit", &ir.SliceLit{Elem: &ir.StringType{}, Elems: []ir.Expr{
			&ir.Lit{Kind: ir.LitString, Value: `"a"`},
		}}, "composite literal of []string/[]byte not supported"},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			var buf bytes.Buffer
			err := Package(mk(tc.rhs), &buf)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("err = %v, want substring %q", err, tc.want)
			}
		})
	}
}

// TestRefsDeferred pins the transitive deferral detection.
func TestRefsDeferred(t *testing.T) {
	t.Parallel()
	e := newEmitter("p", &ir.File{})
	e.deferredDecls = map[string]bool{"data": true}
	if !e.refsDeferred(idn("data")) {
		t.Error("direct ident should be deferred")
	}
	if !e.refsDeferred(&ir.BinOp{Op: "+", X: idn("n"), Y: idn("data")}) {
		t.Error("nested binop should be deferred")
	}
	if !e.refsDeferred(&ir.Call{Fun: idn("f"), Args: []ir.Expr{
		&ir.IndexExpr{X: idn("data"), Index: litInt("0")},
	}}) {
		t.Error("call arg referencing deferred should defer")
	}
	if e.refsDeferred(&ir.BinOp{Op: "+", X: idn("n"), Y: litInt("1")}) {
		t.Error("no deferred names → not deferred")
	}
	if e.refsDeferred(nil) {
		t.Error("nil expr → not deferred")
	}
}

// TestErrorTypeName pins ErrorType/ByteType typeName mappings.
func TestErrorTypeName(t *testing.T) {
	t.Parallel()
	e := newEmitter("p", &ir.File{})
	if got, _ := e.typeName(&ir.ErrorType{}); got != "Gada.Std.Errors.Error_Access" {
		t.Errorf("ErrorType typeName = %q", got)
	}
	if got, _ := e.typeName(&ir.ByteType{}); got != "Character" {
		t.Errorf("ByteType typeName = %q", got)
	}
	if got, _ := e.typeName(&ir.SliceType{Elem: &ir.ByteType{}}); got != "Gada.Std.Bytes.Byte_Slice" {
		t.Errorf("[]byte typeName = %q", got)
	}
}

// TestStdlibEdgeBranches covers the remaining error/edge arms of the
// new emit paths: out-call with a non-ident LHS, refsDeferred over all
// node kinds, sliceElemForExpr on non-idents, and append of an unknown
// slice type.
func TestStdlibEdgeBranches(t *testing.T) {
	t.Parallel()

	// Out-call with a non-ident LHS fails loudly.
	var buf bytes.Buffer
	err := Package(&ir.Package{Name: "p", Files: []*ir.File{
		{Name: "x.go", Imports: []string{"os"}, Decls: []ir.Decl{funcMain(
			&ir.Assign{
				LHS:    []ir.Expr{&ir.IndexExpr{X: idn("a"), Index: litInt("0")}, idn("err")},
				Define: true,
				RHS: []ir.Expr{&ir.Call{
					Fun:  &ir.Selector{X: idn("os"), Sel: "ReadFile"},
					Args: []ir.Expr{idn("p")},
					ResultTypes: []ir.Type{
						&ir.SliceType{Elem: &ir.ByteType{}},
						&ir.ErrorType{},
					},
				}},
			},
		)}},
	}}, &buf)
	if err == nil || !strings.Contains(err.Error(), "plain identifiers") {
		t.Fatalf("non-ident out-call LHS: err = %v", err)
	}

	// refsDeferred over every node kind.
	e := newEmitter("p", &ir.File{})
	e.deferredDecls = map[string]bool{"d": true}
	deep := []ir.Expr{
		&ir.UnaryOp{Op: "-", X: idn("d")},
		&ir.Selector{X: idn("d"), Sel: "F"},
		&ir.SliceLit{Elem: &ir.IntType{}, Elems: []ir.Expr{idn("d")}},
		&ir.MapLit{Key: &ir.IntType{}, Value: &ir.IntType{}, Entries: []*ir.MapEntry{
			{Key: litInt("1"), Value: idn("d")},
		}},
		&ir.StructLit{TypeName: "S", Fields: []*ir.StructLitField{{Name: "F", Value: idn("d")}}},
		&ir.MakeChan{Elem: &ir.IntType{}, Capacity: idn("d")},
		&ir.TypeAssert{X: idn("d"), Type: &ir.IntType{}},
		&ir.SliceExpr{X: idn("d"), Low: litInt("0"), High: idn("d")},
		&ir.ChanRecv{Chan: idn("d")},
	}
	for i, x := range deep {
		if !e.refsDeferred(x) {
			t.Errorf("refsDeferred(deep[%d] %T) = false, want true", i, x)
		}
	}

	// sliceElemForExpr: non-ident and non-slice misses.
	if _, ok := e.sliceElemForExpr(litInt("1")); ok {
		t.Error("lit arg should miss")
	}
	e.localTypes = map[string]ir.Type{"n": &ir.IntType{}}
	if _, ok := e.sliceElemForExpr(idn("n")); ok {
		t.Error("int-typed ident should miss")
	}

	// append of an unknown slice type fails at decl inference.
	buf.Reset()
	err = Package(wrapPkg(funcMain(
		&ir.Assign{LHS: []ir.Expr{idn("x")}, Define: true,
			RHS: []ir.Expr{&ir.BuiltinCall{Name: "append", Args: []ir.Expr{idn("u"), idn("v")}}}},
	)), &buf)
	if err == nil || !strings.Contains(err.Error(), "append of unknown slice") {
		t.Fatalf("append unknown: err = %v", err)
	}
}

// TestBuiltinAndInferErrorArms covers the error arms of the builtin
// dispatcher and decl-type inference that the happy-path tests miss.
func TestBuiltinAndInferErrorArms(t *testing.T) {
	t.Parallel()
	e := newEmitter("p", &ir.File{})
	e.localTypes = map[string]ir.Type{"b": &ir.SliceType{Elem: &ir.ByteType{}}}

	errCases := []struct {
		name string
		call *ir.BuiltinCall
		want string
	}{
		{"string arity", &ir.BuiltinCall{Name: "string", Args: []ir.Expr{idn("a"), idn("b")}}, "string() takes exactly 1 arg"},
		{"string non-byte", &ir.BuiltinCall{Name: "string", Args: []ir.Expr{idn("n")}}, "supported only for []byte"},
		{"len arity", &ir.BuiltinCall{Name: "len", Args: []ir.Expr{idn("s"), idn("s")}}, "len takes exactly 1 arg"},
		{"cap arity", &ir.BuiltinCall{Name: "cap", Args: []ir.Expr{idn("s"), idn("s")}}, "cap takes exactly 1 arg"},
		{"append arity", &ir.BuiltinCall{Name: "append", Args: []ir.Expr{idn("s")}}, "append-of-N"},
		{"delete arity", &ir.BuiltinCall{Name: "delete", Args: []ir.Expr{idn("m")}}, "delete takes exactly 2 args"},
		{"recover args", &ir.BuiltinCall{Name: "recover", Args: []ir.Expr{idn("x")}}, "recover takes no args"},
		{"panic expr", &ir.BuiltinCall{Name: "panic", Args: []ir.Expr{idn("x")}}, "panic in expression position"},
		{"unknown", &ir.BuiltinCall{Name: "copy", Args: []ir.Expr{idn("x")}}, "not supported"},
	}
	for _, tc := range errCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			e := newEmitter("p", &ir.File{})
			e.localTypes = map[string]ir.Type{
				"b": &ir.SliceType{Elem: &ir.ByteType{}},
				"s": &ir.SliceType{Elem: &ir.IntType{}},
				"m": &ir.MapType{Key: &ir.IntType{}, Value: &ir.IntType{}},
				"n": &ir.IntType{},
			}
			got := e.emitBuiltinCall(tc.call)
			if e.err == nil || !strings.Contains(e.err.Error(), tc.want) {
				t.Fatalf("err = %v (got %q), want substring %q", e.err, got, tc.want)
			}
		})
	}

	// inferDeclType error arms.
	if _, err := e.inferDeclType(&ir.Call{}); err == nil {
		t.Error("Call without ResultTypes should fail")
	}
	if _, err := e.inferDeclType(&ir.IndexExpr{X: idn("unknown")}); err == nil {
		t.Error("IndexExpr of unknown slice should fail")
	}
	if _, err := e.inferDeclType(&ir.BuiltinCall{Name: "copy"}); err == nil {
		t.Error("unknown builtin should fail")
	}
}

// TestDeclInitHelpers pins the bare-decl initializer rules:
// vector-backed slices get their empty vector, String gets "", others
// get none.
func TestDeclInitHelpers(t *testing.T) {
	t.Parallel()
	if got := vectorEmptyInit(&ir.SliceType{Elem: &ir.StringType{}}); got != "Gada.Std.Strings.String_Vectors.Empty" {
		t.Errorf("vectorEmptyInit([]string) = %q", got)
	}
	if got := vectorEmptyInit(&ir.SliceType{Elem: &ir.ByteType{}}); got != "Gada.Std.Bytes.Byte_Vectors.Empty" {
		t.Errorf("vectorEmptyInit([]byte) = %q", got)
	}
	if got := vectorEmptyInit(&ir.SliceType{Elem: &ir.IntType{}}); got != "" {
		t.Errorf("vectorEmptyInit([]int) = %q, want empty", got)
	}
	if got := declInit(&ir.StringType{}); got != "" {
		t.Errorf("declInit(string) = %q (string locals are Unbounded_String; handled by emitVarDecl)", got)
	}
	if got := declInit(&ir.IntType{}); got != "" {
		t.Errorf("declInit(int) = %q, want empty", got)
	}
	e := newEmitter("p", &ir.File{})
	if got := e.rhsIRType(&ir.BuiltinCall{Name: "string"}); got == nil || got.NodeKind() != "StringType" {
		t.Errorf("rhsIRType(string()) = %#v", got)
	}
	if got := e.rhsIRType(&ir.SliceLit{Elem: &ir.IntType{}}); got == nil || got.NodeKind() != "SliceType" {
		t.Errorf("rhsIRType(slicelit) = %#v", got)
	}
	if got := e.rhsIRType(&ir.BuiltinCall{Name: "len"}); got == nil || got.NodeKind() != "IntType" {
		t.Errorf("rhsIRType(len) = %#v", got)
	}
}

// TestRhsIRTypeMisses pins rhsIRType's nil returns for shapes without
// a statically known type.
func TestRhsIRTypeMisses(t *testing.T) {
	t.Parallel()
	e := newEmitter("p", &ir.File{})
	if got := e.rhsIRType(&ir.Call{}); got != nil {
		t.Errorf("rhsIRType(call no results) = %#v, want nil", got)
	}
	if got := e.rhsIRType(&ir.IndexExpr{X: idn("unknown")}); got != nil {
		t.Errorf("rhsIRType(index of unknown) = %#v, want nil", got)
	}
	if got := e.rhsIRType(&ir.BuiltinCall{Name: "recover"}); got != nil {
		t.Errorf("rhsIRType(recover) = %#v, want nil", got)
	}
	// Out-call decl with a nil result type fails loudly.
	var buf bytes.Buffer
	err := Package(&ir.Package{Name: "p", Files: []*ir.File{
		{Name: "x.go", Imports: []string{"os"}, Decls: []ir.Decl{funcMain(
			&ir.Assign{
				LHS: []ir.Expr{idn("a"), idn("b")}, Define: true,
				RHS: []ir.Expr{&ir.Call{
					Fun:  &ir.Selector{X: idn("os"), Sel: "ReadFile"},
					Args: []ir.Expr{idn("p")},
					ResultTypes: []ir.Type{
						&ir.SliceType{Elem: &ir.ByteType{}}, nil,
					},
				}},
			},
		)}},
	}}, &buf)
	if err == nil || !strings.Contains(err.Error(), "known result types") {
		t.Fatalf("nil result type: err = %v", err)
	}
}

// TestUnboundedStringAssignEmit pins the local-string-variable
// lowering: head `w := "a"` declares W as Unbounded_String, and a later
// `w = "b"` assigns the bare l-value (never `To_String (W) := ...`)
// with the RHS wrapped back into Unbounded_String.
func TestUnboundedStringAssignEmit(t *testing.T) {
	t.Parallel()
	out := emitMain(t, nil,
		&ir.Assign{
			LHS:    []ir.Expr{idn("w")},
			Define: true,
			RHS:    []ir.Expr{&ir.Lit{Kind: ir.LitString, Value: `"a"`}},
		},
		&ir.Assign{
			LHS: []ir.Expr{idn("w")},
			RHS: []ir.Expr{&ir.Lit{Kind: ir.LitString, Value: `"b"`}},
		},
	)
	for _, want := range []string{
		"W : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.To_Unbounded_String (\"a\");",
		"W := Ada.Strings.Unbounded.To_Unbounded_String (\"b\");",
		"with Ada.Strings.Unbounded;",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
	if strings.Contains(out, "To_String (W) :=") {
		t.Errorf("assignment LHS must stay a bare l-value:\n%s", out)
	}
}

// TestStdlibOutCallStringResultEmit pins the 2-LHS out-call whose first
// result is a string: the target is declared as Unbounded_String so the
// out-param write is not length-constrained.
func TestStdlibOutCallStringResultEmit(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"os"},
		&ir.Assign{
			LHS:    []ir.Expr{idn("s"), idn("err")},
			Define: true,
			RHS: []ir.Expr{&ir.Call{
				Fun:  &ir.Selector{X: idn("os"), Sel: "ReadFile"},
				Args: []ir.Expr{&ir.Lit{Kind: ir.LitString, Value: `"f.txt"`}},
				ResultTypes: []ir.Type{
					&ir.StringType{},
					&ir.ErrorType{},
				},
			}},
		},
	)
	for _, want := range []string{
		"S : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.To_Unbounded_String (\"\");",
		"Err : Gada.Std.Errors.Error_Access;",
		"Gada.Std.OS.Read_File (\"f.txt\", S, Err);",
		"with Ada.Strings.Unbounded;",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// TestAliasedStdlibImport is the regression test for PR #45 review #13:
// `import str "strings"; str.ToUpper(s)` must lower through the alias
// (the emitter used to key stdlib imports by path segment only, so the
// call fell through to the method-call path).
func TestAliasedStdlibImport(t *testing.T) {
	t.Parallel()
	pkg := &ir.Package{Name: "p", Files: []*ir.File{{
		Name:    "x.go",
		Imports: []string{"strings"},
		Aliases: map[string]string{"strings": "str"},
		Decls: []ir.Decl{funcMain(
			&ir.Assign{
				LHS:    []ir.Expr{idn("u")},
				Define: true,
				RHS: []ir.Expr{&ir.Call{
					Fun:         &ir.Selector{X: idn("str"), Sel: "ToUpper"},
					Args:        []ir.Expr{&ir.Lit{Kind: ir.LitString, Value: `"go"`}},
					ResultTypes: []ir.Type{&ir.StringType{}},
				}},
			},
			&ir.Call{
				Fun:  &ir.Selector{X: idn("str"), Sel: "Contains"},
				Args: []ir.Expr{idn("u"), &ir.Lit{Kind: ir.LitString, Value: `"G"`}},
			},
		)},
	}}}
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	out := flattenSpaces(buf.String())
	for _, want := range []string{
		"with Gada.Std.Strings;",
		`Gada.Std.Strings.To_Upper ("go")`,
		`Gada.Std.Strings.Contains (`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
	if strings.Contains(out, "Str.") {
		t.Errorf("alias leaked into the Ada output:\n%s", out)
	}
}

// TestUnsupportedImportForms pins the loud rejections that keep aliased
// imports from silently miscompiling: a renamed fmt (whose Println
// special case matches the literal `fmt` prefix) and dot imports.
func TestUnsupportedImportForms(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		imp, alias, want string
	}{
		{"fmt", "f", `renamed import of "fmt"`},
		{"strings", ".", "dot import"},
	} {
		pkg := &ir.Package{Name: "p", Files: []*ir.File{{
			Name: "x.go", Imports: []string{c.imp},
			Aliases: map[string]string{c.imp: c.alias},
			Decls:   []ir.Decl{funcMain()},
		}}}
		var buf bytes.Buffer
		err := Package(pkg, &buf)
		if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("import %s %q: err = %v, want %q", c.alias, c.imp, err, c.want)
		}
	}
}

// TestErrorWithClauseFromBoundErrors is the regression test for PR #45
// review #3: a strconv-only program binding `n, err := strconv.Atoi(s)`
// names Gada.Std.Errors.Error_Access, so it needs the with/use type
// clause even though neither os nor errors is imported. The same holds
// for an `error` in a function signature.
func TestErrorWithClauseFromBoundErrors(t *testing.T) {
	t.Parallel()
	const with = "with Gada.Std.Errors; use type Gada.Std.Errors.Error_Access;"
	out := emitMain(t, []string{"strconv"},
		&ir.Assign{
			LHS:    []ir.Expr{idn("n"), idn("err")},
			Define: true,
			RHS: []ir.Expr{&ir.Call{
				Fun:         &ir.Selector{X: idn("strconv"), Sel: "Atoi"},
				Args:        []ir.Expr{&ir.Lit{Kind: ir.LitString, Value: `"12"`}},
				ResultTypes: []ir.Type{&ir.IntType{}, &ir.ErrorType{}},
			}},
		},
		&ir.If{
			Cond: &ir.BinOp{Op: "!=", X: idn("err"), Y: &ir.Lit{Kind: ir.LitNil}},
			Then: []ir.Stmt{&ir.Return{}},
		},
	)
	if !strings.Contains(out, with) {
		t.Errorf("strconv-only Atoi: missing %q in:\n%s", with, out)
	}
	if !strings.Contains(out, `Gada.Std.Strconv.Atoi ("12", N, Err);`) {
		t.Errorf("missing the out-call in:\n%s", out)
	}

	// No imports at all: `func check() error` alone needs the clause.
	pkg := &ir.Package{Name: "p", Files: []*ir.File{{
		Name: "x.go",
		Decls: []ir.Decl{&ir.Function{
			Name:    "check",
			Results: []*ir.Param{{Type: &ir.ErrorType{}}},
			Body:    []ir.Stmt{&ir.Return{Results: []ir.Expr{&ir.Lit{Kind: ir.LitNil}}}},
		}},
	}}}
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	if !strings.Contains(flattenSpaces(buf.String()), with) {
		t.Errorf("error result: missing %q in:\n%s", with, buf.String())
	}
}

// TestBlankOutCallLHS is the regression test for PR #45 review #10:
// `n, _ := strconv.Atoi(s)` / `_, err := os.ReadFile(p)` emitted `_`
// as an Ada identifier ("identifier cannot start with underline"). Each
// blank gets its own Discard_N local in its out position.
func TestBlankOutCallLHS(t *testing.T) {
	t.Parallel()
	atoi := func(lhs ...ir.Expr) *ir.Assign {
		return &ir.Assign{
			LHS:    lhs,
			Define: true,
			RHS: []ir.Expr{&ir.Call{
				Fun:         &ir.Selector{X: idn("strconv"), Sel: "Atoi"},
				Args:        []ir.Expr{&ir.Lit{Kind: ir.LitString, Value: `"7"`}},
				ResultTypes: []ir.Type{&ir.IntType{}, &ir.ErrorType{}},
			}},
		}
	}
	out := emitMain(t, []string{"strconv"},
		atoi(idn("n"), idn("_")),
		atoi(idn("_"), idn("err")),
		&ir.Assign{
			LHS:    []ir.Expr{idn("_"), idn("q")},
			Define: true,
			RHS: []ir.Expr{&ir.Call{
				Fun:         &ir.Selector{X: idn("strconv"), Sel: "Unquote"},
				Args:        []ir.Expr{&ir.Lit{Kind: ir.LitString, Value: `"x"`}},
				ResultTypes: []ir.Type{&ir.StringType{}, &ir.ErrorType{}},
			}},
		},
	)
	for _, want := range []string{
		"Discard_1 : Gada.Std.Errors.Error_Access;",
		`Gada.Std.Strconv.Atoi ("7", N, Discard_1);`,
		"Discard_2 : Integer;",
		`Gada.Std.Strconv.Atoi ("7", Discard_2, Err);`,
		`Discard_3 : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.To_Unbounded_String ("");`,
		`Gada.Std.Strconv.Unquote ("x", Discard_3, Q);`,
		"with Ada.Strings.Unbounded;",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
	if strings.Contains(out, " _ ") || strings.Contains(out, ", _") {
		t.Errorf("blank identifier leaked into Ada:\n%s", out)
	}
}
