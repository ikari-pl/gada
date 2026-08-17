package translate

import (
	"encoding/json"
	"flag"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// updateGolden lets a developer regenerate testdata/*.golden.json
// deliberately:
//
//	cd compiler && go test ./internal/translate/... -run TestCorpus -update
//
// Without the flag the test is read-only and fails on any drift.
var updateGolden = flag.Bool("update", false, "regenerate testdata/*.golden.json")

// TestCorpus walks every .go fixture under testdata/, translates it
// to IR, and asserts a byte-for-byte match against the matching
// .golden.json. The same JSON is then unmarshaled and DeepEqual'd
// against the in-memory IR — that catches encoder/decoder asymmetry
// that a pure text diff would miss.
func TestCorpus(t *testing.T) {
	t.Parallel()

	matches, err := filepath.Glob(filepath.Join("testdata", "*.go"))
	if err != nil {
		t.Fatalf("glob: %v", err)
	}
	wantNames := []string{
		"hello.go", "assign.go", "if.go",
		"for_classic.go", "for_infinite.go",
		"return.go", "binop.go", "unaryop.go",
		"selector.go", "combined.go",
		// Phase 2 — slice fixtures (compiler-emit Item 6).
		"slice_type_param.go", "slice_lit.go", "slice_index.go",
		"slice_subslice.go", "slice_append.go", "slice_len_cap.go",
		// Phase 2 — map fixtures (compiler-emit Item 7).
		"map_type_param.go", "map_lit.go", "map_index.go",
		"map_insert.go", "map_range.go", "map_delete.go",
		// Phase 2 — defer / panic / recover fixtures (compiler-emit Item 8).
		"defer_simple.go", "panic_simple.go", "recover_simple.go",
		// Phase 2 — main-side defer/panic fixtures (Item 9 emitMain wiring).
		"main_defer.go", "main_panic.go", "main_defer_panic.go",
		// Phase 3 — go-statement fixtures (compiler-emit go-stmt item).
		"go_simple.go", "go_main.go", "go_main_via_helper.go",
		// Phase 3 — go-statement argument capture (go f(x, y) snapshot).
		"go_with_args.go",
		// Phase 3 — channel-type fixture (channel-emit item, sub-item a).
		"chan_type_param.go",
		// Phase 3 — channel make fixture (channel-emit item, sub-item b).
		"chan_make.go",
		// Phase 3 — channel send fixture (channel-emit item, sub-item c).
		"chan_send.go",
		// Phase 3 — channel single-value receive fixture
		// (channel-emit item, sub-item d).
		"chan_recv_single.go",
		// Phase 3 — channel comma-ok receive fixture
		// (channel-emit item, sub-item e).
		"chan_recv_commaok.go",
		// Phase 3 — channel close fixture (channel-emit item, sub-item f).
		"chan_close.go",
		// Phase 3 — select-stmt fixture (select-emit item, sub-item b).
		"select_basic.go",
		// Phase 3 — multi-arg fmt.Println with int rendering (ping_pong b).
		"println_mixed_args.go",
		// Phase 4 — type declarations (item 2a): named scalar + struct.
		"type_decl.go",
		// Phase 4 — interface types (item 4a): method sets + empty any.
		"interface_decl.go",
		// Phase 4 — methods (item 4b): value + pointer receivers.
		"method_decl.go",
		// Phase 4 — interface satisfaction (item 4c-ii): a concrete type
		// with a method implementing an interface.
		"iface_satisfy.go",
		// Phase 4 — struct type in package main (item 5a-i).
		"struct_main.go",
		// Phase 4 — struct values: literals + field access (item 5a-ii).
		"struct_values.go",
		// Phase 4 — struct zero-value + partial literals (item 5a-iii).
		"struct_zero.go",
	}
	if got, want := len(matches), len(wantNames); got != want {
		t.Fatalf("corpus size mismatch: have %d files, want %d", got, want)
	}
	have := map[string]bool{}
	for _, m := range matches {
		have[filepath.Base(m)] = true
	}
	for _, n := range wantNames {
		if !have[n] {
			t.Fatalf("missing required corpus file %s", n)
		}
	}

	for _, src := range matches {
		src := src
		name := strings.TrimSuffix(filepath.Base(src), ".go")
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			fset := token.NewFileSet()
			af, err := parser.ParseFile(fset, src, nil, parser.AllErrors)
			if err != nil {
				t.Fatalf("parse %s: %v", src, err)
			}

			pkg, err := File(af, nil)
			if err != nil {
				t.Fatalf("translate %s: %v", src, err)
			}
			// File leaves File.Name empty by design; the source path
			// is the authoritative name. Fix it up so the goldens are
			// stable regardless of test working directory.
			pkg.Files[0].Name = filepath.Base(src)

			got, err := json.MarshalIndent(pkg, "", "  ")
			if err != nil {
				t.Fatalf("marshal: %v", err)
			}
			got = append(got, '\n')

			goldenPath := filepath.Join("testdata", name+".golden.json")
			if *updateGolden {
				if err := os.WriteFile(goldenPath, got, 0o644); err != nil {
					t.Fatalf("write golden: %v", err)
				}
				t.Logf("wrote %s", goldenPath)
				return
			}
			want, err := os.ReadFile(goldenPath)
			if err != nil {
				t.Fatalf("read %s: %v (run with -update to create)", goldenPath, err)
			}
			if string(got) != string(want) {
				t.Fatalf("%s mismatch\n--- want ---\n%s\n--- got ---\n%s", name, want, got)
			}

			// Round-trip the JSON back through the IR's Unmarshal and
			// confirm reflect.DeepEqual. This catches any drift
			// between Marshal and Unmarshal that a string diff alone
			// would miss.
			var back ir.Package
			if err := json.Unmarshal(got, &back); err != nil {
				t.Fatalf("unmarshal: %v\nJSON was:\n%s", err, got)
			}
			if !reflect.DeepEqual(pkg, &back) {
				t.Fatalf("%s round-trip mismatch\norig: %#v\nback: %#v", name, pkg, &back)
			}
		})
	}
}

// TestErrorCases covers the "feature N not supported in Phase 1"
// branches of the translator using parseable Go source. These exist
// to (a) document what is intentionally out of scope right now and
// (b) keep coverage above the 95% gate without resorting to
// hand-built ASTs.
func TestErrorCases(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		src     string
		wantSub string
	}{
		// Top-level constructs. (`type` declarations are supported as of
		// Phase 4 — see the type_decl corpus fixture and the two cases
		// below — so only var / const remain deferred.)
		{"top var", `package p; var x = 1`, "Phase 1"},
		{"top const", `package p; const c = 1`, "Phase 1"},
		// A type decl whose underlying type emit can't render yet rejects
		// at transType rather than producing a half-formed TypeDecl.
		{"type decl func underlying", `package p
type Handler func()`, "unsupported type expr"},
		{"struct embedded field", `package p
type E struct{ int }`, "embedded/anonymous struct fields"},
		{"embedded interface", `package p
type RW interface{ Reader }`, "embedded interfaces not supported"},
		{"interface method bad param", `package p
type I interface{ M(x complex128) }`, "unsupported type"},
		{"interface method bad result", `package p
type I interface{ M() complex128 }`, "unsupported type"},
		// Statement-level features that are out of Phase 1 scope.
		{"compound assign", `package p
func f() { x := 1; x += 1 }`, "assign token"},
		{"increment stmt", `package p
func f() { x := 1; x++ }`, "unsupported stmt"},
		{"if init", `package p
func f() { if x := 1; x > 0 {} }`, "if-with-init"},
		{"go with bad call subexpr", `package p
func f() { go g(1i) }`, "literal kind"},
		{"go panic with bad subexpr", `package p
func f() { go panic(1i) }`, "literal kind"},
		{"defer with bad call subexpr", `package p
func f() { defer g(1i) }`, "literal kind"},
		{"defer panic with bad subexpr", `package p
func f() { defer panic(1i) }`, "literal kind"},
		{"switch stmt", `package p
func f() { switch {} }`, "unsupported stmt"},
		// Expression-level features.
		{"imag literal", `package p
func f() { _ = 1i }`, "literal kind"},
		{"call as expr in rhs", `package p
func g() int { return 0 }
func f() { _ = g() }`, "general call-as-expression"},
		// Named-struct literals are supported (item 5a-ii); an *anonymous*
		// struct literal (`c.Type` is *ast.StructType, not *ast.Ident) has
		// no named Ada record to name, so it stays rejected.
		{"anon struct composite lit on rhs", `package p
func f() { _ = struct{}{} }`, "named-struct composite literals"},
		{"fixed-size array composite", `package p
func f() { _ = [3]int{1, 2, 3} }`, "fixed-size array composite"},
		// Named-struct literal error paths (item 5a-ii, transStructFields).
		{"struct lit mixed keyed/positional", `package p
func f() { _ = Point{X: 1, 2} }`, "mixes keyed and positional"},
		{"struct lit non-ident key", `package p
func f() { _ = Point{1: 2} }`, "field key must be an identifier"},
		{"struct lit bad keyed value", `package p
func f() { _ = Point{X: 1i} }`, "literal kind"},
		{"struct lit bad positional value", `package p
func f() { _ = Point{1i} }`, "literal kind"},
		{"map lit bad key type", `package p
func f() { _ = map[complex128]int{} }`, "unsupported type"},
		{"map lit bad value type", `package p
func f() { _ = map[int]complex128{} }`, "unsupported type"},
		{"map lit non-keyed entry", `package p
func f() { _ = map[int]int{1} }`, "K: V"},
		{"map lit bad key expr", `package p
func f() { _ = map[int]int{1i: 2} }`, "literal kind"},
		{"map lit bad value expr", `package p
func f() { _ = map[int]int{1: 1i} }`, "literal kind"},
		// Types.
		{"unsupported param type name", `package p
func f(x complex128) {}`, "unsupported type"},
		{"non-ident param type", `package p
func f(x func()) {}`, "unsupported type expr"},
		{"directional chan param", `package p
func f(x chan<- int) {}`, "directional channel types"},
		// `c <- v` SendStmt: the Value side runs through transExpr, so
		// any expression rejection (e.g. complex literals) surfaces here.
		// This pins transSend's Value-error return.
		{"chan send bad value", `package p
func f(c chan int) { c <- 1i }`, "literal kind"},
		// And the symmetric Chan-side rejection. The Go parser accepts a
		// numeric literal as the SendStmt.Chan slot (typecheck would
		// reject it later); translate's transExpr runs first and bounces.
		{"chan send bad chan", `package p
func f() { 1i <- 1 }`, "literal kind"},
		// select-stmt error paths. v1 supports only the Go-source
		// shapes the runtime can lower (Send / Recv-with-`:=` /
		// Default); other shapes hit the translate-side rejections.
		{"select recv with =", `package p
func f(c chan int, v int) { select { case v = <-c: } }`, "must use `:=`"},
		{"select send bad chan", `package p
func f() { select { case 1i <- 1: } }`, "literal kind"},
		{"select send bad value", `package p
func f(c chan int) { select { case c <- 1i: } }`, "literal kind"},
		{"select recv non-arrow rhs", `package p
func f() int { select { case v := 5: _ = v } ; return 0 }`, "must be `<-c`"},
		{"select drain non-arrow", `package p
func f() { select { case 1: } }`, "must be `case <-c:`"},
		{"select bad body", `package p
func f(c chan int) { select { case <-c: switch{} } }`, "unsupported stmt"},
		// transSelectCommClauseHead's transExpr(recv.X) error path
		// for both AssignStmt and ExprStmt arms — `<-1i` parses (the
		// parser doesn't typecheck) but transExpr on an imag literal
		// rejects loudly.
		{"select recv arrow bad chan", `package p
func f() { select { case v := <-1i: _ = v } }`, "literal kind"},
		{"select drain arrow bad chan", `package p
func f() { select { case <-1i: } }`, "literal kind"},
		{"map param bad key", `package p
func f(x map[complex128]int) {}`, "unsupported type"},
		{"map param bad value", `package p
func f(x map[int]complex128) {}`, "unsupported type"},
		{"unsupported result type", `package p
func f() complex128 { return 0 }`, "unsupported type"},
		{"fixed-size array param", `package p
func f(x [3]int) {}`, "fixed-size array types"},
		{"slice of unsupported elem", `package p
func f(x []complex128) {}`, "unsupported type"},
		// Slice-expression edge cases.
		{"three-index slice", `package p
func f(s []int) { _ = s[0:1:2] }`, "three-index slice"},
		{"index with bad subexpr", `package p
func f(s []int) { _ = s[1i] }`, "literal kind"},
		{"slice low bad subexpr", `package p
func f(s []int) { _ = s[1i:2] }`, "literal kind"},
		{"slice high bad subexpr", `package p
func f(s []int) { _ = s[0:1i] }`, "literal kind"},
		{"slice X bad subexpr", `package p
func f() { _ = (1i)[0:1] }`, "literal kind"},
		{"index X bad subexpr", `package p
func f() { _ = (1i)[0] }`, "literal kind"},
		{"slice lit elem bad", `package p
func f() { _ = []int{1i} }`, "literal kind"},
		{"builtin arg bad as stmt", `package p
func f() { panic(1i) }`, "literal kind"},
		{"builtin arg bad as expr", `package p
func f(s []int) { _ = len(1i) }`, "literal kind"},
		{"composite elided type", `package p
func f() { _ = [][]int{{1, 2}} }`, "elided type"},
		// Error propagation through every recursive helper. Each
		// case plants a Phase-1-unsupported leaf inside a particular
		// container so the corresponding error branch is exercised.
		{"binary X err", `package p
func f() { _ = 1i + 1 }`, "literal kind"},
		{"binary Y err", `package p
func f() { _ = 1 + 1i }`, "literal kind"},
		{"unary X err", `package p
func f() { _ = -1i }`, "literal kind"},
		{"selector X err", `package p
func f() { _ = (1i).a }`, "literal kind"},
		{"call fun err", `package p
func f() { (1i)() }`, "literal kind"},
		{"call arg err", `package p
func g(x int) {}
func f() { g(1i) }`, "literal kind"},
		{"return err", `package p
func f() int { return 1i }`, "literal kind"},
		{"assign lhs err", `package p
func f() { []int{1i} = nil }`, "literal kind"},
		{"if cond err", `package p
func f() { if 1i {} }`, "literal kind"},
		{"if then err", `package p
func f() { if true { x++ } }`, "unsupported stmt"},
		{"if else block err", `package p
func f() { if true {} else { x++ } }`, "unsupported stmt"},
		{"if nested else err", `package p
func f() { if true {} else if 1i {} }`, "literal kind"},
		{"for init err", `package p
func f() { for x := 1i; ; { _ = x } }`, "literal kind"},
		{"for cond err", `package p
func f() { for ; 1i; {} }`, "literal kind"},
		{"for post err", `package p
func f() { for ; ; x = 1i {} }`, "literal kind"},
		{"for body err", `package p
func f() { for { x++ } }`, "unsupported stmt"},
		// Range-statement edge cases.
		{"range x bad", `package p
func f() { for k := range (1i) { _ = k } }`, "literal kind"},
		{"range body err", `package p
func f(m map[int]int) { for range m { x++ } }`, "unsupported stmt"},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			fset := token.NewFileSet()
			af, err := parser.ParseFile(fset, "src.go", tc.src, parser.AllErrors)
			if err != nil {
				t.Fatalf("parse: %v", err)
			}
			_, err = File(af, nil)
			if err == nil {
				t.Fatalf("expected error containing %q, got nil", tc.wantSub)
			}
			if tc.wantSub != "" && !strings.Contains(err.Error(), tc.wantSub) {
				t.Fatalf("error %q does not contain %q", err.Error(), tc.wantSub)
			}
		})
	}
}

// TestSyntheticErrors covers branches that natural Go source cannot
// reach: nil inputs, unparseable import paths, function decls
// without a body, and `if` else clauses that are neither block nor
// nested-if. Each is constructed by hand.
func TestSyntheticErrors(t *testing.T) {
	t.Parallel()

	t.Run("nil ast.File", func(t *testing.T) {
		t.Parallel()
		if _, err := File(nil, nil); err == nil {
			t.Fatal("expected error for nil ast.File")
		}
	})

	t.Run("nil package name", func(t *testing.T) {
		t.Parallel()
		if _, err := File(&ast.File{}, nil); err == nil {
			t.Fatal("expected error for missing package clause")
		}
	})

	t.Run("bad import path", func(t *testing.T) {
		t.Parallel()
		af := &ast.File{
			Name: &ast.Ident{Name: "p"},
			Imports: []*ast.ImportSpec{
				{Path: &ast.BasicLit{Kind: token.STRING, Value: `"`}}, // unterminated
			},
		}
		if _, err := File(af, nil); err == nil {
			t.Fatal("expected error for malformed import path")
		}
	})

	t.Run("function without body", func(t *testing.T) {
		t.Parallel()
		af := &ast.File{
			Name: &ast.Ident{Name: "p"},
			Decls: []ast.Decl{
				&ast.FuncDecl{
					Name: &ast.Ident{Name: "extern"},
					Type: &ast.FuncType{Params: &ast.FieldList{}},
				},
			},
		}
		if _, err := File(af, nil); err == nil {
			t.Fatal("expected error for body-less function")
		}
	})

	t.Run("interface method non-func type", func(t *testing.T) {
		t.Parallel()
		// A named interface field whose type is not a FuncType. The
		// parser never yields this (a named field is always a method
		// with a signature), so it can only be built by hand — it
		// pins transInterfaceType's defensive non-FuncType branch.
		af := &ast.File{
			Name: &ast.Ident{Name: "p"},
			Decls: []ast.Decl{
				&ast.GenDecl{
					Tok: token.TYPE,
					Specs: []ast.Spec{
						&ast.TypeSpec{
							Name: &ast.Ident{Name: "I"},
							Type: &ast.InterfaceType{
								Methods: &ast.FieldList{
									List: []*ast.Field{
										{
											Names: []*ast.Ident{{Name: "M"}},
											Type:  &ast.Ident{Name: "int"},
										},
									},
								},
							},
						},
					},
				},
			},
		}
		if _, err := File(af, nil); err == nil {
			t.Fatal("expected error for interface method with non-func type")
		}
	})

	t.Run("unsupported else type", func(t *testing.T) {
		t.Parallel()
		af := &ast.File{
			Name: &ast.Ident{Name: "p"},
			Decls: []ast.Decl{
				&ast.FuncDecl{
					Name: &ast.Ident{Name: "f"},
					Type: &ast.FuncType{Params: &ast.FieldList{}},
					Body: &ast.BlockStmt{List: []ast.Stmt{
						&ast.IfStmt{
							Cond: &ast.Ident{Name: "true"},
							Body: &ast.BlockStmt{},
							// neither nil, *BlockStmt, nor *IfStmt
							Else: &ast.ReturnStmt{},
						},
					}},
				},
			},
		}
		if _, err := File(af, nil); err == nil {
			t.Fatal("expected error for unsupported else node")
		}
	})

	t.Run("unsupported top-level decl", func(t *testing.T) {
		t.Parallel()
		af := &ast.File{
			Name:  &ast.Ident{Name: "p"},
			Decls: []ast.Decl{(*ast.BadDecl)(nil)},
		}
		if _, err := File(af, nil); err == nil {
			t.Fatal("expected error for BadDecl")
		}
	})

	// Methods are unreachable through `go/parser` source alone — a
	// method declaration requires a sibling type declaration, which
	// fails first in File's GenDecl branch. Construct the FuncDecl
	// directly so the method-rejection path is tested.
	// Methods are now supported (item 4b); what natural source cannot
	// reach is a *generic* receiver — transReceiver's two defensive
	// branches. A generic receiver `func (c C[T]) m()` is an IndexExpr
	// (default branch); a pointer to one `func (c *C[T]) m()` is a
	// StarExpr over a non-Ident.
	methodRecv := func(recvType ast.Expr) *ast.File {
		return &ast.File{
			Name: &ast.Ident{Name: "p"},
			Decls: []ast.Decl{
				&ast.FuncDecl{
					Recv: &ast.FieldList{List: []*ast.Field{{
						Names: []*ast.Ident{{Name: "c"}},
						Type:  recvType,
					}}},
					Name: &ast.Ident{Name: "m"},
					Type: &ast.FuncType{Params: &ast.FieldList{}},
					Body: &ast.BlockStmt{},
				},
			},
		}
	}

	t.Run("generic receiver", func(t *testing.T) {
		t.Parallel()
		af := methodRecv(&ast.IndexExpr{
			X: &ast.Ident{Name: "C"}, Index: &ast.Ident{Name: "T"}})
		if _, err := File(af, nil); err == nil {
			t.Fatal("expected error for generic receiver")
		}
	})

	t.Run("pointer non-ident receiver", func(t *testing.T) {
		t.Parallel()
		af := methodRecv(&ast.StarExpr{X: &ast.IndexExpr{
			X: &ast.Ident{Name: "C"}, Index: &ast.Ident{Name: "T"}}})
		if _, err := File(af, nil); err == nil {
			t.Fatal("expected error for pointer non-ident receiver")
		}
	})
}

// TestNonCallExprStmt explicitly exercises the non-call branch of
// transExprStmt by translating unaryop.go (which has a bare `-x`
// statement) and walking the IR for the wrapped *ir.ExprStmt. The
// corpus golden test would catch a regression in the JSON shape, but
// this is an extra structural check that makes the intent clear.
func TestNonCallExprStmt(t *testing.T) {
	t.Parallel()

	fset := token.NewFileSet()
	af, err := parser.ParseFile(fset, "testdata/unaryop.go", nil, parser.AllErrors)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	pkg, err := File(af, nil)
	if err != nil {
		t.Fatalf("translate: %v", err)
	}
	flip := pkg.Files[0].Decls[0].(*ir.Function)
	es, ok := flip.Body[0].(*ir.ExprStmt)
	if !ok {
		t.Fatalf("expected first stmt to be *ir.ExprStmt, got %T", flip.Body[0])
	}
	if _, ok := es.X.(*ir.UnaryOp); !ok {
		t.Fatalf("expected ExprStmt.X to be *ir.UnaryOp, got %T", es.X)
	}
}

// TestStmtPositionBuiltin confirms that a builtin call used as a
// statement (e.g. bare `panic("boom")`) translates to *ir.BuiltinCall
// directly, not to *ir.Call wrapped in *ir.ExprStmt. The slice
// fixtures only exercise builtins in expression position
// (`xs = append(xs, x)`, `return len(s)`), so this is the dedicated
// coverage for the stmt-position branch of transExprStmt.
func TestStmtPositionBuiltin(t *testing.T) {
	t.Parallel()

	const src = `package p
func boom() { panic("oh no") }`

	fset := token.NewFileSet()
	af, err := parser.ParseFile(fset, "boom.go", src, parser.AllErrors)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	pkg, err := File(af, nil)
	if err != nil {
		t.Fatalf("translate: %v", err)
	}
	fn := pkg.Files[0].Decls[0].(*ir.Function)
	bc, ok := fn.Body[0].(*ir.BuiltinCall)
	if !ok {
		t.Fatalf("expected first stmt to be *ir.BuiltinCall, got %T", fn.Body[0])
	}
	if bc.Name != "panic" {
		t.Fatalf("expected builtin name 'panic', got %q", bc.Name)
	}
	if len(bc.Args) != 1 {
		t.Fatalf("expected 1 arg, got %d", len(bc.Args))
	}
}

// TestParenUnwrap confirms ParenExpr is transparent: `(i * 2)` in
// combined.go should produce the same IR as `i * 2`.
func TestParenUnwrap(t *testing.T) {
	t.Parallel()

	fset := token.NewFileSet()
	af, err := parser.ParseFile(fset, "testdata/combined.go", nil, parser.AllErrors)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	pkg, err := File(af, nil)
	if err != nil {
		t.Fatalf("translate: %v", err)
	}
	demo := pkg.Files[0].Decls[0].(*ir.Function)
	forStmt := demo.Body[1].(*ir.For)
	assign := forStmt.Body[0].(*ir.Assign)
	rhs := assign.RHS[0].(*ir.BinOp)
	// Inner `i * 2` should be a BinOp, not nested under any paren-ish
	// node. (The IR has no paren type; the unwrap is structural.)
	if _, ok := rhs.Y.(*ir.BinOp); !ok {
		t.Fatalf("expected paren-unwrapped *ir.BinOp on RHS.Y, got %T", rhs.Y)
	}
}

// TestTransStructTypeNilFields covers transStructType's defensive
// nil-FieldList guard. The Go parser never produces a struct type with
// a nil Fields (even `struct{}` yields a non-nil empty FieldList), so
// the case is reachable only via a hand-built AST node — which is
// exactly what an error-recovered parse or a synthetic AST could hand
// us. It must return an empty StructType, not nil-deref.
func TestTransStructTypeNilFields(t *testing.T) {
	t.Parallel()
	got, err := transType(&ast.StructType{Fields: nil})
	if err != nil {
		t.Fatalf("transType(struct with nil Fields) error = %v", err)
	}
	st, ok := got.(*ir.StructType)
	if !ok {
		t.Fatalf("expected *ir.StructType, got %T", got)
	}
	if len(st.Fields) != 0 {
		t.Fatalf("expected zero fields, got %d", len(st.Fields))
	}
}
