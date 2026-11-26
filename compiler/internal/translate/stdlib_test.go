package translate

import (
	"go/ast"
	"go/parser"
	"go/token"
	"go/types"
	"testing"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// parseSrc parses a one-file package and translates it with the given
// types.Info (nil for the parser-only corpus path).
func parseSrc(t *testing.T, src string, info *types.Info) *ir.Package {
	t.Helper()
	fset := token.NewFileSet()
	af, err := parser.ParseFile(fset, "x.go", src, parser.AllErrors)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	pkg, err := File(af, info)
	if err != nil {
		t.Fatalf("translate: %v", err)
	}
	return pkg
}

// TestStdlibCallExpression pins the Phase 5 wave-1 lowering: a
// stdlib-qualified call in expression position becomes an *ir.Call
// with a Selector Fun and fallback ResultTypes (parser-only path).
func TestStdlibCallExpression(t *testing.T) {
	t.Parallel()
	pkg := parseSrc(t, `package p

import (
	"os"
	"strings"
)

func f(path string) {
	data, err := os.ReadFile(path)
	words := strings.Fields(string(data))
	_ = words
	_ = err
}
`, nil)
	fn := pkg.Files[0].Decls[0].(*ir.Function)
	// Head decls: the 2-LHS out-call and the 1-LHS call.
	a0 := fn.Body[0].(*ir.Assign)
	if len(a0.LHS) != 2 || len(a0.RHS) != 1 {
		t.Fatalf("decl0 shape = %d/%d", len(a0.LHS), len(a0.RHS))
	}
	c0, ok := a0.RHS[0].(*ir.Call)
	if !ok {
		t.Fatalf("decl0 RHS = %T, want *ir.Call", a0.RHS[0])
	}
	sel, ok := c0.Fun.(*ir.Selector)
	if !ok || sel.Sel != "ReadFile" {
		t.Fatalf("call fun = %#v", c0.Fun)
	}
	if len(c0.ResultTypes) != 2 ||
		c0.ResultTypes[0].NodeKind() != "SliceType" ||
		c0.ResultTypes[1].NodeKind() != "ErrorType" {
		t.Fatalf("ReadFile ResultTypes = %#v", c0.ResultTypes)
	}
	a1 := fn.Body[1].(*ir.Assign)
	c1 := a1.RHS[0].(*ir.Call)
	if sel, ok := c1.Fun.(*ir.Selector); !ok || sel.Sel != "Fields" {
		t.Fatalf("decl1 fun = %#v", c1.Fun)
	}
	if len(c1.ResultTypes) != 1 || c1.ResultTypes[0].NodeKind() != "SliceType" {
		t.Fatalf("Fields ResultTypes = %#v", c1.ResultTypes)
	}
	// string(data) is a builtin conversion, not a Call.
	if _, ok := c1.Args[0].(*ir.BuiltinCall); !ok {
		t.Fatalf("Fields arg = %T, want *ir.BuiltinCall (string conversion)", c1.Args[0])
	}
}

// TestStdlibCallRejectsNonStdlib pins that selector calls on
// non-stdlib prefixes still fall through to the loud error.
func TestStdlibCallRejectsNonStdlib(t *testing.T) {
	t.Parallel()
	_, err := func() (*ir.Package, error) {
		fset := token.NewFileSet()
		af, perr := parser.ParseFile(fset, "x.go", `package p

func f(x int) int {
	return x
}

func g() {
	f(f(1))
}
`, parser.AllErrors)
		if perr != nil {
			t.Fatalf("parse: %v", perr)
		}
		return File(af, nil)
	}()
	if err == nil {
		t.Fatal("expected general call-as-expression error")
	}
}

// TestNilIdent pins the nil literal lowering.
func TestNilIdent(t *testing.T) {
	t.Parallel()
	got := transIdent(&ast.Ident{Name: "nil"})
	lit, ok := got.(*ir.Lit)
	if !ok || lit.Kind != ir.LitNil {
		t.Fatalf("transIdent(nil) = %#v, want Lit nil", got)
	}
}

// TestGoTypesToIR covers the go/types → IR conversion used for call
// result types, including tuples, slices, and the named error type.
func TestGoTypesToIR(t *testing.T) {
	t.Parallel()
	errType := types.Universe.Lookup("error").Type()
	cases := []struct {
		name string
		t    types.Type
		want string // NodeKind of first result
	}{
		{"int", types.Typ[types.Int], "IntType"},
		{"string", types.Typ[types.String], "StringType"},
		{"bool", types.Typ[types.Bool], "BoolType"},
		{"float64", types.Typ[types.Float64], "Float64Type"},
		{"byte", types.Typ[types.Byte], "ByteType"},
		{"[]string", types.NewSlice(types.Typ[types.String]), "SliceType"},
		{"[]byte", types.NewSlice(types.Typ[types.Byte]), "SliceType"},
		{"error", errType, "ErrorType"},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			rts := goTypesToIR(tc.t)
			if len(rts) != 1 || rts[0] == nil || rts[0].NodeKind() != tc.want {
				t.Fatalf("goTypesToIR(%s) = %#v, want 1 result of kind %s", tc.name, rts, tc.want)
			}
		})
	}
	// Tuple expands to one IR type per result.
	tup := types.NewTuple(
		types.NewVar(0, nil, "d", types.NewSlice(types.Typ[types.Byte])),
		types.NewVar(0, nil, "e", errType),
	)
	rts := goTypesToIR(tup)
	if len(rts) != 2 || rts[0].NodeKind() != "SliceType" || rts[1].NodeKind() != "ErrorType" {
		t.Fatalf("goTypesToIR(tuple) = %#v", rts)
	}
	// Unknown shapes yield nil entries (callers fail loudly).
	if rts := goTypesToIR(types.NewPointer(types.Typ[types.Int])); len(rts) != 1 || rts[0] != nil {
		t.Fatalf("goTypesToIR(*int) = %#v, want [nil]", rts)
	}
	if rts := goTypesToIR(nil); rts != nil {
		t.Fatalf("goTypesToIR(nil) = %#v, want nil", rts)
	}
}

// TestResetFileContextAliasedImport pins alias handling: an aliased
// import binds the alias name, not the path's last segment.
func TestResetFileContextAliasedImport(t *testing.T) {
	t.Parallel()
	fset := token.NewFileSet()
	af, err := parser.ParseFile(fset, "x.go", `package p

import s "strings"

func f() { s.TrimSpace("x") }
`, parser.AllErrors)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if err := resetFileContext(af, nil); err != nil {
		t.Fatalf("resetFileContext: %v", err)
	}
	if curImports["s"] != "strings" {
		t.Fatalf("curImports = %v, want s→strings", curImports)
	}
	if _, ok := curImports["strings"]; ok {
		t.Fatalf("curImports should not bind the path segment for an alias: %v", curImports)
	}
}

// TestStdlibCallRejections pins the ok=false shapes: non-selector Fun,
// non-Ident prefix, unknown prefix, and a non-stdlib import path.
func TestStdlibCallRejections(t *testing.T) {
	t.Parallel()
	if err := resetFileContext(&ast.File{Name: &ast.Ident{Name: "p"}, Imports: []*ast.ImportSpec{
		{Path: &ast.BasicLit{Kind: token.STRING, Value: `"strings"`}},
		{Path: &ast.BasicLit{Kind: token.STRING, Value: `"example.com/x"`}},
	}}, nil); err != nil {
		t.Fatalf("resetFileContext: %v", err)
	}
	mk := func(fun ast.Expr) *ast.CallExpr {
		return &ast.CallExpr{Fun: fun, Args: []ast.Expr{&ast.Ident{Name: "s"}}}
	}
	if _, ok, err := stdlibCall(mk(&ast.Ident{Name: "len"})); ok || err != nil {
		t.Errorf("bare ident fun: ok=%v err=%v", ok, err)
	}
	if _, ok, err := stdlibCall(mk(&ast.SelectorExpr{
		X: &ast.ParenExpr{X: &ast.Ident{Name: "strings"}}, Sel: &ast.Ident{Name: "TrimSpace"},
	})); ok || err != nil {
		t.Errorf("non-ident prefix: ok=%v err=%v", ok, err)
	}
	if _, ok, err := stdlibCall(mk(&ast.SelectorExpr{
		X: &ast.Ident{Name: "unknown"}, Sel: &ast.Ident{Name: "F"},
	})); ok || err != nil {
		t.Errorf("unknown prefix: ok=%v err=%v", ok, err)
	}
	if _, ok, err := stdlibCall(mk(&ast.SelectorExpr{
		X: &ast.Ident{Name: "x"}, Sel: &ast.Ident{Name: "F"},
	})); ok || err != nil {
		t.Errorf("non-stdlib import: ok=%v err=%v", ok, err)
	}
	if _, ok, err := stdlibCall(mk(&ast.SelectorExpr{
		X: &ast.Ident{Name: "strings"}, Sel: &ast.Ident{Name: "TrimSpace"},
	})); !ok || err != nil {
		t.Errorf("strings.TrimSpace: ok=%v err=%v", ok, err)
	}
	if lastSlash("noslash") != -1 || lastSlash("a/b") != 1 {
		t.Errorf("lastSlash wrong")
	}
	if err := resetFileContext(&ast.File{Name: &ast.Ident{Name: "p"}, Imports: []*ast.ImportSpec{
		{Path: &ast.BasicLit{Kind: token.STRING, Value: `"bad`}},
	}}, nil); err == nil {
		t.Errorf("expected bad-import-path error")
	}
}
