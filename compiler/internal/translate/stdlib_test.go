package translate

import (
	"go/ast"
	"go/importer"
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
			rts := (&translator{}).goTypesToIR(tc.t)
			if len(rts) != 1 || rts[0] == nil || rts[0].NodeKind() != tc.want {
				t.Fatalf("(&translator{}).goTypesToIR(%s) = %#v, want 1 result of kind %s", tc.name, rts, tc.want)
			}
		})
	}
	// Tuple expands to one IR type per result.
	tup := types.NewTuple(
		types.NewVar(0, nil, "d", types.NewSlice(types.Typ[types.Byte])),
		types.NewVar(0, nil, "e", errType),
	)
	rts := (&translator{}).goTypesToIR(tup)
	if len(rts) != 2 || rts[0].NodeKind() != "SliceType" || rts[1].NodeKind() != "ErrorType" {
		t.Fatalf("(&translator{}).goTypesToIR(tuple) = %#v", rts)
	}
	// Unknown shapes yield nil entries (callers fail loudly).
	if rts := (&translator{}).goTypesToIR(types.NewPointer(types.Typ[types.Int])); len(rts) != 1 || rts[0] != nil {
		t.Fatalf("(&translator{}).goTypesToIR(*int) = %#v, want [nil]", rts)
	}
	if rts := (&translator{}).goTypesToIR(nil); rts != nil {
		t.Fatalf("(&translator{}).goTypesToIR(nil) = %#v, want nil", rts)
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
	tr, err := newTranslator(af, nil)
	if err != nil {
		t.Fatalf("newTranslator: %v", err)
	}
	if tr.imports["s"] != "strings" {
		t.Fatalf("imports = %v, want s→strings", tr.imports)
	}
	if _, ok := tr.imports["strings"]; ok {
		t.Fatalf("imports should not bind the path segment for an alias: %v", tr.imports)
	}
}

// TestStdlibCallRejections pins the ok=false shapes: non-selector Fun,
// non-Ident prefix, unknown prefix, and a non-stdlib import path.
func TestStdlibCallRejections(t *testing.T) {
	t.Parallel()
	tr, err := newTranslator(&ast.File{Name: &ast.Ident{Name: "p"}, Imports: []*ast.ImportSpec{
		{Path: &ast.BasicLit{Kind: token.STRING, Value: `"strings"`}},
		{Path: &ast.BasicLit{Kind: token.STRING, Value: `"example.com/x"`}},
	}}, nil)
	if err != nil {
		t.Fatalf("newTranslator: %v", err)
	}
	mk := func(fun ast.Expr) *ast.CallExpr {
		return &ast.CallExpr{Fun: fun, Args: []ast.Expr{&ast.Ident{Name: "s"}}}
	}
	if _, ok, err := tr.stdlibCall(mk(&ast.Ident{Name: "len"})); ok || err != nil {
		t.Errorf("bare ident fun: ok=%v err=%v", ok, err)
	}
	if _, ok, err := tr.stdlibCall(mk(&ast.SelectorExpr{
		X: &ast.ParenExpr{X: &ast.Ident{Name: "strings"}}, Sel: &ast.Ident{Name: "TrimSpace"},
	})); ok || err != nil {
		t.Errorf("non-ident prefix: ok=%v err=%v", ok, err)
	}
	if _, ok, err := tr.stdlibCall(mk(&ast.SelectorExpr{
		X: &ast.Ident{Name: "unknown"}, Sel: &ast.Ident{Name: "F"},
	})); ok || err != nil {
		t.Errorf("unknown prefix: ok=%v err=%v", ok, err)
	}
	if _, ok, err := tr.stdlibCall(mk(&ast.SelectorExpr{
		X: &ast.Ident{Name: "x"}, Sel: &ast.Ident{Name: "F"},
	})); ok || err != nil {
		t.Errorf("non-stdlib import: ok=%v err=%v", ok, err)
	}
	if _, ok, err := tr.stdlibCall(mk(&ast.SelectorExpr{
		X: &ast.Ident{Name: "strings"}, Sel: &ast.Ident{Name: "TrimSpace"},
	})); !ok || err != nil {
		t.Errorf("strings.TrimSpace: ok=%v err=%v", ok, err)
	}
	if lastSlash("noslash") != -1 || lastSlash("a/b") != 1 {
		t.Errorf("lastSlash wrong")
	}
	if _, err := newTranslator(&ast.File{Name: &ast.Ident{Name: "p"}, Imports: []*ast.ImportSpec{
		{Path: &ast.BasicLit{Kind: token.STRING, Value: `"bad`}},
	}}, nil); err == nil {
		t.Errorf("expected bad-import-path error")
	}
}

// TestTranslatorMiscArms covers the remaining stdlib.go branches: the
// transExpr test wrapper, stdlibCall arg-error propagation, the
// info-backed ResultTypes path, and a bare (unnamed) error interface.
func TestTranslatorMiscArms(t *testing.T) {
	t.Parallel()
	// transExpr wrapper works standalone.
	if _, err := transExpr(&ast.Ident{Name: "x"}); err != nil {
		t.Fatalf("transExpr wrapper: %v", err)
	}
	// stdlibCall propagates arg translation errors (func lit is unsupported).
	tr := &translator{imports: map[string]string{"strings": "strings"}}
	bad := &ast.CallExpr{
		Fun: &ast.SelectorExpr{X: &ast.Ident{Name: "strings"}, Sel: &ast.Ident{Name: "Fields"}},
		Args: []ast.Expr{&ast.FuncLit{
			Type: &ast.FuncType{},
			Body: &ast.BlockStmt{},
		}},
	}
	if _, _, err := tr.stdlibCall(bad); err == nil {
		t.Fatal("expected arg-translation error to propagate")
	}
	// info-backed ResultTypes: type-check a tiny source with go/types.
	src := `package p

import "strings"

func f(s string) []string { return strings.Fields(s) }
`
	fset := token.NewFileSet()
	af, err := parser.ParseFile(fset, "x.go", src, parser.AllErrors)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	conf := types.Config{Importer: importer.Default()}
	info := &types.Info{Types: map[ast.Expr]types.TypeAndValue{}}
	_, err = conf.Check("p", fset, []*ast.File{af}, info)
	if err != nil {
		t.Fatalf("typecheck: %v", err)
	}
	tr2, err := newTranslator(af, info)
	if err != nil {
		t.Fatalf("newTranslator: %v", err)
	}
	call := af.Decls[1].(*ast.FuncDecl).Body.List[0].(*ast.ReturnStmt).Results[0].(*ast.CallExpr)
	c, ok, err := tr2.stdlibCall(call)
	if !ok || err != nil {
		t.Fatalf("stdlibCall: ok=%v err=%v", ok, err)
	}
	if len(c.ResultTypes) != 1 || c.ResultTypes[0].NodeKind() != "SliceType" {
		t.Fatalf("info-backed ResultTypes = %#v", c.ResultTypes)
	}
	// Bare (unnamed) one-method Error interface also maps to ErrorType.
	iface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(0, nil, "Error", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(), types.NewTuple(types.NewVar(0, nil, "", types.Typ[types.String])), false)),
	}, nil)
	if got := (&translator{}).goOneToIR(iface); got == nil || got.NodeKind() != "ErrorType" {
		t.Fatalf("goOneToIR(bare error iface) = %#v", got)
	}
}
