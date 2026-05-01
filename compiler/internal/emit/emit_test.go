package emit

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// updateGolden lets a developer regenerate testdata/*.golden.adb
// deliberately:
//
//	cd compiler && go test ./internal/emit/... -run TestCorpus -update
//
// Without the flag the test is read-only and fails on any drift.
var updateGolden = flag.Bool("update", false, "regenerate testdata/*.golden.adb")

// corpusFixtures is the set of fixture base names emit shares with
// translate. The IR golden lives under translate/testdata/ and is
// the source-of-truth shape; the .adb golden lives next to this
// test file.
var corpusFixtures = []string{
	"hello", "assign", "if",
	"for_classic", "for_infinite",
	"return", "binop", "unaryop",
	"selector", "combined",
}

// TestCorpus loads each fixture's IR (from translate/testdata), runs
// it through emit.Package, and asserts a byte-for-byte match against
// the corresponding .golden.adb. The IR side is shared with
// translate so a divergence in emit alone surfaces here, while a
// divergence in IR shape would surface in translate's TestCorpus.
func TestCorpus(t *testing.T) {
	t.Parallel()

	for _, name := range corpusFixtures {
		name := name
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			pkg := loadFixtureIR(t, name)

			var buf bytes.Buffer
			if err := Package(pkg, &buf); err != nil {
				t.Fatalf("emit: %v", err)
			}
			got := buf.Bytes()

			adbPath := filepath.Join("testdata", name+".golden.adb")
			if *updateGolden {
				if err := os.WriteFile(adbPath, got, 0o644); err != nil {
					t.Fatalf("write golden: %v", err)
				}
				t.Logf("wrote %s", adbPath)
				return
			}
			want, err := os.ReadFile(adbPath)
			if err != nil {
				t.Fatalf("read %s: %v (run with -update to create)", adbPath, err)
			}
			if !bytes.Equal(got, want) {
				t.Fatalf("%s mismatch\n--- want ---\n%s\n--- got ---\n%s",
					name, want, got)
			}
		})
	}
}

// TestCorpusComplete guards against silent shrinkage of the corpus
// (e.g. a `.golden.adb` file deleted, or a fixture name removed
// from corpusFixtures).
func TestCorpusComplete(t *testing.T) {
	t.Parallel()
	matches, err := filepath.Glob(filepath.Join("testdata", "*.golden.adb"))
	if err != nil {
		t.Fatalf("glob: %v", err)
	}
	if got, want := len(matches), len(corpusFixtures); got != want {
		t.Fatalf("found %d .golden.adb files, want %d", got, want)
	}
	have := map[string]bool{}
	for _, m := range matches {
		base := strings.TrimSuffix(filepath.Base(m), ".golden.adb")
		have[base] = true
	}
	for _, name := range corpusFixtures {
		if !have[name] {
			t.Errorf("missing testdata/%s.golden.adb", name)
		}
	}
}

func loadFixtureIR(t *testing.T, name string) *ir.Package {
	t.Helper()
	path := filepath.Join("..", "translate", "testdata", name+".golden.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read IR golden %s: %v", path, err)
	}
	var pkg ir.Package
	if err := json.Unmarshal(raw, &pkg); err != nil {
		t.Fatalf("decode IR %s: %v", path, err)
	}
	return &pkg
}

// --- Negative space: error branches reachable from real IR ----------------
//
// Cases where a structurally-valid but Phase-1-unsupported IR shape
// must produce a typed error rather than silently-wrong Ada.
// Branches that are unreachable from any IR the translator can
// produce (e.g. a hypothetical non-Function Decl) are intentionally
// not exercised — they're defensive against future IR additions.

func TestErrorCases(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		pkg     *ir.Package
		wantErr string
	}{
		{
			name:    "nil package",
			pkg:     nil,
			wantErr: "nil package",
		},
		{
			name:    "zero files",
			pkg:     &ir.Package{Name: "main", Files: nil},
			wantErr: "expected exactly one file",
		},
		{
			name: "two files",
			pkg: &ir.Package{Name: "main", Files: []*ir.File{
				{Name: "a"}, {Name: "b"},
			}},
			wantErr: "expected exactly one file",
		},
		{
			name: "multi-value := lhs/rhs",
			pkg: wrapMain(funcMain(
				&ir.Assign{Define: true,
					LHS: []ir.Expr{idn("x"), idn("y")},
					RHS: []ir.Expr{litInt("1")}})),
			wantErr: "multi-value :=",
		},
		{
			name: "non-ident lhs in :=",
			pkg: wrapMain(funcMain(
				&ir.Assign{Define: true,
					LHS: []ir.Expr{litInt("1")},
					RHS: []ir.Expr{litInt("2")}})),
			wantErr: ":= lhs must be a plain identifier",
		},
		{
			name: "non-literal := rhs",
			pkg: wrapMain(funcMain(
				&ir.Assign{Define: true,
					LHS: []ir.Expr{idn("x")},
					RHS: []ir.Expr{idn("y")}})),
			wantErr: "literal RHS",
		},
		{
			name: "unknown literal kind",
			pkg: wrapMain(funcMain(
				&ir.Assign{Define: true,
					LHS: []ir.Expr{idn("x")},
					RHS: []ir.Expr{&ir.Lit{Kind: "weird", Value: "?"}}})),
			wantErr: "unknown literal kind",
		},
		{
			name: ":= after non-define",
			pkg: wrapMain(funcMain(
				&ir.Assign{Define: false,
					LHS: []ir.Expr{idn("x")}, RHS: []ir.Expr{litInt("0")}},
				&ir.Assign{Define: true,
					LHS: []ir.Expr{idn("y")}, RHS: []ir.Expr{litInt("1")}})),
			wantErr: ":= outside head of function body",
		},
		{
			name: "multi-value plain assign",
			pkg: wrapMain(funcMain(
				&ir.Assign{Define: false,
					LHS: []ir.Expr{idn("x"), idn("y")},
					RHS: []ir.Expr{litInt("1")}})),
			wantErr: "multi-value assignment",
		},
		{
			name: "multi-value return",
			pkg: wrapMain(funcMain(
				&ir.Return{Results: []ir.Expr{litInt("1"), litInt("2")}})),
			wantErr: "multi-value return",
		},
		{
			name: "multi-value return on function signature",
			pkg: wrapPkg(&ir.Function{
				Name:    "two",
				Results: []*ir.Param{{Type: &ir.IntType{}}, {Type: &ir.IntType{}}},
				Body:    []ir.Stmt{&ir.Return{Results: []ir.Expr{litInt("1")}}},
			}),
			wantErr: "multi-value return on two",
		},
		{
			name: "unsupported binary op",
			pkg: wrapMain(funcMain(
				&ir.Return{Results: []ir.Expr{
					&ir.BinOp{Op: "<<", X: idn("x"), Y: idn("y")},
				}})),
			wantErr: `unsupported binary op "<<"`,
		},
		{
			name: "unsupported unary op",
			pkg: wrapMain(funcMain(
				&ir.Return{Results: []ir.Expr{
					&ir.UnaryOp{Op: "&", X: idn("x")},
				}})),
			wantErr: `unsupported unary op "&"`,
		},
		{
			name: "bad string literal escape",
			pkg: wrapMain(funcMain(
				&ir.Return{Results: []ir.Expr{
					&ir.Lit{Kind: ir.LitString, Value: `"unterminated`},
				}})),
			wantErr: "bad string literal",
		},
		{
			name: "control character in string literal",
			pkg: wrapMain(funcMain(
				&ir.Return{Results: []ir.Expr{
					&ir.Lit{Kind: ir.LitString, Value: "\"line\\nbreak\""},
				}})),
			wantErr: "control characters",
		},
		{
			name: "non-trivial for",
			pkg: wrapMain(funcMain(&ir.For{
				Init: &ir.Assign{Define: true,
					LHS: []ir.Expr{idn("i")},
					RHS: []ir.Expr{litInt("0")}},
				Cond: &ir.BinOp{Op: ">", X: idn("i"), Y: idn("n")}, // wrong direction
				Post: &ir.Assign{Define: false,
					LHS: []ir.Expr{idn("i")},
					RHS: []ir.Expr{&ir.BinOp{Op: "+", X: idn("i"), Y: litInt("1")}}},
			})),
			wantErr: "trivial integer for-loops",
		},
		{
			name: "missing param type",
			pkg: wrapPkg(&ir.Function{
				Name:   "f",
				Params: []*ir.Param{{Name: "x", Type: nil}},
				Body:   nil,
			}),
			wantErr: "missing type",
		},
		{
			name: "missing result type",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Results: []*ir.Param{{Type: nil}},
				Body:    nil,
			}),
			wantErr: "missing type",
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := Package(tc.pkg, &bytes.Buffer{})
			if err == nil {
				t.Fatalf("expected error matching %q, got nil", tc.wantErr)
			}
			if !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("error %q does not contain %q", err.Error(), tc.wantErr)
			}
		})
	}
}

// TestNonTrivialForVariants exercises every clause of matchTrivialFor's
// rejection logic so the for-loop pattern matcher is pinned by test.
func TestNonTrivialForVariants(t *testing.T) {
	t.Parallel()
	mkBody := func(f *ir.For) *ir.Package {
		return wrapMain(funcMain(f))
	}
	stdInit := &ir.Assign{Define: true,
		LHS: []ir.Expr{idn("i")}, RHS: []ir.Expr{litInt("0")}}
	stdCond := &ir.BinOp{Op: "<", X: idn("i"), Y: idn("n")}
	stdPost := &ir.Assign{Define: false,
		LHS: []ir.Expr{idn("i")},
		RHS: []ir.Expr{&ir.BinOp{Op: "+", X: idn("i"), Y: litInt("1")}}}

	cases := []*ir.For{
		// init isn't define
		{Init: &ir.Assign{Define: false, LHS: []ir.Expr{idn("i")}, RHS: []ir.Expr{litInt("0")}},
			Cond: stdCond, Post: stdPost},
		// init lhs not ident
		{Init: &ir.Assign{Define: true, LHS: []ir.Expr{litInt("0")}, RHS: []ir.Expr{litInt("0")}},
			Cond: stdCond, Post: stdPost},
		// init multi-value
		{Init: &ir.Assign{Define: true, LHS: []ir.Expr{idn("i"), idn("j")}, RHS: []ir.Expr{litInt("0")}},
			Cond: stdCond, Post: stdPost},
		// cond not binop
		{Init: stdInit, Cond: idn("i"), Post: stdPost},
		// cond op not <
		{Init: stdInit, Cond: &ir.BinOp{Op: "<=", X: idn("i"), Y: idn("n")}, Post: stdPost},
		// cond X not ident matching V
		{Init: stdInit, Cond: &ir.BinOp{Op: "<", X: litInt("0"), Y: idn("n")}, Post: stdPost},
		{Init: stdInit, Cond: &ir.BinOp{Op: "<", X: idn("k"), Y: idn("n")}, Post: stdPost},
		// post not assign
		{Init: stdInit, Cond: stdCond, Post: &ir.Return{}},
		// post is define (impossible in real Go but the matcher rejects)
		{Init: stdInit, Cond: stdCond,
			Post: &ir.Assign{Define: true, LHS: []ir.Expr{idn("i")},
				RHS: []ir.Expr{&ir.BinOp{Op: "+", X: idn("i"), Y: litInt("1")}}}},
		// post lhs not ident matching V
		{Init: stdInit, Cond: stdCond,
			Post: &ir.Assign{Define: false, LHS: []ir.Expr{idn("k")},
				RHS: []ir.Expr{&ir.BinOp{Op: "+", X: idn("i"), Y: litInt("1")}}}},
		// post lhs is lit
		{Init: stdInit, Cond: stdCond,
			Post: &ir.Assign{Define: false, LHS: []ir.Expr{litInt("0")},
				RHS: []ir.Expr{&ir.BinOp{Op: "+", X: idn("i"), Y: litInt("1")}}}},
		// post rhs not binop
		{Init: stdInit, Cond: stdCond,
			Post: &ir.Assign{Define: false, LHS: []ir.Expr{idn("i")},
				RHS: []ir.Expr{litInt("1")}}},
		// post rhs op not +
		{Init: stdInit, Cond: stdCond,
			Post: &ir.Assign{Define: false, LHS: []ir.Expr{idn("i")},
				RHS: []ir.Expr{&ir.BinOp{Op: "-", X: idn("i"), Y: litInt("1")}}}},
		// post rhs X not ident matching V
		{Init: stdInit, Cond: stdCond,
			Post: &ir.Assign{Define: false, LHS: []ir.Expr{idn("i")},
				RHS: []ir.Expr{&ir.BinOp{Op: "+", X: idn("k"), Y: litInt("1")}}}},
		// post rhs Y not int 1
		{Init: stdInit, Cond: stdCond,
			Post: &ir.Assign{Define: false, LHS: []ir.Expr{idn("i")},
				RHS: []ir.Expr{&ir.BinOp{Op: "+", X: idn("i"), Y: litInt("2")}}}},
	}
	for i, f := range cases {
		err := Package(mkBody(f), &bytes.Buffer{})
		if err == nil || !strings.Contains(err.Error(), "trivial integer for-loops") {
			t.Errorf("case %d: expected trivial-for rejection, got %v", i, err)
		}
	}
}

// TestSelectorFallthrough exercises the dotted-selector fallback
// path (everything that isn't fmt.Println). Phase 1 doesn't really
// support these, but we keep the path live for later phases — and
// the test pins the formatting so it doesn't drift accidentally.
func TestSelectorFallthrough(t *testing.T) {
	t.Parallel()
	pkg := wrapMain(funcMain(
		&ir.Call{
			Fun: &ir.Selector{X: idn("foo"), Sel: "Bar"},
		},
	))
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	if !strings.Contains(buf.String(), "Foo.Bar;") {
		t.Fatalf("expected dotted selector output, got:\n%s", buf.String())
	}
}

// TestReservedRenameVariants covers identifier mutations not present
// in the corpus directly — both that an Ada reserved word gains the
// `_K` suffix, and that a non-reserved word is just first-letter
// capitalised.
func TestReservedRenameVariants(t *testing.T) {
	t.Parallel()
	cases := []struct {
		in, want string
	}{
		{"loop", "Loop_K"},
		{"end", "End_K"},
		{"return", "Return_K"},
		{"x", "X"},
		{"prefix", "Prefix"},
		{"OK", "OK"},
		{"Already", "Already"},
		{"", ""},
	}
	for _, tc := range cases {
		got := adaIdent(tc.in)
		if got != tc.want {
			t.Errorf("adaIdent(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// TestBoolFalseLiteral covers the False side of the bool literal
// translation (the corpus only exercises True via `func always()`).
func TestBoolFalseLiteral(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name:    "no",
		Results: []*ir.Param{{Type: &ir.BoolType{}}},
		Body: []ir.Stmt{
			&ir.Return{Results: []ir.Expr{&ir.Lit{Kind: ir.LitBool, Value: "false"}}},
		},
	})
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	if !strings.Contains(buf.String(), "return False;") {
		t.Fatalf("expected return False;, got:\n%s", buf.String())
	}
}

// TestUnaryPlusAndStringEscape covers branches not in the corpus:
// unary `+`, the BinOp-child wrapping for unary, and string
// literals containing an embedded `"` (Ada doubles them).
func TestUnaryPlusAndStringEscape(t *testing.T) {
	t.Parallel()
	pkg := wrapMain(funcMain(
		&ir.Call{
			Fun: &ir.Selector{X: idn("fmt"), Sel: "Println"},
			Args: []ir.Expr{
				&ir.Lit{Kind: ir.LitString, Value: `"a\"b"`},
			},
		},
		&ir.Return{Results: []ir.Expr{
			&ir.UnaryOp{Op: "+", X: &ir.BinOp{Op: "+", X: idn("a"), Y: idn("b")}},
		}},
	))
	pkg.Files[0].Imports = []string{"fmt"}
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	out := buf.String()
	if !strings.Contains(out, `Println ("a""b");`) {
		t.Fatalf("expected escaped string literal a\"\"b, got:\n%s", out)
	}
	if !strings.Contains(out, `return +(A + B);`) {
		t.Fatalf("expected unary + with parenthesised binop child, got:\n%s", out)
	}
}

// TestVarDeclTypeInference covers all four literal-typed `:=`
// declaration variants. The corpus only exercises Integer; the other
// three are reachable but unused there.
func TestVarDeclTypeInference(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		lit  *ir.Lit
		want string
	}{
		{"int", &ir.Lit{Kind: ir.LitInt, Value: "1"}, "X : Integer := 1;"},
		{"string", &ir.Lit{Kind: ir.LitString, Value: `"hi"`}, `X : String := "hi";`},
		{"bool", &ir.Lit{Kind: ir.LitBool, Value: "true"}, "X : Boolean := True;"},
		{"float", &ir.Lit{Kind: ir.LitFloat, Value: "1.5"}, "X : Long_Float := 1.5;"},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			pkg := wrapMain(funcMain(
				&ir.Assign{Define: true,
					LHS: []ir.Expr{idn("x")},
					RHS: []ir.Expr{tc.lit}},
			))
			var buf bytes.Buffer
			if err := Package(pkg, &buf); err != nil {
				t.Fatalf("emit: %v", err)
			}
			if !strings.Contains(buf.String(), tc.want) {
				t.Fatalf("missing %q in:\n%s", tc.want, buf.String())
			}
		})
	}
}

// TestBinaryOpTranslation pins the operator mapping table. Every
// supported Go binary op is exercised; unsupported ones are covered
// by TestErrorCases.
func TestBinaryOpTranslation(t *testing.T) {
	t.Parallel()
	cases := []struct {
		op   string
		want string
	}{
		{"+", "A + B"}, {"-", "A - B"}, {"*", "A * B"}, {"/", "A / B"},
		{"<", "A < B"}, {">", "A > B"}, {"<=", "A <= B"}, {">=", "A >= B"},
		{"==", "A = B"}, {"!=", "A /= B"},
		{"&&", "A and B"}, {"||", "A or B"},
		{"%", "A mod B"},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.op, func(t *testing.T) {
			t.Parallel()
			pkg := wrapPkg(&ir.Function{
				Name:    "f",
				Params:  []*ir.Param{{Name: "a", Type: &ir.IntType{}}, {Name: "b", Type: &ir.IntType{}}},
				Results: []*ir.Param{{Type: &ir.IntType{}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.BinOp{Op: tc.op, X: idn("a"), Y: idn("b")},
				}}},
			})
			var buf bytes.Buffer
			if err := Package(pkg, &buf); err != nil {
				t.Fatalf("emit: %v", err)
			}
			if !strings.Contains(buf.String(), "return "+tc.want+";") {
				t.Fatalf("expected `return %s;`, got:\n%s", tc.want, buf.String())
			}
		})
	}
}

// TestUnaryWithNonBinopChild exercises the unary path whose child
// is not a BinOp (so no wrapping), separately from the corpus.
func TestUnaryWithNonBinopChild(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name:    "f",
		Results: []*ir.Param{{Type: &ir.IntType{}}},
		Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
			&ir.UnaryOp{Op: "+", X: litInt("5")},
		}}},
	})
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	if !strings.Contains(buf.String(), "return +5;") {
		t.Fatalf("expected `return +5;`, got:\n%s", buf.String())
	}
}

// TestForBareEmptyBody covers the bare `for { }` with an empty body
// (translates to `loop null; end loop;`); the corpus's bare-for
// has a return statement instead.
func TestForBareEmptyBody(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name: "spin",
		Body: []ir.Stmt{&ir.For{}},
	})
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	out := buf.String()
	if !strings.Contains(out, "loop\n         null;\n      end loop;") {
		t.Fatalf("expected empty bare-for to use null;, got:\n%s", out)
	}
}

// TestZeroArgCallStmt covers a call with no arguments — the corpus
// always has at least one argument.
func TestZeroArgCallStmt(t *testing.T) {
	t.Parallel()
	pkg := wrapMain(funcMain(
		&ir.Call{Fun: idn("Tick")},
	))
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	if !strings.Contains(buf.String(), "Tick;") {
		t.Fatalf("expected zero-arg call to emit `Tick;`, got:\n%s", buf.String())
	}
}

// TestVoidReturn covers `return;` (no results), which the corpus
// only exercises inside the bare `for { }`.
func TestVoidReturn(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name: "stop",
		Body: []ir.Stmt{&ir.Return{}},
	})
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	if !strings.Contains(buf.String(), "return;") {
		t.Fatalf("expected void return, got:\n%s", buf.String())
	}
}

// TestProjectTemplateExposed sanity-checks that the embedded
// template is non-empty and contains the placeholder fields the
// driver depends on.
func TestProjectTemplateExposed(t *testing.T) {
	t.Parallel()
	want := []string{
		"{{.ProjectName}}", "{{.RuntimeProject}}", "{{.SourceDir}}",
		"{{.ObjectDir}}", "{{.ExecDir}}", "{{.MainFile}}",
	}
	for _, w := range want {
		if !strings.Contains(ProjectTemplate, w) {
			t.Errorf("ProjectTemplate missing %s", w)
		}
	}
}

// TestExprEmitAfterError ensures sticky errors short-circuit further
// emit work without panicking on follow-on nil dereferences.
func TestExprEmitAfterError(t *testing.T) {
	t.Parallel()
	e := newEmitter("p", &ir.File{})
	e.fail(fmt.Errorf("primary"))
	if got := e.emitExpr(idn("x")); got != "" {
		t.Fatalf("expected empty after sticky error, got %q", got)
	}
	e.emitStmt(&ir.Return{}) // must not panic
	e.emitVarDecl(&ir.Assign{Define: true,
		LHS: []ir.Expr{idn("x")},
		RHS: []ir.Expr{litInt("1")}})
	e.emitSubprogram(&ir.Function{Name: "f"})

	if e.err == nil || e.err.Error() != "primary" {
		t.Fatalf("expected sticky primary error preserved, got %v", e.err)
	}
}

// --- helpers --------------------------------------------------------------

func wrapMain(decls ...ir.Decl) *ir.Package {
	return &ir.Package{Name: "main", Files: []*ir.File{
		{Name: "x.go", Decls: decls},
	}}
}

// wrapPkg fabricates a non-main IR package called "p" — the only
// non-main name the emit-test corpus exercises today. If a future
// fixture needs a different name, widen the helper rather than open-
// code the wrapping at every call site.
func wrapPkg(decls ...ir.Decl) *ir.Package {
	return &ir.Package{Name: "p", Files: []*ir.File{
		{Name: "x.go", Decls: decls},
	}}
}

func funcMain(stmts ...ir.Stmt) *ir.Function {
	return &ir.Function{Name: "main", Body: stmts}
}

func idn(s string) *ir.Ident { return &ir.Ident{Name: s} }

// litInt is a shorthand for the only literal kind every emit-test
// fixture builds (integer literals dominate the loop / arithmetic
// coverage). String / bool / float literals are constructed inline at
// the few call sites that need them so the helper stays single-purpose.
func litInt(v string) *ir.Lit { return &ir.Lit{Kind: ir.LitInt, Value: v} }
