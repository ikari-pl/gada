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
	// Phase 2 — slice operations (Item 6).
	"slice_type_param", "slice_lit", "slice_index",
	"slice_subslice", "slice_append", "slice_len_cap",
	// Phase 2 — map operations (Item 7).
	"map_type_param", "map_lit", "map_index",
	"map_insert", "map_range", "map_delete",
	// Phase 2 — defer / panic / recover (Item 8).
	"defer_simple", "panic_simple", "recover_simple",
	// Phase 2 — main-side defer / panic (Item 9 emitMain wiring).
	"main_defer", "main_panic", "main_defer_panic",
	// Phase 3 — go-statement compiler emission.
	"go_simple", "go_main", "go_main_via_helper",
	// Phase 3 — go-statement argument capture (go f(x, y) snapshot).
	"go_with_args",
	// Phase 3 — channel-emit (sub-item b: make + per-element-type instantiation).
	"chan_make",
	// Phase 3 — channel-emit (sub-item c: c <- v send statement).
	"chan_send",
	// Phase 3 — channel-emit (sub-item d: v := <-c single-value receive).
	"chan_recv_single",
	// Phase 3 — channel-emit (sub-item e: v, ok := <-c comma-ok receive).
	"chan_recv_commaok",
	// Phase 3 — channel-emit (sub-item f: close(c) builtin).
	"chan_close",
	// Phase 3 — select-emit (sub-item d: full Select_One lowering).
	"select_basic",
	// Phase 3 — multi-arg fmt.Println with int rendering (ping_pong b).
	"println_mixed_args",
	// Phase 4 — type metadata emission (item 2c): Register_Type per type.
	"type_decl",
	// Phase 4 — interface satisfaction (item 4c-ii): Add_Method + Register.
	"iface_satisfy",
	// Phase 4 — struct type in package main (item 5a-i): record in Main.
	"struct_main",
	// Phase 4 — struct values: literals + field access (item 5a-ii).
	"struct_values",
	// Phase 4 — struct zero-value + partial literals (item 5a-iii).
	"struct_zero",
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
			wantErr: "literal or composite RHS",
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
	if !strings.Contains(out, `Print ("a""b");`) {
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

// TestSliceElementAssignment pins the `s[i] = v` lowering: assigning
// to a slice element must route through the runtime's `Set_Element`
// (1-based on the Ada side) rather than the default `lhs := rhs`
// path, which would emit `Slices_Of_T.Element (S, I + 1) := V;` and
// fail to compile because `Element` returns by-value. Equivalent
// guard to the map-side `m[k] = v -> Insert (M, K, V)` lowering
// already covered by the corpus.
func TestSliceElementAssignment(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name:   "set_first",
		Params: []*ir.Param{{Name: "s", Type: &ir.SliceType{Elem: &ir.IntType{}}}},
		Body: []ir.Stmt{&ir.Assign{
			LHS: []ir.Expr{&ir.IndexExpr{X: idn("s"), Index: litInt("0")}},
			RHS: []ir.Expr{litInt("42")},
		}},
	})
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	got := buf.String()
	want := "Slices_Of_Integer.Set_Element (S, 0 + 1, 42);"
	if !strings.Contains(got, want) {
		t.Fatalf("missing %q in output:\n%s", want, got)
	}
	// Ensure we did NOT fall through to the default `:=` path,
	// which would have emitted `:= 42;` (assignment to the
	// `Element` function's return value).
	if strings.Contains(got, "Element (S, 0 + 1) :=") {
		t.Fatalf("emitter fell through to invalid `Element (...) :=` path:\n%s", got)
	}
}

// TestRangeAssignFormRejected pins the Phase 2 emit guard that
// rejects `for k, v = range m` (Tok=ASSIGN). Define=false would
// otherwise silently emit an inner `K : T := …` shadow that
// diverges from Go's "write back to outer k/v each iteration"
// semantics. Phase 4 widens this to honour the assignment form.
func TestRangeAssignFormRejected(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name: "f",
		Params: []*ir.Param{{Name: "m",
			Type: &ir.MapType{Key: &ir.IntType{}, Value: &ir.IntType{}}}},
		Body: []ir.Stmt{&ir.RangeStmt{
			KeyName:   "k",
			ValueName: "v",
			Define:    false, // `=` form, not `:=`
			X:         idn("m"),
		}},
	})
	var buf bytes.Buffer
	err := Package(pkg, &buf)
	if err == nil {
		t.Fatalf("expected error, got success:\n%s", buf.String())
	}
	if !strings.Contains(err.Error(), "range with `=`") {
		t.Fatalf("wrong error: %v", err)
	}
}

// TestRangeBlankBypassesAssignGuard pins the corner case where the
// Define=false rejection only triggers if the range actually binds
// at least one name. `for range m` (no key, no value) is harmless
// regardless of Tok and must continue to emit the cursor walk.
func TestRangeBlankBypassesAssignGuard(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name: "count",
		Params: []*ir.Param{{Name: "m",
			Type: &ir.MapType{Key: &ir.IntType{}, Value: &ir.IntType{}}}},
		Results: []*ir.Param{{Type: &ir.IntType{}}},
		Body: []ir.Stmt{&ir.RangeStmt{Define: false, X: idn("m")},
			&ir.Return{Results: []ir.Expr{litInt("0")}}},
	})
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	if !strings.Contains(buf.String(), "Has_Element") {
		t.Fatalf("expected cursor walk, got:\n%s", buf.String())
	}
}

// TestRangeRestoresLocalTypes pins the localTypes save/restore so
// that a range-bound `k`/`v` does not poison subsequent dispatch
// for a same-named outer variable of a different type. Before the
// save/restore was added, `len(k)` after the range loop would
// route to `mapPkgFor`/`slicePkgFor` against the *map's* key type
// rather than the outer `k`'s real type.
func TestRangeRestoresLocalTypes(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name: "f",
		Params: []*ir.Param{
			{Name: "m", Type: &ir.MapType{Key: &ir.IntType{}, Value: &ir.IntType{}}},
			{Name: "outerK", Type: &ir.SliceType{Elem: &ir.IntType{}}},
		},
		Results: []*ir.Param{{Type: &ir.IntType{}}},
		Body: []ir.Stmt{
			&ir.RangeStmt{KeyName: "outerK", ValueName: "v", Define: true, X: idn("m")},
			// After the range, outerK must still be typed as a slice for
			// `len(outerK)` dispatch — not as an Integer (the map's key
			// type, which the range temporarily bound during the loop).
			&ir.Return{Results: []ir.Expr{
				&ir.BuiltinCall{Name: "len", Args: []ir.Expr{idn("outerK")}},
			}},
		},
	})
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	got := buf.String()
	// `len(outerK)` after the range must dispatch to the slice
	// `Length` call, not error out as a non-determinable instantiation.
	if !strings.Contains(got, "Slices_Of_Integer.Len (OuterK)") {
		t.Fatalf("expected post-range len to dispatch as slice, got:\n%s", got)
	}
}

// TestChanSendUnsupportedShapes pins the four early-out branches in
// chanPkgForExpr plus the matching `e.fail` path in emitChanSend.
// Each subtest constructs an IR fragment that the front-end (Go
// parser + translate) can't actually produce today — the goal is to
// keep the defensive branches exercised so a Phase 4 widening to
// chan-typed selectors / call results surfaces here, not at customer
// gprbuild time. The chan_send corpus fixture covers the happy path
// (bare-Ident-into-Channels_Of_T.Send); these tests cover everything
// else.
func TestChanSendUnsupportedShapes(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name string
		fn   *ir.Function
	}{
		// Branch A: chan operand is not an *ir.Ident at all (a literal,
		// in this case). emitChanSend's chanPkgForExpr lookup returns
		// false on the first type assertion.
		{"non-ident chan", &ir.Function{
			Name: "f",
			Body: []ir.Stmt{&ir.ChanSend{Chan: litInt("0"), Value: litInt("1")}},
		}},
		// Branch B: bare Ident, but no localTypes entry — i.e. the
		// front-end never declared `c` in this scope. chanPkgForExpr
		// gets past the type-assert but bounces on the map lookup.
		{"undeclared chan ident", &ir.Function{
			Name: "f",
			Body: []ir.Stmt{&ir.ChanSend{Chan: idn("c"), Value: litInt("1")}},
		}},
		// Branch C: bare Ident is in localTypes but as a non-chan type
		// (here, a plain `int` parameter). chanPkgForExpr passes both
		// type-assert and map-lookup but fails the *ir.ChanType cast.
		{"non-chan typed ident", &ir.Function{
			Name:   "f",
			Params: []*ir.Param{{Name: "c", Type: &ir.IntType{}}},
			Body:   []ir.Stmt{&ir.ChanSend{Chan: idn("c"), Value: litInt("1")}},
		}},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			pkg := wrapPkg(tc.fn)
			var buf bytes.Buffer
			err := Package(pkg, &buf)
			if err == nil {
				t.Fatalf("expected emit error, got success:\n%s", buf.String())
			}
			if !strings.Contains(err.Error(), "ChanSend") {
				t.Fatalf("wrong error (want substring \"ChanSend\"): %v", err)
			}
		})
	}
}

// TestChanRecvUnsupportedShapes pins the four reachable defensive
// branches around the `v := <-c` lowering: CommaOK rejection
// (sub-item d limit; sub-item e widens it), the three
// chanElemTypeOfExpr early-out branches (non-Ident, undeclared,
// non-ChanType ident), and the emitExpr ChanRecv arm that fires
// when `<-c` appears at general expression position. Mirror of
// TestChanSendUnsupportedShapes.
func TestChanRecvUnsupportedShapes(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		fn      *ir.Function
		wantSub string
	}{
		// Malformed IR: ChanRecv with CommaOK=true but only 1 LHS.
		// Sub-item (e) ships the comma-ok lowering, but the path is
		// gated on the 2-LHS branch in emitVarDecl. A translate bug
		// that produced CommaOK=true with only 1 LHS would land at the
		// defensive guard below — surface it loudly rather than silently
		// emit `V : Integer;` with no OK declaration.
		{"comma-ok with 1 lhs", &ir.Function{
			Name:   "f",
			Params: []*ir.Param{{Name: "c", Type: &ir.ChanType{Elem: &ir.IntType{}}}},
			Body: []ir.Stmt{&ir.Assign{
				Define: true,
				LHS:    []ir.Expr{idn("v")},
				RHS:    []ir.Expr{&ir.ChanRecv{Chan: idn("c"), CommaOK: true}},
			}},
		}, "must arrive via 2-LHS"},
		// chanElemTypeOfExpr branch A: non-Ident chan operand. The
		// receive RHS is a literal, which can't be chan-typed.
		{"non-ident chan operand", &ir.Function{
			Name: "f",
			Body: []ir.Stmt{&ir.Assign{
				Define: true,
				LHS:    []ir.Expr{idn("v")},
				RHS:    []ir.Expr{&ir.ChanRecv{Chan: litInt("0"), CommaOK: false}},
			}},
		}, "ChanRecv"},
		// chanElemTypeOfExpr branch B: bare Ident with no localTypes
		// entry — the chan is referenced but never declared.
		{"undeclared chan ident", &ir.Function{
			Name: "f",
			Body: []ir.Stmt{&ir.Assign{
				Define: true,
				LHS:    []ir.Expr{idn("v")},
				RHS:    []ir.Expr{&ir.ChanRecv{Chan: idn("c"), CommaOK: false}},
			}},
		}, "ChanRecv"},
		// chanElemTypeOfExpr branch C: bare Ident in localTypes but
		// as a non-chan type (here, an `int` parameter).
		{"non-chan typed ident", &ir.Function{
			Name:   "f",
			Params: []*ir.Param{{Name: "c", Type: &ir.IntType{}}},
			Body: []ir.Stmt{&ir.Assign{
				Define: true,
				LHS:    []ir.Expr{idn("v")},
				RHS:    []ir.Expr{&ir.ChanRecv{Chan: idn("c"), CommaOK: false}},
			}},
		}, "ChanRecv"},
		// emitExpr ChanRecv arm: `<-c` appears as the RHS of a
		// non-define Assign (`v = <-c`, where v is a pre-existing
		// variable). Sub-item (d) only handles the head-of-body
		// `:=` shape; this lands at emitAssign → emitExpr →
		// ChanRecv rejection arm.
		{"<-c at non-define assign rhs", &ir.Function{
			Name: "f",
			Params: []*ir.Param{
				{Name: "c", Type: &ir.ChanType{Elem: &ir.IntType{}}},
				{Name: "v", Type: &ir.IntType{}},
			},
			Body: []ir.Stmt{&ir.Assign{
				Define: false,
				LHS:    []ir.Expr{idn("v")},
				RHS:    []ir.Expr{&ir.ChanRecv{Chan: idn("c"), CommaOK: false}},
			}},
		}, "expression position"},
		// Comma-ok with second-LHS non-Ident: defensive guard in
		// emitChanRecvDecl that catches a translate bug producing
		// e.g. `lit, ok := <-c` (impossible from real Go source, but
		// IR-level fabrication needs a clear failure axis).
		{"comma-ok 2nd lhs non-ident", &ir.Function{
			Name:   "f",
			Params: []*ir.Param{{Name: "c", Type: &ir.ChanType{Elem: &ir.IntType{}}}},
			Body: []ir.Stmt{&ir.Assign{
				Define: true,
				LHS:    []ir.Expr{idn("v"), litInt("0")},
				RHS:    []ir.Expr{&ir.ChanRecv{Chan: idn("c"), CommaOK: true}},
			}},
		}, "second lhs"},
		// Comma-ok with first-LHS non-Ident: same defensive guard
		// (V identifier slot).
		{"comma-ok 1st lhs non-ident", &ir.Function{
			Name:   "f",
			Params: []*ir.Param{{Name: "c", Type: &ir.ChanType{Elem: &ir.IntType{}}}},
			Body: []ir.Stmt{&ir.Assign{
				Define: true,
				LHS:    []ir.Expr{litInt("0"), idn("ok")},
				RHS:    []ir.Expr{&ir.ChanRecv{Chan: idn("c"), CommaOK: true}},
			}},
		}, "plain identifier"},
		// Comma-ok with non-chan operand: chanElemTypeOfExpr fails on
		// the comma-ok path (sub-item d already pinned this for the
		// single-value path; mirror the case so both code paths
		// through emitChanRecvDecl exercise the chan-resolution
		// rejection).
		{"comma-ok non-chan operand", &ir.Function{
			Name:   "f",
			Params: []*ir.Param{{Name: "c", Type: &ir.IntType{}}},
			Body: []ir.Stmt{&ir.Assign{
				Define: true,
				LHS:    []ir.Expr{idn("v"), idn("ok")},
				RHS:    []ir.Expr{&ir.ChanRecv{Chan: idn("c"), CommaOK: true}},
			}},
		}, "ChanRecv"},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			pkg := wrapPkg(tc.fn)
			var buf bytes.Buffer
			err := Package(pkg, &buf)
			if err == nil {
				t.Fatalf("expected emit error, got success:\n%s", buf.String())
			}
			if !strings.Contains(err.Error(), tc.wantSub) {
				t.Fatalf("wrong error (want substring %q): %v", tc.wantSub, err)
			}
		})
	}
}

// TestSelectorInstantiationsPrelude pins the file-level prelude
// landed in sub-item (c): a SelectStmt whose case operand is a
// chan-typed Ident emits the `with Gada.Async.Selector;` umbrella
// and one `package Selectors_Of_<T> is new Gada.Async.Selector (…)`
// block per distinct element type the select references. Sub-item
// (d) replaced the original `null;` body placeholder with the real
// Case_Array build + Select_One call, so the assertions also check
// for the Sel_Cases_1 declaration as a proxy for the body lowering
// having fired — the full body shape lives in select_basic.golden.adb.
func TestSelectorInstantiationsPrelude(t *testing.T) {
	t.Parallel()

	// Case A: chan-typed PARAMETER drives chanIdentTypes via the
	// fn.Params pre-scan in collectSliceElems. One Recv case is
	// enough to drive the Selectors_Of_<T> recording path.
	t.Run("chan param operand", func(t *testing.T) {
		t.Parallel()
		pkg := wrapPkg(&ir.Function{
			Name:   "f",
			Params: []*ir.Param{{Name: "c", Type: &ir.ChanType{Elem: &ir.IntType{}}}},
			Body: []ir.Stmt{&ir.SelectStmt{
				Cases: []*ir.SelectCase{
					{Kind: ir.SelectCaseRecv, Chan: idn("c")},
				},
			}},
		})
		var buf bytes.Buffer
		if err := Package(pkg, &buf); err != nil {
			t.Fatalf("emit: %v", err)
		}
		got := buf.String()
		for _, want := range []string{
			"with Gada.Async.Channels.Bounded;",
			"with Gada.Async.Selector;",
			"package Channels_Of_Integer is new Gada.Async.Channels.Bounded (Element_Type => Integer);",
			"package Selectors_Of_Integer is new Gada.Async.Selector",
			"(Element_Type    => Integer,",
			"Default_Element => 0,",
			"Bnd             => Channels_Of_Integer);",
			"Sel_Cases_1 : Selectors_Of_Integer.Case_Array",
		} {
			if !strings.Contains(got, want) {
				t.Fatalf("missing %q in output:\n%s", want, got)
			}
		}
	})

	// Case B: chan-typed HEAD-OF-BODY LOCAL drives chanIdentTypes via
	// the fn.Body pre-scan in collectSliceElems. A `c := make(chan T,
	// N)` define is the only IR shape that exercises that branch;
	// select cases referencing the local resolve through the same
	// chanIdentTypes map. Assertions mirror the chan-param case
	// exactly so a regression that breaks the local-resolution path
	// surfaces with the same failure shape as a regression that
	// breaks the param-resolution path.
	t.Run("chan local operand", func(t *testing.T) {
		t.Parallel()
		pkg := wrapPkg(&ir.Function{
			Name: "f",
			Body: []ir.Stmt{
				&ir.Assign{
					Define: true,
					LHS:    []ir.Expr{idn("c")},
					RHS: []ir.Expr{&ir.MakeChan{
						Elem:     &ir.IntType{},
						Capacity: litInt("4"),
					}},
				},
				&ir.SelectStmt{
					Cases: []*ir.SelectCase{
						{Kind: ir.SelectCaseRecv, Chan: idn("c")},
					},
				},
			},
		})
		var buf bytes.Buffer
		if err := Package(pkg, &buf); err != nil {
			t.Fatalf("emit: %v", err)
		}
		got := buf.String()
		for _, want := range []string{
			"with Gada.Async.Channels.Bounded;",
			"with Gada.Async.Selector;",
			"package Channels_Of_Integer is new Gada.Async.Channels.Bounded (Element_Type => Integer);",
			"package Selectors_Of_Integer is new Gada.Async.Selector",
			"(Element_Type    => Integer,",
			"Default_Element => 0,",
			"Bnd             => Channels_Of_Integer);",
			"Sel_Cases_1 : Selectors_Of_Integer.Case_Array",
		} {
			if !strings.Contains(got, want) {
				t.Fatalf("missing %q in output:\n%s", want, got)
			}
		}
	})
}

// TestSelectStmtEdgeCases covers the five reachable code paths in
// emitSelectStmt that aren't exercised by the select_basic corpus
// fixture: empty select, all-Default degenerate (both with and
// without a body), non-Ident chan operand, undeclared chan operand,
// and heterogeneous-Element_Type rejection. Together with the
// corpus golden they take emitSelectStmt to full coverage.
func TestSelectStmtEdgeCases(t *testing.T) {
	t.Parallel()

	// 1. Empty select. Go's `select {}` is the deadlock-forever
	//    shape; emit lowers to Program_Error so the source intent
	//    is preserved.
	t.Run("empty select", func(t *testing.T) {
		t.Parallel()
		pkg := wrapPkg(&ir.Function{
			Name: "f",
			Body: []ir.Stmt{&ir.SelectStmt{Cases: nil}},
		})
		var buf bytes.Buffer
		if err := Package(pkg, &buf); err != nil {
			t.Fatalf("emit: %v", err)
		}
		if !strings.Contains(buf.String(), "raise Program_Error with \"select with no cases") {
			t.Fatalf("missing empty-select Program_Error in output:\n%s", buf.String())
		}
	})

	// 2. All-Default degenerate with non-empty body. Emit skips
	//    Select_One and inlines the default body directly.
	t.Run("all-default with body", func(t *testing.T) {
		t.Parallel()
		pkg := wrapPkg(&ir.Function{
			Name: "f",
			Body: []ir.Stmt{&ir.SelectStmt{
				Cases: []*ir.SelectCase{
					{Kind: ir.SelectCaseDefault, Body: []ir.Stmt{
						&ir.ExprStmt{X: idn("x")},
					}},
				},
			}},
		})
		var buf bytes.Buffer
		if err := Package(pkg, &buf); err != nil {
			t.Fatalf("emit: %v", err)
		}
		out := buf.String()
		if strings.Contains(out, "Select_One") {
			t.Fatalf("all-default select should skip Select_One:\n%s", out)
		}
		if strings.Contains(out, "Sel_Cases") {
			t.Fatalf("all-default select should skip Case_Array build:\n%s", out)
		}
	})

	// 3. All-Default degenerate with empty body. Falls through to
	//    `null;` to satisfy Ada's "block needs a statement" rule.
	t.Run("all-default with empty body", func(t *testing.T) {
		t.Parallel()
		pkg := wrapPkg(&ir.Function{
			Name: "f",
			Body: []ir.Stmt{&ir.SelectStmt{
				Cases: []*ir.SelectCase{
					{Kind: ir.SelectCaseDefault, Body: nil},
				},
			}},
		})
		var buf bytes.Buffer
		if err := Package(pkg, &buf); err != nil {
			t.Fatalf("emit: %v", err)
		}
		if strings.Contains(buf.String(), "Select_One") {
			t.Fatalf("all-default empty-body select should skip Select_One:\n%s", buf.String())
		}
	})

	// 4. Non-Ident chan operand. Sub-item-(d) emit rejects with a
	//    clear error pointing at the Phase 4 widening.
	t.Run("non-ident chan operand", func(t *testing.T) {
		t.Parallel()
		pkg := wrapPkg(&ir.Function{
			Name: "f",
			Body: []ir.Stmt{&ir.SelectStmt{
				Cases: []*ir.SelectCase{
					{Kind: ir.SelectCaseRecv, Chan: litInt("0")},
				},
			}},
		})
		var buf bytes.Buffer
		err := Package(pkg, &buf)
		if err == nil {
			t.Fatalf("expected emit error, got success:\n%s", buf.String())
		}
		if !strings.Contains(err.Error(), "bare identifier") {
			t.Fatalf("wrong error: %v", err)
		}
	})

	// 5. Undeclared chan ident. The ident isn't a function
	//    parameter and isn't a head-of-body `make` local, so
	//    chanIdentTypes has no entry for it.
	t.Run("undeclared chan ident", func(t *testing.T) {
		t.Parallel()
		pkg := wrapPkg(&ir.Function{
			Name: "f",
			Body: []ir.Stmt{&ir.SelectStmt{
				Cases: []*ir.SelectCase{
					{Kind: ir.SelectCaseRecv, Chan: idn("c")},
				},
			}},
		})
		var buf bytes.Buffer
		err := Package(pkg, &buf)
		if err == nil {
			t.Fatalf("expected emit error, got success:\n%s", buf.String())
		}
		if !strings.Contains(err.Error(), "undeclared chan ident") {
			t.Fatalf("wrong error: %v", err)
		}
	})

	// 6. Heterogeneous select: two chan params with different
	//    element types. v1 rejects pointing at Phase 4 widening.
	t.Run("mixed element types", func(t *testing.T) {
		t.Parallel()
		pkg := wrapPkg(&ir.Function{
			Name: "f",
			Params: []*ir.Param{
				{Name: "ci", Type: &ir.ChanType{Elem: &ir.IntType{}}},
				{Name: "cs", Type: &ir.ChanType{Elem: &ir.StringType{}}},
			},
			Body: []ir.Stmt{&ir.SelectStmt{
				Cases: []*ir.SelectCase{
					{Kind: ir.SelectCaseRecv, Chan: idn("ci")},
					{Kind: ir.SelectCaseRecv, Chan: idn("cs")},
				},
			}},
		})
		var buf bytes.Buffer
		err := Package(pkg, &buf)
		if err == nil {
			t.Fatalf("expected emit error, got success:\n%s", buf.String())
		}
		if !strings.Contains(err.Error(), "heterogeneous select") {
			t.Fatalf("wrong error: %v", err)
		}
	})
}

// TestChanCloseUnsupportedShapes pins the two reachable defensive
// branches in emitChanClose: arg-count check (front-end *should*
// already reject `close()` with no args or `close(c, x)` with two,
// but Phase 2 has no `close` typecheck — the IR boundary is the
// only place that catches a translate bug producing the wrong
// shape) and non-chan-operand check (mirror of the receive- and
// send-side guards).
func TestChanCloseUnsupportedShapes(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		fn      *ir.Function
		wantSub string
	}{
		// Arg count: close takes exactly one chan operand. Zero args
		// is the IR-level fabrication that emitChanClose's len check
		// catches.
		{"close zero args", &ir.Function{
			Name: "f",
			Body: []ir.Stmt{&ir.BuiltinCall{Name: "close"}},
		}, "exactly 1 arg"},
		// Two args is the symmetric case; same arg-count guard.
		{"close two args", &ir.Function{
			Name:   "f",
			Params: []*ir.Param{{Name: "c", Type: &ir.ChanType{Elem: &ir.IntType{}}}},
			Body: []ir.Stmt{&ir.BuiltinCall{
				Name: "close",
				Args: []ir.Expr{idn("c"), litInt("0")},
			}},
		}, "exactly 1 arg"},
		// Non-chan operand: close on a plain int param triggers the
		// chanPkgForExpr-fails branch.
		{"close on non-chan", &ir.Function{
			Name:   "f",
			Params: []*ir.Param{{Name: "c", Type: &ir.IntType{}}},
			Body: []ir.Stmt{&ir.BuiltinCall{
				Name: "close",
				Args: []ir.Expr{idn("c")},
			}},
		}, "close on non-chan"},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			pkg := wrapPkg(tc.fn)
			var buf bytes.Buffer
			err := Package(pkg, &buf)
			if err == nil {
				t.Fatalf("expected emit error, got success:\n%s", buf.String())
			}
			if !strings.Contains(err.Error(), tc.wantSub) {
				t.Fatalf("wrong error (want substring %q): %v", tc.wantSub, err)
			}
		})
	}
}

// TestSliceEmitErrors covers every error branch reachable from the
// new Phase 2 slice-emission paths. Each entry pins one specific
// failure mode so a future regression surfaces at the right call
// site rather than as an opaque "got %T" line.
func TestSliceEmitErrors(t *testing.T) {
	t.Parallel()

	intSliceParam := []*ir.Param{{Name: "s", Type: &ir.SliceType{Elem: &ir.IntType{}}}}
	intSliceResult := []*ir.Param{{Type: &ir.SliceType{Elem: &ir.IntType{}}}}

	cases := []struct {
		name    string
		pkg     *ir.Package
		wantErr string
	}{
		{
			name: "slice of slice element rejected",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Params: []*ir.Param{{Name: "s",
					Type: &ir.SliceType{Elem: &ir.SliceType{Elem: &ir.IntType{}}}}},
			}),
			wantErr: "unsupported slice element type",
		},
		{
			name: "index expr on non-slice ident",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Params:  []*ir.Param{{Name: "x", Type: &ir.IntType{}}},
				Results: []*ir.Param{{Type: &ir.IntType{}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.IndexExpr{X: idn("x"), Index: litInt("0")},
				}}},
			}),
			wantErr: "cannot determine slice/map instantiation",
		},
		{
			name: "index expr on non-ident X",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Params:  intSliceParam,
				Results: []*ir.Param{{Type: &ir.IntType{}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.IndexExpr{
						X:     &ir.SliceLit{Elem: &ir.IntType{}},
						Index: litInt("0"),
					},
				}}},
			}),
			wantErr: "cannot determine slice/map instantiation",
		},
		{
			name: "slice expr on non-ident X",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Params:  intSliceParam,
				Results: intSliceResult,
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.SliceExpr{
						X:    &ir.SliceLit{Elem: &ir.IntType{}},
						Low:  litInt("0"),
						High: litInt("1"),
					},
				}}},
			}),
			wantErr: "cannot determine slice instantiation",
		},
		{
			name: "len on unknown ident",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Results: []*ir.Param{{Type: &ir.IntType{}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.BuiltinCall{Name: "len", Args: []ir.Expr{idn("nope")}},
				}}},
			}),
			wantErr: "cannot determine slice instantiation",
		},
		{
			name: "append wrong arity",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Params:  intSliceParam,
				Results: intSliceResult,
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.BuiltinCall{Name: "append", Args: []ir.Expr{idn("s")}},
				}}},
			}),
			wantErr: "append-of-N values not supported",
		},
		{
			name: "len wrong arity",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Params:  intSliceParam,
				Results: []*ir.Param{{Type: &ir.IntType{}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.BuiltinCall{Name: "len", Args: []ir.Expr{idn("s"), idn("s")}},
				}}},
			}),
			wantErr: "len takes exactly 1 arg",
		},
		{
			name: "cap wrong arity",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Params:  intSliceParam,
				Results: []*ir.Param{{Type: &ir.IntType{}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.BuiltinCall{Name: "cap", Args: []ir.Expr{idn("s"), idn("s")}},
				}}},
			}),
			wantErr: "cap takes exactly 1 arg",
		},
		{
			name: "builtin zero args (slice path)",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Results: []*ir.Param{{Type: &ir.IntType{}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.BuiltinCall{Name: "len", Args: nil},
				}}},
			}),
			wantErr: "requires at least 1 arg",
		},
		{
			name: "unsupported builtin in expression position",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Results: []*ir.Param{{Type: &ir.IntType{}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.BuiltinCall{Name: "delete", Args: []ir.Expr{idn("m"), idn("k")}},
				}}},
			}),
			wantErr: `cannot determine map instantiation for "delete"`,
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := Package(tc.pkg, &bytes.Buffer{})
			if err == nil {
				t.Fatalf("expected error containing %q, got nil", tc.wantErr)
			}
			if !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("error %q does not contain %q", err.Error(), tc.wantErr)
			}
		})
	}
}

// TestSliceEmptyLitDispatch covers the `[]int{}` empty-literal
// shortcut which routes to the runtime's `Slices_Of_Integer.Empty`
// constant rather than the From_Array call. The corpus uses non-
// empty literals only, so this is the dedicated assertion.
func TestSliceEmptyLitDispatch(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name:    "zero",
		Results: []*ir.Param{{Type: &ir.SliceType{Elem: &ir.IntType{}}}},
		Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
			&ir.SliceLit{Elem: &ir.IntType{}},
		}}},
	})
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	if !strings.Contains(buf.String(), "return Slices_Of_Integer.Empty;") {
		t.Fatalf("expected Slices_Of_Integer.Empty dispatch, got:\n%s", buf.String())
	}
}

// TestSliceLitInVarDecl exercises the `:=` declaration path where
// the RHS is a SliceLit (the corpus uses SliceLit only as a return
// expression, so the inferDeclType slice branch is otherwise dead).
func TestSliceLitInVarDecl(t *testing.T) {
	t.Parallel()
	pkg := wrapMain(funcMain(
		&ir.Assign{Define: true,
			LHS: []ir.Expr{idn("xs")},
			RHS: []ir.Expr{&ir.SliceLit{
				Elem:  &ir.IntType{},
				Elems: []ir.Expr{litInt("1"), litInt("2")},
			}},
		},
	))
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	out := buf.String()
	if !strings.Contains(out, "Xs : Slices_Of_Integer.Slice := Slices_Of_Integer.From_Array ([1, 2]);") {
		t.Fatalf("expected slice := decl, got:\n%s", out)
	}
}

// TestInferRHSTypeNonIntLits covers inferRHSType's bool/string/float
// branches which the corpus does not reach via SliceLit.
func TestInferRHSTypeNonIntLits(t *testing.T) {
	t.Parallel()
	cases := []struct {
		lit  *ir.Lit
		want ir.Type
	}{
		{&ir.Lit{Kind: ir.LitInt, Value: "1"}, &ir.IntType{}},
		{&ir.Lit{Kind: ir.LitString, Value: `"x"`}, &ir.StringType{}},
		{&ir.Lit{Kind: ir.LitBool, Value: "true"}, &ir.BoolType{}},
		{&ir.Lit{Kind: ir.LitFloat, Value: "1.5"}, &ir.Float64Type{}},
	}
	for _, tc := range cases {
		got, ok := inferRHSType(tc.lit)
		if !ok {
			t.Fatalf("inferRHSType(%v) = (_, false), want true", tc.lit)
		}
		if reflectKind(got) != reflectKind(tc.want) {
			t.Errorf("inferRHSType(%v) = %T, want %T", tc.lit, got, tc.want)
		}
	}
	// Unknown LitKind bows out with ok=false.
	if _, ok := inferRHSType(&ir.Lit{Kind: "bogus"}); ok {
		t.Fatal("inferRHSType(bogus literal) should report ok=false")
	}
	// Non-literal, non-SliceLit: also bows out.
	if _, ok := inferRHSType(idn("x")); ok {
		t.Fatal("inferRHSType(*ir.Ident) should report ok=false")
	}
}

func reflectKind(t ir.Type) string {
	if t == nil {
		return "<nil>"
	}
	return t.NodeKind()
}

// TestElemBaseNameTable pins elemBaseName's basic-type table and the
// rejection of any non-basic element. The slice fixtures only
// exercise IntType; the other three basic types and the rejection
// branch live here.
func TestElemBaseNameTable(t *testing.T) {
	t.Parallel()
	cases := []struct {
		t    ir.Type
		want string
	}{
		{&ir.IntType{}, "Integer"},
		{&ir.StringType{}, "String"},
		{&ir.BoolType{}, "Boolean"},
		{&ir.Float64Type{}, "Long_Float"},
	}
	for _, tc := range cases {
		got, err := elemBaseName(tc.t)
		if err != nil {
			t.Fatalf("elemBaseName(%T): unexpected error %v", tc.t, err)
		}
		if got != tc.want {
			t.Errorf("elemBaseName(%T) = %q, want %q", tc.t, got, tc.want)
		}
	}
	if _, err := elemBaseName(&ir.SliceType{Elem: &ir.IntType{}}); err == nil {
		t.Fatal("expected error for slice-of-slice element type")
	}
	if _, err := slicePkgFor(&ir.SliceType{Elem: &ir.IntType{}}); err == nil {
		t.Fatal("expected slicePkgFor to propagate the slice-of-slice error")
	}
}

// TestTypeNameSliceAndMissing covers typeName's Phase 2 SliceType
// case and the explicit nil/missing-type branch.
func TestTypeNameSliceAndMissing(t *testing.T) {
	t.Parallel()
	got, err := typeName(&ir.SliceType{Elem: &ir.StringType{}})
	if err != nil {
		t.Fatalf("typeName(SliceType{StringType}): unexpected error %v", err)
	}
	if got != "Slices_Of_String.Slice" {
		t.Errorf("typeName(SliceType{StringType}) = %q, want %q", got, "Slices_Of_String.Slice")
	}
	if _, err := typeName(nil); err == nil {
		t.Fatal("expected error for nil type")
	}
}

// TestEmitSliceLitOfStringFloatBool covers the three basic-type slice
// instantiations the corpus does not exercise (corpus is integer-
// only). Together with TestEmitCorpus they pin every basic-type
// slice path.
func TestEmitSliceLitOfStringFloatBool(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name     string
		elem     ir.Type
		wantInst string
	}{
		{"string", &ir.StringType{},
			"package Slices_Of_String is new Gada.Core.Slices (Element_Type => String);"},
		{"bool", &ir.BoolType{},
			"package Slices_Of_Boolean is new Gada.Core.Slices (Element_Type => Boolean);"},
		{"float64", &ir.Float64Type{},
			"package Slices_Of_Long_Float is new Gada.Core.Slices (Element_Type => Long_Float);"},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			pkg := wrapPkg(&ir.Function{
				Name:    "f",
				Results: []*ir.Param{{Type: &ir.SliceType{Elem: tc.elem}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.SliceLit{Elem: tc.elem},
				}}},
			})
			var buf bytes.Buffer
			if err := Package(pkg, &buf); err != nil {
				t.Fatalf("emit: %v", err)
			}
			if !strings.Contains(buf.String(), tc.wantInst) {
				t.Fatalf("expected %q in:\n%s", tc.wantInst, buf.String())
			}
		})
	}
}

// TestMapEmitErrors covers every error branch reachable from the
// new Phase 2 map-emission paths. Each case pins one specific failure
// mode so a future regression surfaces at the right call site rather
// than as an opaque "got %T" line. Together with TestSliceEmitErrors
// these pin the negative-space surface of the per-call dispatchers.
func TestMapEmitErrors(t *testing.T) {
	t.Parallel()

	intMap := &ir.MapType{Key: &ir.IntType{}, Value: &ir.IntType{}}
	intMapParam := []*ir.Param{{Name: "m", Type: intMap}}

	cases := []struct {
		name    string
		pkg     *ir.Package
		wantErr string
	}{
		{
			name: "unsupported map key type (string awaits Phase 4)",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Params: []*ir.Param{{Name: "m",
					Type: &ir.MapType{Key: &ir.StringType{}, Value: &ir.IntType{}}}},
			}),
			wantErr: "map keys of type string await Phase 4",
		},
		{
			name: "unsupported map value type (string awaits Phase 4)",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Params: []*ir.Param{{Name: "m",
					Type: &ir.MapType{Key: &ir.IntType{}, Value: &ir.StringType{}}}},
			}),
			wantErr: "map values of type string await Phase 4",
		},
		{
			name: "delete wrong arity",
			pkg: wrapPkg(&ir.Function{
				Name:   "f",
				Params: intMapParam,
				Body: []ir.Stmt{
					&ir.BuiltinCall{Name: "delete", Args: []ir.Expr{idn("m")}},
				},
			}),
			wantErr: "delete takes exactly 2 args",
		},
		{
			name: "len(map) wrong arity",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Params:  intMapParam,
				Results: []*ir.Param{{Type: &ir.IntType{}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.BuiltinCall{Name: "len", Args: []ir.Expr{idn("m"), idn("m")}},
				}}},
			}),
			// emitBuiltinCall only routes to emitMapBuiltin when arity==1;
			// arity≠1 falls through to slice path, which fails first arg
			// resolution because m is a map ident.
			wantErr: "cannot determine slice instantiation",
		},
		{
			name: "delete on non-map ident (no instantiation)",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Body: []ir.Stmt{
					&ir.BuiltinCall{Name: "delete", Args: []ir.Expr{idn("nope"), litInt("1")}},
				},
			}),
			wantErr: `cannot determine map instantiation for "delete"`,
		},
		{
			name: "delete zero args (stmt position)",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Body: []ir.Stmt{
					&ir.BuiltinCall{Name: "delete", Args: nil},
				},
			}),
			wantErr: `requires at least 1 arg`,
		},
		{
			name: "stmt-position builtin not delete",
			pkg: wrapPkg(&ir.Function{
				Name:   "f",
				Params: intMapParam,
				Body: []ir.Stmt{
					&ir.BuiltinCall{Name: "len", Args: []ir.Expr{idn("m")}},
				},
			}),
			wantErr: `builtin "len" at statement position not supported`,
		},
		{
			name: "range over non-map (non-Ident X)",
			pkg: wrapPkg(&ir.Function{
				Name:   "f",
				Params: intMapParam,
				Body: []ir.Stmt{
					&ir.RangeStmt{
						KeyName: "k", ValueName: "v", Define: true,
						X:    &ir.MapLit{Key: &ir.IntType{}, Value: &ir.IntType{}},
						Body: nil,
					},
				},
			}),
			wantErr: "range supports only map values in Phase 2",
		},
		{
			name: "range over unknown ident",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Body: []ir.Stmt{
					&ir.RangeStmt{
						KeyName: "k", ValueName: "v", Define: true,
						X:    idn("nope"),
						Body: nil,
					},
				},
			}),
			wantErr: "range supports only map values in Phase 2",
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := Package(tc.pkg, &bytes.Buffer{})
			if err == nil {
				t.Fatalf("expected error containing %q, got nil", tc.wantErr)
			}
			if !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("error %q does not contain %q", err.Error(), tc.wantErr)
			}
		})
	}
}

// TestMapKeyValueBaseNameTable pins the basic-type acceptance table
// for map keys and values plus the explicit Phase-4 deferral message
// for String. The corpus only exercises Integer→Integer, so the
// other supported pairs and the rejection branches live here.
func TestMapKeyValueBaseNameTable(t *testing.T) {
	t.Parallel()
	keyAccepts := []struct {
		t    ir.Type
		want string
	}{
		{&ir.IntType{}, "Integer"},
		{&ir.BoolType{}, "Boolean"},
		{&ir.Float64Type{}, "Long_Float"},
	}
	for _, tc := range keyAccepts {
		got, err := mapKeyBaseName(tc.t)
		if err != nil {
			t.Fatalf("mapKeyBaseName(%T): unexpected error %v", tc.t, err)
		}
		if got != tc.want {
			t.Errorf("mapKeyBaseName(%T) = %q, want %q", tc.t, got, tc.want)
		}
	}
	if _, err := mapKeyBaseName(&ir.StringType{}); err == nil {
		t.Fatal("mapKeyBaseName(StringType): expected Phase-4 deferral error")
	}
	if _, err := mapKeyBaseName(&ir.SliceType{Elem: &ir.IntType{}}); err == nil {
		t.Fatal("mapKeyBaseName(SliceType): expected unsupported-type error")
	}

	for _, tc := range keyAccepts {
		got, err := mapValueBaseName(tc.t)
		if err != nil {
			t.Fatalf("mapValueBaseName(%T): unexpected error %v", tc.t, err)
		}
		if got != tc.want {
			t.Errorf("mapValueBaseName(%T) = %q, want %q", tc.t, got, tc.want)
		}
	}
	if _, err := mapValueBaseName(&ir.StringType{}); err == nil {
		t.Fatal("mapValueBaseName(StringType): expected Phase-4 deferral error")
	}
	if _, err := mapValueBaseName(&ir.SliceType{Elem: &ir.IntType{}}); err == nil {
		t.Fatal("mapValueBaseName(SliceType): expected unsupported-type error")
	}

	// mapPairKey propagates both branches; mapPkgFor in turn propagates
	// mapPairKey. Pin both forwarders so a refactor that swaps to a
	// silent fallback fails here.
	if _, err := mapPairKey(&ir.MapType{Key: &ir.StringType{}, Value: &ir.IntType{}}); err == nil {
		t.Fatal("mapPairKey: expected key-side error to propagate")
	}
	if _, err := mapPairKey(&ir.MapType{Key: &ir.IntType{}, Value: &ir.StringType{}}); err == nil {
		t.Fatal("mapPairKey: expected value-side error to propagate")
	}
	if _, err := mapPkgFor(&ir.MapType{Key: &ir.StringType{}, Value: &ir.IntType{}}); err == nil {
		t.Fatal("mapPkgFor: expected error to propagate from mapPairKey")
	}
}

// TestMapDefaultLiteralTable pins the per-value-type Default_Value
// formal the runtime instantiation receives. Integer is corpus-
// covered; the other two basic types and the unreachable-fallback
// guard live here.
func TestMapDefaultLiteralTable(t *testing.T) {
	t.Parallel()
	cases := []struct {
		t    ir.Type
		want string
	}{
		{&ir.IntType{}, "0"},
		{&ir.BoolType{}, "False"},
		{&ir.Float64Type{}, "0.0"},
		// Unreachable-fallback for an unsupported value type. recordMapPair
		// already filters these in the pre-scan, so this case proves the
		// fallback isn't load-bearing — but we keep it in case a future
		// refactor changes the dispatch order.
		{&ir.StringType{}, "0"},
	}
	for _, tc := range cases {
		got := mapDefaultLiteral(tc.t)
		if got != tc.want {
			t.Errorf("mapDefaultLiteral(%T) = %q, want %q", tc.t, got, tc.want)
		}
	}
}

// TestMapInstantiationViaResultType drives recordTypeInTree's
// MapType case via a function *result* (rather than a parameter, as
// the corpus uses). The corpus's map fixtures all have map params
// only; the result-type branch needs separate cover.
func TestMapInstantiationViaResultType(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name:    "make_one",
		Results: []*ir.Param{{Type: &ir.MapType{Key: &ir.IntType{}, Value: &ir.BoolType{}}}},
		Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
			&ir.MapLit{Key: &ir.IntType{}, Value: &ir.BoolType{}},
		}}},
	})
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	out := buf.String()
	if !strings.Contains(out, "Maps_Of_Integer_To_Boolean") {
		t.Fatalf("expected Maps_Of_Integer_To_Boolean instantiation, got:\n%s", out)
	}
	if !strings.Contains(out, "Default_Value => False") {
		t.Fatalf("expected Default_Value => False, got:\n%s", out)
	}
}

// TestMapLitNonEmptyInVarDecl drives emitMapLit through the
// non-empty `:=` declaration path (the corpus covers only function-
// body composite literals; the `:=` flow is reachable from elided-
// type contexts that the translator-side accepts).
func TestMapLitNonEmptyInVarDecl(t *testing.T) {
	t.Parallel()
	pkg := wrapMain(funcMain(
		&ir.Assign{Define: true,
			LHS: []ir.Expr{idn("m")},
			RHS: []ir.Expr{&ir.MapLit{
				Key: &ir.IntType{}, Value: &ir.IntType{},
				Entries: []*ir.MapEntry{{Key: litInt("1"), Value: litInt("2")}},
			}},
		},
	))
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	out := buf.String()
	if !strings.Contains(out, "M : Maps_Of_Integer_To_Integer.Map :=") {
		t.Fatalf("expected map := decl, got:\n%s", out)
	}
	if !strings.Contains(out, "From_Pairs ([(K => 1, V => 2)])") {
		t.Fatalf("expected From_Pairs aggregate, got:\n%s", out)
	}
}

// TestDeferPanicEmitErrors covers every error branch reachable from
// the new Phase 2 defer/panic/recover emission paths. Each case pins
// one specific failure mode so a future regression surfaces at the
// right call site.
func TestDeferPanicEmitErrors(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		pkg     *ir.Package
		wantErr string
	}{
		{
			name: "panic wrong arity (0 args, stmt)",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Body: []ir.Stmt{
					&ir.BuiltinCall{Name: "panic", Args: nil},
				},
			}),
			wantErr: "panic takes exactly 1 arg",
		},
		{
			name: "panic in expression position (return)",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Results: []*ir.Param{{Type: &ir.IntType{}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.BuiltinCall{Name: "panic", Args: []ir.Expr{litInt("1")}},
				}}},
			}),
			wantErr: "panic in expression position",
		},
		{
			name: "recover with args (in return)",
			pkg: wrapPkg(&ir.Function{
				Name:    "f",
				Results: []*ir.Param{{Type: &ir.IntType{}}},
				Body: []ir.Stmt{&ir.Return{Results: []ir.Expr{
					&ir.BuiltinCall{Name: "recover", Args: []ir.Expr{litInt("1")}},
				}}},
			}),
			wantErr: "recover takes no args",
		},
		{
			name: "defer holds unexpected stmt (Return)",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Body: []ir.Stmt{&ir.DeferStmt{Call: &ir.Return{}}},
			}),
			wantErr: "defer holds unexpected stmt",
		},
		{
			// go-with-args to a name that has no top-level function in
			// the file: there is no signature to shape the closure from.
			name: "go-stmt args: unknown callee",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Body: []ir.Stmt{&ir.GoStmt{Call: &ir.Call{
					Fun:  idn("consume"),
					Args: []ir.Expr{litInt("5")},
				}}},
			}),
			wantErr: "no top-level function",
		},
		{
			// go-with-args where the entry point is a builtin (panic),
			// not a user function — no Function decl to capture against.
			name: "go-stmt args: builtin callee",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Body: []ir.Stmt{&ir.GoStmt{Call: &ir.BuiltinCall{
					Name: "panic",
					Args: []ir.Expr{litInt("1")},
				}}},
			}),
			wantErr: "supports only direct user-function calls",
		},
		{
			// go-with-args whose call target is not a plain identifier
			// (here a literal stands in for any non-Ident Fun shape).
			name: "go-stmt args: non-ident callee",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Body: []ir.Stmt{&ir.GoStmt{Call: &ir.Call{
					Fun:  litInt("1"),
					Args: []ir.Expr{litInt("5")},
				}}},
			}),
			wantErr: "must be a plain function name",
		},
		{
			// go g(1, 2) but g declares a single parameter.
			name: "go-stmt args: arg/param count mismatch",
			pkg: wrapPkg(
				&ir.Function{
					Name:   "g",
					Params: []*ir.Param{{Name: "x", Type: &ir.IntType{}}},
				},
				&ir.Function{
					Name: "f",
					Body: []ir.Stmt{&ir.GoStmt{Call: &ir.Call{
						Fun:  idn("g"),
						Args: []ir.Expr{litInt("1"), litInt("2")},
					}}},
				},
			),
			wantErr: "declares 1 parameter",
		},
		{
			// callee parameter whose type emit cannot render (nil type)
			// surfaces typeName's error through the capture path.
			name: "go-stmt args: unsupported param type",
			pkg: wrapPkg(
				&ir.Function{
					Name:   "g",
					Params: []*ir.Param{{Name: "x", Type: nil}},
				},
				&ir.Function{
					Name: "f",
					Body: []ir.Stmt{&ir.GoStmt{Call: &ir.Call{
						Fun:  idn("g"),
						Args: []ir.Expr{litInt("1")},
					}}},
				},
			),
			wantErr: "missing type",
		},
		{
			name: "go holds unexpected stmt (Return)",
			pkg: wrapPkg(&ir.Function{
				Name: "f",
				Body: []ir.Stmt{&ir.GoStmt{Call: &ir.Return{}}},
			}),
			wantErr: "go holds unexpected stmt",
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := Package(tc.pkg, &bytes.Buffer{})
			if err == nil {
				t.Fatalf("expected error containing %q, got nil", tc.wantErr)
			}
			if !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("error %q does not contain %q", err.Error(), tc.wantErr)
			}
		})
	}
}

// TestZeroLiteralOfTable pins the per-type zero-value table used by
// the per-function panic-recover wrapper's exception path. Integer is
// corpus-covered; the other three basic types and the unreachable
// fallback live here.
func TestZeroLiteralOfTable(t *testing.T) {
	t.Parallel()
	cases := []struct {
		t    ir.Type
		want string
	}{
		{&ir.IntType{}, "0"},
		{&ir.BoolType{}, "False"},
		{&ir.Float64Type{}, "0.0"},
		{&ir.StringType{}, `""`},
		// Unreachable fallback for an unsupported type. The pre-scan
		// rejects panic of unsupported types before the wrapper would
		// emit; the fallback is defensive.
		{&ir.SliceType{Elem: &ir.IntType{}}, "0"},
	}
	for _, tc := range cases {
		got := zeroLiteralOf(tc.t)
		if got != tc.want {
			t.Errorf("zeroLiteralOf(%T) = %q, want %q", tc.t, got, tc.want)
		}
	}
}

// TestDeferAndPanicCombined exercises the per-function panic-recover
// wrapper *with* a defer site present — the corpus exercises each in
// isolation but not the combined shape.
func TestDeferAndPanicCombined(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name:    "f",
		Results: []*ir.Param{{Type: &ir.BoolType{}}},
		Body: []ir.Stmt{
			&ir.DeferStmt{Call: &ir.Call{Fun: idn("cleanup")}},
			&ir.BuiltinCall{Name: "panic", Args: []ir.Expr{litInt("99")}},
			&ir.Return{Results: []ir.Expr{
				&ir.Lit{Kind: ir.LitBool, Value: "true"},
			}},
		},
	})
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	out := buf.String()
	if !strings.Contains(out, "Defer_Closure_1") {
		t.Fatalf("expected Defer_Closure_1, got:\n%s", out)
	}
	if !strings.Contains(out, "Panic_Of_Integer.Do_Panic (99);") {
		t.Fatalf("expected Do_Panic (99), got:\n%s", out)
	}
	if !strings.Contains(out, "return False;") {
		t.Fatalf("expected default-return False on exception path, got:\n%s", out)
	}
}

// TestDeferInNestedBlocks exercises collectDefers's recursion through
// if / for / range. Go semantics: defer is bound to the enclosing
// *function*, not the lexical block, so nested defers hoist all the
// way out to the top-level declarative region.
func TestDeferInNestedBlocks(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(&ir.Function{
		Name: "f",
		Body: []ir.Stmt{
			&ir.If{
				Cond: &ir.Lit{Kind: ir.LitBool, Value: "true"},
				Then: []ir.Stmt{&ir.DeferStmt{Call: &ir.Call{Fun: idn("a")}}},
				Else: []ir.Stmt{&ir.DeferStmt{Call: &ir.Call{Fun: idn("b")}}},
			},
			&ir.For{
				Body: []ir.Stmt{&ir.DeferStmt{Call: &ir.Call{Fun: idn("c")}}},
			},
		},
	})
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	out := buf.String()
	for _, want := range []string{"Defer_Closure_1", "Defer_Closure_2", "Defer_Closure_3"} {
		if !strings.Contains(out, want) {
			t.Fatalf("expected %s, got:\n%s", want, out)
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

// structLitEmitFile is the shared declarative context for
// TestStructLitEmit: emitStructLit consults the declared field set, so
// the emitter must see these struct TypeDecls. Point (2 fields), Tick
// (1 field), Empty (0 fields), and Low (1 lowercase field) between them
// exercise every emitStructLit branch.
func structLitEmitFile() *ir.File {
	sf := func(name string) *ir.StructField {
		return &ir.StructField{Name: name, Type: &ir.IntType{}}
	}
	field := func(name string, t ir.Type) *ir.StructField {
		return &ir.StructField{Name: name, Type: t}
	}
	return &ir.File{Decls: []ir.Decl{
		&ir.TypeDecl{Name: "Point", Underlying: &ir.StructType{Fields: []*ir.StructField{sf("X"), sf("Y")}}},
		&ir.TypeDecl{Name: "Tick", Underlying: &ir.StructType{Fields: []*ir.StructField{sf("N")}}},
		&ir.TypeDecl{Name: "Empty", Underlying: &ir.StructType{}},
		&ir.TypeDecl{Name: "Low", Underlying: &ir.StructType{Fields: []*ir.StructField{sf("count")}}},
		// Mix exercises the non-int scalar zero spellings (bool, float).
		// A string field is deliberately absent: an unconstrained String
		// record component is invalid Ada, so a string struct field is
		// rejected at declaration (see TestStructTypeRejectsUnsupportedField).
		&ir.TypeDecl{Name: "Mix", Underlying: &ir.StructType{Fields: []*ir.StructField{
			field("B", &ir.BoolType{}), field("F", &ir.Float64Type{}),
		}}},
		// Vec has a slice field whose zero value is not yet synthesisable.
		&ir.TypeDecl{Name: "Vec", Underlying: &ir.StructType{Fields: []*ir.StructField{
			field("Data", &ir.SliceType{Elem: &ir.IntType{}}), sf("N"),
		}}},
	}}
}

// TestStructLitEmit locks emitStructLit's aggregate forms directly: a
// complete keyed literal renders `Name'(F => V, …)`, a complete
// multi-field positional one `Name'(V, …)`, a single positional field
// the *named* `Name'(F => V)` form (a one-component positional
// aggregate is not valid Ada), and an empty struct the
// `Name'(null record)` mirror of the `is null record` type. A lowercase
// single field confirms adaIdent capitalises the aggregate component so
// it lines up with the record declaration 5a-i emits.
func TestStructLitEmit(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		lit  *ir.StructLit
		want string
	}{
		{
			"keyed complete",
			&ir.StructLit{TypeName: "Point", Fields: []*ir.StructLitField{
				{Name: "X", Value: litInt("1")},
				{Name: "Y", Value: litInt("2")},
			}},
			"Point'(X => 1, Y => 2)",
		},
		{
			"positional multi-field",
			&ir.StructLit{TypeName: "Point", Fields: []*ir.StructLitField{
				{Value: litInt("3")},
				{Value: litInt("4")},
			}},
			"Point'(3, 4)",
		},
		{
			"single positional field uses named form",
			&ir.StructLit{TypeName: "Tick", Fields: []*ir.StructLitField{
				{Value: litInt("7")},
			}},
			"Tick'(N => 7)",
		},
		{
			"empty struct",
			&ir.StructLit{TypeName: "Empty"},
			"Empty'(null record)",
		},
		{
			"lowercase field capitalised",
			&ir.StructLit{TypeName: "Low", Fields: []*ir.StructLitField{
				{Name: "count", Value: litInt("5")},
			}},
			"Low'(Count => 5)",
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			e := newEmitter("p", structLitEmitFile())
			if got := e.emitExpr(tc.lit); got != tc.want {
				t.Fatalf("emitStructLit = %q, want %q", got, tc.want)
			}
			if e.err != nil {
				t.Fatalf("unexpected emit error: %v", e.err)
			}
		})
	}
}

// TestStructZeroFill locks item 5a-iii: a zero-value `Point{}` and a
// partial keyed `Point{X: 1}` fill the omitted components with each
// field's Go zero value in *declared* order, so the aggregate is
// complete (Ada requires every component). The non-int scalar zeros
// (""/False/0.0) and an out-of-order partial confirm the fill resolves
// by declared field, not literal order.
func TestStructZeroFill(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		lit  *ir.StructLit
		want string
	}{
		{
			"zero-value literal fills all fields",
			&ir.StructLit{TypeName: "Point"},
			"Point'(X => 0, Y => 0)",
		},
		{
			"partial keyed fills the omitted field",
			&ir.StructLit{TypeName: "Point", Fields: []*ir.StructLitField{
				{Name: "X", Value: litInt("1")},
			}},
			"Point'(X => 1, Y => 0)",
		},
		{
			"partial fill resolves by declared order not literal order",
			&ir.StructLit{TypeName: "Point", Fields: []*ir.StructLitField{
				{Name: "Y", Value: litInt("9")},
			}},
			"Point'(X => 0, Y => 9)",
		},
		{
			"non-int scalar zeros",
			&ir.StructLit{TypeName: "Mix"},
			"Mix'(B => False, F => 0.0)",
		},
		{
			"complete keyed out of declared order fills in declared order",
			&ir.StructLit{TypeName: "Point", Fields: []*ir.StructLitField{
				{Name: "Y", Value: litInt("2")},
				{Name: "X", Value: litInt("1")},
			}},
			"Point'(X => 1, Y => 2)",
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			e := newEmitter("p", structLitEmitFile())
			if got := e.emitExpr(tc.lit); got != tc.want {
				t.Fatalf("emitStructLit = %q, want %q", got, tc.want)
			}
			if e.err != nil {
				t.Fatalf("unexpected emit error: %v", e.err)
			}
		})
	}
}

// TestStructLitEmitRejects locks emitStructLit's correct-or-loud
// guards: a composite literal on a non-struct/undeclared type, and a
// partial literal whose *omitted* field is a slice (whose zero value is
// not yet synthesisable — see zeroValueFor) both fail with a clear
// diagnostic rather than emit invalid Ada.
func TestStructLitEmitRejects(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		lit     *ir.StructLit
		wantSub string
	}{
		{
			"undeclared / non-struct type",
			&ir.StructLit{TypeName: "Ints", Fields: []*ir.StructLitField{{Value: litInt("1")}}},
			"non-struct or undeclared",
		},
		{
			"omitted non-scalar (slice) field has no synthesisable zero",
			&ir.StructLit{TypeName: "Vec", Fields: []*ir.StructLitField{
				{Name: "N", Value: litInt("3")},
			}},
			"no zero value for struct field",
		},
		{
			"positional literal with too few fields",
			&ir.StructLit{TypeName: "Point", Fields: []*ir.StructLitField{
				{Value: litInt("3")},
			}},
			"positional struct literal",
		},
		{
			"positional literal with too many fields",
			&ir.StructLit{TypeName: "Tick", Fields: []*ir.StructLitField{
				{Value: litInt("1")}, {Value: litInt("2")},
			}},
			"positional struct literal",
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			e := newEmitter("p", structLitEmitFile())
			got := e.emitExpr(tc.lit)
			if e.err == nil {
				t.Fatalf("expected emit error, got output %q", got)
			}
			if !strings.Contains(e.err.Error(), tc.wantSub) {
				t.Fatalf("error %q does not contain %q", e.err.Error(), tc.wantSub)
			}
		})
	}
}

// TestStructTypeRejectsUnsupportedField locks that emitStructTypes
// fails loudly for a struct field whose type does not yet lower to a
// valid Ada record component — a string (unconstrained component) or a
// slice/map/chan (un-instantiated package) — rather than emit a record
// declaration that gprbuild would reject. The scalar-only boundary is
// shared with zeroValueFor via validStructFieldType.
func TestStructTypeRejectsUnsupportedField(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		typ     ir.Type
		wantSub string
	}{
		{"string field", &ir.StringType{}, "type string not yet supported"},
		{"slice field", &ir.SliceType{Elem: &ir.IntType{}}, "not yet supported"},
		{"map field", &ir.MapType{Key: &ir.IntType{}, Value: &ir.IntType{}}, "not yet supported"},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			file := &ir.File{Decls: []ir.Decl{
				&ir.TypeDecl{Name: "T", Underlying: &ir.StructType{Fields: []*ir.StructField{
					{Name: "F", Type: tc.typ},
				}}},
			}}
			e := newEmitter("p", file)
			err := e.emitStructTypes()
			if err == nil {
				t.Fatal("expected emitStructTypes error for unsupported field type")
			}
			if !strings.Contains(err.Error(), tc.wantSub) {
				t.Fatalf("error %q does not contain %q", err.Error(), tc.wantSub)
			}
		})
	}
}

// TestSelectorFieldCapitalised locks that a field access through a
// lowercase Go field name (`p.count`) renders the capitalised record
// component (`P.Count`) 5a-i declares — a no-op on already-exported
// fields but essential for unexported ones to compile.
func TestSelectorFieldCapitalised(t *testing.T) {
	t.Parallel()
	e := newEmitter("p", &ir.File{})
	got := e.emitExpr(&ir.Selector{X: idn("p"), Sel: "count"})
	if want := "P.Count"; got != want {
		t.Fatalf("emitSelector = %q, want %q", got, want)
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

// TestGoArgsUnnamedParam covers the synthetic-name path in
// emitGoClosureWithArgs: a callee with an unnamed parameter (Go's
// `func f(int)`) must still emit a valid closure record component,
// named Anon_<i>, rather than an empty identifier.
func TestGoArgsUnnamedParam(t *testing.T) {
	t.Parallel()
	pkg := wrapPkg(
		&ir.Function{
			Name:   "g",
			Params: []*ir.Param{{Name: "", Type: &ir.IntType{}}},
		},
		&ir.Function{
			Name: "f",
			Body: []ir.Stmt{&ir.GoStmt{Call: &ir.Call{
				Fun:  idn("g"),
				Args: []ir.Expr{litInt("5")},
			}}},
		},
	)
	var buf bytes.Buffer
	if err := Package(pkg, &buf); err != nil {
		t.Fatalf("emit: %v", err)
	}
	out := buf.String()
	if !strings.Contains(out, "Anon_1 : Integer;") {
		t.Fatalf("expected synthetic Anon_1 component for unnamed param, got:\n%s", out)
	}
	if !strings.Contains(out, "G (Anon_1);") {
		t.Fatalf("expected call G (Anon_1), got:\n%s", out)
	}
}

// TestTypeMetaScalarStruct exercises collectTypeMeta on a named scalar
// and a struct, mirroring the type_decl corpus but asserting the
// resolved Ids / kinds / field links directly.
// TestEmitStructTypesError covers emitStructTypes' typeName failure on a
// field whose type has no Ada mapping (here a nested anonymous struct).
// The full pipeline rejects such IR earlier at collectTypeMeta, so the
// branch is exercised by calling emitStructTypes directly.
func TestEmitStructTypesError(t *testing.T) {
	t.Parallel()
	em := newEmitter("p", &ir.File{Decls: []ir.Decl{
		&ir.TypeDecl{Name: "Bad", Underlying: &ir.StructType{Fields: []*ir.StructField{
			{Name: "F", Type: &ir.StructType{}},
		}}},
	}})
	if err := em.emitStructTypes(); err == nil {
		t.Fatal("expected error for struct field with no Ada type mapping")
	}
}

func TestTypeMetaScalarStruct(t *testing.T) {
	t.Parallel()
	decls := []ir.Decl{
		&ir.TypeDecl{Name: "Celsius", Underlying: &ir.Float64Type{}},
		&ir.TypeDecl{Name: "Point", Underlying: &ir.StructType{Fields: []*ir.StructField{
			{Name: "X", Type: &ir.IntType{}},
			{Name: "Y", Type: &ir.IntType{}},
		}}},
	}
	set, err := collectTypeMeta(decls)
	if err != nil {
		t.Fatalf("collectTypeMeta: %v", err)
	}
	got := set.entries()
	// Defined types first (source order), then referenced int.
	if len(got) != 3 {
		t.Fatalf("want 3 entries, got %d: %+v", len(got), got)
	}
	if got[0].Name != "Celsius" || got[0].ID != 1 || got[0].Kind != "Float_Kind" {
		t.Errorf("entry 0 = %+v, want Celsius/1/Float_Kind", got[0])
	}
	if got[1].Name != "Point" || got[1].ID != 2 || got[1].Kind != "Struct_Kind" {
		t.Errorf("entry 1 = %+v, want Point/2/Struct_Kind", got[1])
	}
	if len(got[1].Fields) != 2 || got[1].Fields[0].TypeID != 3 || got[1].Fields[1].TypeID != 3 {
		t.Errorf("Point fields = %+v, want X,Y both -> int Id 3", got[1].Fields)
	}
	if got[2].Name != "int" || got[2].ID != 3 || got[2].Kind != "Int_Kind" {
		t.Errorf("entry 2 = %+v, want int/3/Int_Kind", got[2])
	}
}

// TestTypeMetaComposites covers the slice / map / chan underlyings and
// their element / key interning, plus the emitted Elem/Key arguments.
func TestTypeMetaComposites(t *testing.T) {
	t.Parallel()
	decls := []ir.Decl{
		&ir.TypeDecl{Name: "Buf", Underlying: &ir.SliceType{Elem: &ir.IntType{}}},
		&ir.TypeDecl{Name: "Dict", Underlying: &ir.MapType{Key: &ir.StringType{}, Value: &ir.BoolType{}}},
		&ir.TypeDecl{Name: "Pipe", Underlying: &ir.ChanType{Elem: &ir.IntType{}}},
	}
	set, err := collectTypeMeta(decls)
	if err != nil {
		t.Fatalf("collectTypeMeta: %v", err)
	}
	got := set.entries()
	byName := map[string]typeMetaEntry{}
	for _, e := range got {
		byName[e.Name] = e
	}
	if e := byName["Buf"]; e.Kind != "Slice_Kind" || e.Elem != byName["int"].ID {
		t.Errorf("Buf = %+v, want Slice_Kind elem->int", e)
	}
	if e := byName["Dict"]; e.Kind != "Map_Kind" || e.Key != byName["string"].ID || e.Elem != byName["bool"].ID {
		t.Errorf("Dict = %+v, want Map_Kind key->string value->bool", e)
	}
	if e := byName["Pipe"]; e.Kind != "Chan_Kind" || e.Elem != byName["int"].ID {
		t.Errorf("Pipe = %+v, want Chan_Kind elem->int", e)
	}

	// Emission carries the Elem/Key arguments + the Register_Type call.
	em := newEmitter("p", &ir.File{})
	em.emitTypeMetadata(got)
	out := em.buf.String()
	if !strings.Contains(out, "Elem =>") || !strings.Contains(out, "Key =>") {
		t.Errorf("emitted metadata missing Elem/Key args:\n%s", out)
	}
	if !strings.Contains(out, "Gada.Reflect.Registry.Register_Type (Meta);") {
		t.Errorf("emitted metadata missing Register_Type call:\n%s", out)
	}
}

// TestTypeMetaSkipsNonTypeDecls feeds collectTypeMeta a decl slice that
// interleaves a Function with the TypeDecls, exercising the
// non-TypeDecl skip in both passes. Functions never contribute a
// descriptor, so only the two defined types (plus the interned int) are
// registered, with Ids unaffected by the interleaved function.
func TestTypeMetaSkipsNonTypeDecls(t *testing.T) {
	t.Parallel()
	decls := []ir.Decl{
		&ir.Function{Name: "f"},
		&ir.TypeDecl{Name: "Celsius", Underlying: &ir.Float64Type{}},
		&ir.Function{Name: "g"},
		&ir.TypeDecl{Name: "Point", Underlying: &ir.StructType{Fields: []*ir.StructField{
			{Name: "X", Type: &ir.IntType{}},
		}}},
	}
	set, err := collectTypeMeta(decls)
	if err != nil {
		t.Fatalf("collectTypeMeta: %v", err)
	}
	got := set.entries()
	if len(got) != 3 {
		t.Fatalf("want 3 entries (Celsius, Point, int), got %d: %+v", len(got), got)
	}
	if got[0].Name != "Celsius" || got[0].ID != 1 {
		t.Errorf("entry 0 = %+v, want Celsius/1", got[0])
	}
	if got[1].Name != "Point" || got[1].ID != 2 {
		t.Errorf("entry 1 = %+v, want Point/2", got[1])
	}
}

// TestInterfaceSatisfaction covers the structural satisfaction
// computation: a concrete type satisfies an interface iff its method set
// provides a name+signature match for every interface method. Exercises
// a clean match, the empty interface (satisfied by all), and the three
// rejections — missing method, wrong result type, and wrong arity — then
// checks the emission resolves Ids into a Register call per pair.
func TestInterfaceSatisfaction(t *testing.T) {
	t.Parallel()
	str := func() *ir.Param { return &ir.Param{Type: &ir.StringType{}} }

	decls := []ir.Decl{
		// type Stringer interface { String() string }
		&ir.TypeDecl{Name: "Stringer", Underlying: &ir.InterfaceType{
			Methods: []*ir.MethodSig{{Name: "String", Results: []*ir.Param{str()}}}}},
		// type Writer interface { Write(n int) }
		&ir.TypeDecl{Name: "Writer", Underlying: &ir.InterfaceType{
			Methods: []*ir.MethodSig{{Name: "Write",
				Params: []*ir.Param{{Name: "n", Type: &ir.IntType{}}}}}}},
		// type Any interface{}
		&ir.TypeDecl{Name: "Any", Underlying: &ir.InterfaceType{}},
		// concrete types
		&ir.TypeDecl{Name: "Point", Underlying: &ir.StructType{}},
		&ir.TypeDecl{Name: "Wrong", Underlying: &ir.StructType{}},
		&ir.TypeDecl{Name: "Arity", Underlying: &ir.StructType{}},
		&ir.TypeDecl{Name: "Bare", Underlying: &ir.StructType{}},
		&ir.TypeDecl{Name: "PtrRecv", Underlying: &ir.StructType{}},
		// Point.String() string -> satisfies Stringer (and Any).
		&ir.Function{Name: "String", Receiver: &ir.Receiver{Type: "Point"},
			Results: []*ir.Param{str()}},
		// PtrRecv.String() string on a *pointer* receiver -> the value
		// type PtrRecv does NOT satisfy Stringer (that method is in
		// *PtrRecv's set), and it must not appear in PtrRecv's descriptor.
		&ir.Function{Name: "String",
			Receiver: &ir.Receiver{Type: "PtrRecv", Pointer: true},
			Results:  []*ir.Param{str()}},
		// Wrong.String() int -> wrong result type, does NOT satisfy Stringer.
		&ir.Function{Name: "String", Receiver: &ir.Receiver{Type: "Wrong"},
			Results: []*ir.Param{{Type: &ir.IntType{}}}},
		// Arity.Write() -> wrong arity (no param), does NOT satisfy Writer.
		&ir.Function{Name: "Write", Receiver: &ir.Receiver{Type: "Arity"}},
		// Bare has no methods -> satisfies only Any.
	}

	got := map[string]bool{}
	for _, p := range satisfiedPairs(decls) {
		got[p.Concrete+":"+p.Iface] = true
	}

	// Every concrete satisfies the empty interface; only Point satisfies
	// Stringer; nobody here satisfies Writer.
	for _, want := range []string{
		"Point:Stringer", "Point:Any", "Wrong:Any", "Arity:Any", "Bare:Any",
		"PtrRecv:Any", // still satisfies the empty interface
	} {
		if !got[want] {
			t.Errorf("expected satisfied pair %q, got %v", want, got)
		}
	}
	for _, notWant := range []string{
		"Wrong:Stringer",   // String() int  != String() string
		"Arity:Writer",     // Write()       != Write(int)
		"Bare:Stringer",    // no String method at all
		"Point:Writer",     // Point has no Write
		"PtrRecv:Stringer", // String() is a *pointer*-receiver method
	} {
		if got[notWant] {
			t.Errorf("did not expect satisfied pair %q, got %v", notWant, got)
		}
	}

	// Emission resolves each pair's Type_Ids and writes one Register
	// call. Point (Id 4) satisfies Stringer (Id 1) — Ids follow source
	// order of the defined types.
	set, err := collectTypeMeta(decls)
	if err != nil {
		t.Fatalf("collectTypeMeta: %v", err)
	}
	// The descriptor's method set follows the same value-receiver rule:
	// Point's value method is listed, PtrRecv's pointer method is not.
	if ms := set.byKey["Point"].Methods; len(ms) != 1 || ms[0] != "String" {
		t.Errorf("Point descriptor methods = %v, want [String]", ms)
	}
	if ms := set.byKey["PtrRecv"].Methods; len(ms) != 0 {
		t.Errorf("PtrRecv descriptor methods = %v, want none (pointer receiver)", ms)
	}
	em := newEmitter("p", &ir.File{})
	em.emitInterfaceSatisfaction(set, satisfiedPairs(decls))
	out := em.buf.String()
	if !strings.Contains(out, "Gada.Reflect.Interfaces.Register (Concrete =>") {
		t.Errorf("emitted satisfaction missing Register call:\n%s", out)
	}
	if !strings.Contains(out, "--  Point satisfies Stringer") {
		t.Errorf("emitted satisfaction missing the Point/Stringer comment:\n%s", out)
	}
}

// TestTypeMetaNested covers metaTypeKey's recursive branches: a
// composite whose element / key / value is itself a composite, so the
// canonical key is built by recursion ("[][]int", "chan []int",
// "map[[]int][]string"). Scalar-element composites (TestTypeMetaComposites)
// never reach the recursive arm because the element interns as a leaf.
func TestTypeMetaNested(t *testing.T) {
	t.Parallel()
	// Each named type is a slice whose *element* is a composite (or
	// float64), so the element is interned via internType -> metaTypeKey
	// and exercises that function's recursive slice / chan / map / float
	// arms. A top-level named composite is keyed by name and would not.
	decls := []ir.Decl{
		&ir.TypeDecl{Name: "Grid", Underlying: &ir.SliceType{
			Elem: &ir.SliceType{Elem: &ir.IntType{}}}},
		&ir.TypeDecl{Name: "Fan", Underlying: &ir.SliceType{
			Elem: &ir.ChanType{Elem: &ir.IntType{}}}},
		&ir.TypeDecl{Name: "Rows", Underlying: &ir.SliceType{
			Elem: &ir.MapType{Key: &ir.IntType{}, Value: &ir.StringType{}}}},
		&ir.TypeDecl{Name: "Temps", Underlying: &ir.SliceType{
			Elem: &ir.Float64Type{}}},
	}
	set, err := collectTypeMeta(decls)
	if err != nil {
		t.Fatalf("collectTypeMeta: %v", err)
	}
	byName := map[string]typeMetaEntry{}
	for _, e := range set.entries() {
		byName[e.Name] = e
	}
	// The interned anonymous composites carry the recursively-built keys.
	for _, want := range []string{
		"[]int", "chan int", "map[int]string", "float64", "int", "string",
	} {
		if _, ok := byName[want]; !ok {
			t.Errorf("missing interned referenced type %q; got %v", want, keysOf(byName))
		}
	}
	// Each named slice links to its interned composite element by Id.
	if e := byName["Grid"]; e.Kind != "Slice_Kind" || e.Elem != byName["[]int"].ID {
		t.Errorf("Grid = %+v, want Slice_Kind elem->[]int", e)
	}
	if e := byName["Fan"]; e.Kind != "Slice_Kind" || e.Elem != byName["chan int"].ID {
		t.Errorf("Fan = %+v, want Slice_Kind elem->chan int", e)
	}
	if e := byName["Rows"]; e.Kind != "Slice_Kind" || e.Elem != byName["map[int]string"].ID {
		t.Errorf("Rows = %+v, want Slice_Kind elem->map[int]string", e)
	}
	if e := byName["Temps"]; e.Kind != "Slice_Kind" || e.Elem != byName["float64"].ID {
		t.Errorf("Temps = %+v, want Slice_Kind elem->float64", e)
	}
}

func keysOf(m map[string]typeMetaEntry) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

// TestTypeMetaErrors covers the rejection branches: a duplicate type
// name, a nil underlying (no Kind), a struct field of unsupported type
// (nil), and a struct-typed field (anonymous struct has no type key).
func TestTypeMetaErrors(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name  string
		decls []ir.Decl
	}{
		{"duplicate type", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.IntType{}},
			&ir.TypeDecl{Name: "T", Underlying: &ir.IntType{}},
		}},
		{"nil underlying", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: nil},
		}},
		{"struct field nil type", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.StructType{Fields: []*ir.StructField{
				{Name: "X", Type: nil},
			}}},
		}},
		{"struct field anon struct", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.StructType{Fields: []*ir.StructField{
				{Name: "X", Type: &ir.StructType{}},
			}}},
		}},
		{"nil struct field", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.StructType{Fields: []*ir.StructField{nil}}},
		}},
		{"slice of nil", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.SliceType{Elem: nil}},
		}},
		{"chan of nil", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.ChanType{Elem: nil}},
		}},
		{"map of nil key", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.MapType{Key: nil, Value: &ir.IntType{}}},
		}},
		{"map of nil value", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.MapType{Key: &ir.IntType{}, Value: nil}},
		}},
		// Nested-composite error propagation: a slice / chan / map that
		// is itself an *element* of another composite reaches
		// metaTypeKey's recursive arm; nil at the bottom must surface as
		// an error from that arm rather than be swallowed. The outer
		// slice forces the inner composite through internType ->
		// metaTypeKey (a top-level named composite is keyed by name and
		// never recurses there).
		{"nested slice of nil", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.SliceType{
				Elem: &ir.SliceType{Elem: nil}}},
		}},
		{"nested chan of nil", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.SliceType{
				Elem: &ir.ChanType{Elem: nil}}},
		}},
		{"nested map nil key", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.SliceType{
				Elem: &ir.MapType{Key: nil, Value: &ir.IntType{}}}},
		}},
		{"nested map nil value", []ir.Decl{
			&ir.TypeDecl{Name: "T", Underlying: &ir.SliceType{
				Elem: &ir.MapType{Key: &ir.IntType{}, Value: nil}}},
		}},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if _, err := collectTypeMeta(tc.decls); err == nil {
				t.Fatalf("expected error for %s, got nil", tc.name)
			}
		})
	}
}
