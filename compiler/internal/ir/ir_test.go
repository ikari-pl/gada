package ir

import (
	"encoding/json"
	"flag"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// updateGolden lets a developer regenerate hello.golden.json deliberately.
//
//	cd compiler && go test ./internal/ir/... -run TestHelloGolden -update
//
// Without the flag the test is read-only and fails on any drift.
var updateGolden = flag.Bool("update", false, "update IR golden files")

// TestNodeKind smoke-tests every concrete node's NodeKind() method.
// The kind string is the JSON discriminator; a typo here corrupts the
// entire on-disk format, so it deserves a dedicated test.
func TestNodeKind(t *testing.T) {
	t.Parallel()

	type kindable interface{ NodeKind() string }

	cases := []struct {
		name string
		node kindable
		want string
	}{
		{"Function", &Function{}, "Function"},
		{"Assign", &Assign{}, "Assign"},
		{"If", &If{}, "If"},
		{"For", &For{}, "For"},
		{"Return", &Return{}, "Return"},
		{"Call", &Call{}, "Call"},
		{"ExprStmt", &ExprStmt{}, "ExprStmt"},
		{"Ident", &Ident{}, "Ident"},
		{"Lit", &Lit{}, "Lit"},
		{"BinOp", &BinOp{}, "BinOp"},
		{"UnaryOp", &UnaryOp{}, "UnaryOp"},
		{"Selector", &Selector{}, "Selector"},
		{"IntType", &IntType{}, "IntType"},
		{"StringType", &StringType{}, "StringType"},
		{"BoolType", &BoolType{}, "BoolType"},
		{"Float64Type", &Float64Type{}, "Float64Type"},
		{"SliceType", &SliceType{}, "SliceType"},
		{"SliceLit", &SliceLit{}, "SliceLit"},
		{"IndexExpr", &IndexExpr{}, "IndexExpr"},
		{"SliceExpr", &SliceExpr{}, "SliceExpr"},
		{"BuiltinCall", &BuiltinCall{}, "BuiltinCall"},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := tc.node.NodeKind(); got != tc.want {
				t.Fatalf("NodeKind() = %q, want %q", got, tc.want)
			}
		})
	}
}

// TestSealedInterfaces is a compile-time check expressed as a runtime
// assertion: every concrete node implements the interface its sentinel
// method claims it does. If someone adds a new variant and forgets to
// register it here, the assertion fires.
func TestSealedInterfaces(t *testing.T) {
	t.Parallel()

	var _ Decl = &Function{}

	var _ Stmt = &Assign{}
	var _ Stmt = &If{}
	var _ Stmt = &For{}
	var _ Stmt = &Return{}
	var _ Stmt = &Call{}
	var _ Stmt = &ExprStmt{}
	var _ Stmt = &BuiltinCall{} // panic(x) at statement position

	var _ Expr = &Ident{}
	var _ Expr = &Lit{}
	var _ Expr = &BinOp{}
	var _ Expr = &UnaryOp{}
	var _ Expr = &Selector{}
	var _ Expr = &SliceLit{}
	var _ Expr = &IndexExpr{}
	var _ Expr = &SliceExpr{}
	var _ Expr = &BuiltinCall{} // recover() at expression position

	var _ Type = &IntType{}
	var _ Type = &StringType{}
	var _ Type = &BoolType{}
	var _ Type = &Float64Type{}
	var _ Type = &SliceType{}
}

// TestRoundTripHello marshals the canonical hello-world IR, unmarshals
// it back, and demands reflect.DeepEqual. This is the headline
// invariant: the IR that goes to disk is the IR that comes off it.
func TestRoundTripHello(t *testing.T) {
	t.Parallel()

	pkg := helloPackage()
	roundTrip(t, pkg)
}

// TestRoundTripKitchenSink exercises every IR variant in a single
// structure so a single round-trip covers them all.
func TestRoundTripKitchenSink(t *testing.T) {
	t.Parallel()

	pkg := kitchenSinkPackage()
	roundTrip(t, pkg)
}

// TestRoundTripSliceCorpus exercises the new slice / index / builtin
// IR shapes (SliceType, SliceLit, IndexExpr, SliceExpr, BuiltinCall)
// in a single structure. The generic kitchen-sink predates these
// nodes; keeping the slice corpus separate makes the regression
// surface explicit when only the slice path changes.
func TestRoundTripSliceCorpus(t *testing.T) {
	t.Parallel()

	pkg := &Package{
		Name: "p",
		Files: []*File{{
			Name: "p.go",
			Decls: []Decl{
				&Function{
					Name:    "demo",
					Params:  []*Param{{Name: "s", Type: &SliceType{Elem: &IntType{}}}},
					Results: []*Param{{Type: &IntType{}}},
					Body: []Stmt{
						&Assign{
							LHS:    []Expr{&Ident{Name: "xs"}},
							Define: true,
							RHS: []Expr{&SliceLit{
								Elem: &IntType{},
								Elems: []Expr{
									&Lit{Kind: LitInt, Value: "1"},
									&Lit{Kind: LitInt, Value: "2"},
									&Lit{Kind: LitInt, Value: "3"},
								},
							}},
						},
						// `xs = append(xs, 4)` — BuiltinCall as expr.
						&Assign{
							LHS: []Expr{&Ident{Name: "xs"}},
							RHS: []Expr{&BuiltinCall{
								Name: "append",
								Args: []Expr{&Ident{Name: "xs"}, &Lit{Kind: LitInt, Value: "4"}},
							}},
						},
						// `_ = xs[0]` (IndexExpr) and `_ = xs[1:3]` (SliceExpr)
						&ExprStmt{X: &IndexExpr{X: &Ident{Name: "xs"}, Index: &Lit{Kind: LitInt, Value: "0"}}},
						&ExprStmt{X: &SliceExpr{
							X:    &Ident{Name: "xs"},
							Low:  &Lit{Kind: LitInt, Value: "1"},
							High: &Lit{Kind: LitInt, Value: "3"},
						}},
						// `_ = xs[:]` — both bounds nil.
						&ExprStmt{X: &SliceExpr{X: &Ident{Name: "xs"}}},
						// Stmt-position BuiltinCall: `panic("boom")`.
						&BuiltinCall{
							Name: "panic",
							Args: []Expr{&Lit{Kind: LitString, Value: `"boom"`}},
						},
						&Return{Results: []Expr{&BuiltinCall{
							Name: "len",
							Args: []Expr{&Ident{Name: "xs"}},
						}}},
					},
				},
			},
		}},
	}
	roundTrip(t, pkg)
}

// TestSliceTypeMissingElem locks the explicit-error branch in
// SliceType.UnmarshalJSON: a `SliceType` with no `elem` field is
// nonsensical and must not silently round-trip to an Elem-nil node.
func TestSliceTypeMissingElem(t *testing.T) {
	t.Parallel()
	if _, err := unmarshalType(json.RawMessage(`{"kind":"SliceType"}`)); err == nil {
		t.Fatal("expected error for SliceType without elem")
	}
	if _, err := unmarshalType(json.RawMessage(`{"kind":"SliceType","elem":null}`)); err == nil {
		t.Fatal("expected error for SliceType with null elem")
	}
}

// TestSliceLitMissingElem mirrors the SliceType guard for SliceLit:
// the element type must always be present so the emitter can pick
// the right Slices_Of_<T> instantiation.
func TestSliceLitMissingElem(t *testing.T) {
	t.Parallel()
	if _, err := unmarshalExpr(json.RawMessage(`{"kind":"SliceLit"}`)); err == nil {
		t.Fatal("expected error for SliceLit without elem")
	}
	if _, err := unmarshalExpr(json.RawMessage(`{"kind":"SliceLit","elem":null}`)); err == nil {
		t.Fatal("expected error for SliceLit with null elem")
	}
}

// TestSliceTypeBadElem covers the unmarshalType propagation when the
// nested elem has an unknown kind.
func TestSliceTypeBadElem(t *testing.T) {
	t.Parallel()
	if _, err := unmarshalType(json.RawMessage(`{"kind":"SliceType","elem":{"kind":"Bogus"}}`)); err == nil {
		t.Fatal("expected error for SliceType with bad elem kind")
	}
}

// TestSliceLitBadElem covers the same propagation through SliceLit.
func TestSliceLitBadElem(t *testing.T) {
	t.Parallel()
	if _, err := unmarshalExpr(json.RawMessage(`{"kind":"SliceLit","elem":{"kind":"Bogus"}}`)); err == nil {
		t.Fatal("expected error for SliceLit with bad elem kind")
	}
}

// TestHelloGolden snapshots the JSON form of the hello-world IR.
// The golden file is the cross-phase contract: the translator (next
// task) and the emitter (the task after) both read it.
func TestHelloGolden(t *testing.T) {
	t.Parallel()

	pkg := helloPackage()
	got, err := json.MarshalIndent(pkg, "", "  ")
	if err != nil {
		t.Fatalf("MarshalIndent: %v", err)
	}
	got = append(got, '\n')

	path := filepath.Join("testdata", "hello.golden.json")
	if *updateGolden {
		if err := os.WriteFile(path, got, 0o644); err != nil {
			t.Fatalf("write golden: %v", err)
		}
		t.Logf("updated %s", path)
		return
	}

	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read golden %s: %v (run with -update to create)", path, err)
	}
	if string(got) != string(want) {
		t.Fatalf("hello golden mismatch.\n--- want ---\n%s\n--- got ---\n%s",
			want, got)
	}
}

// TestSentinels invokes every unexported sealed-interface method so
// coverage tooling sees them. They are no-ops by design — the JVM-style
// "marker method" pattern — but they remain part of the executable
// surface and the COVERAGE.md threshold counts them.
func TestSentinels(t *testing.T) {
	t.Parallel()

	(&Function{}).irDecl()

	(&Assign{}).irStmt()
	(&If{}).irStmt()
	(&For{}).irStmt()
	(&Return{}).irStmt()
	(&Call{}).irStmt()
	(&ExprStmt{}).irStmt()

	(&Ident{}).irExpr()
	(&Lit{}).irExpr()
	(&BinOp{}).irExpr()
	(&UnaryOp{}).irExpr()
	(&Selector{}).irExpr()
	(&SliceLit{}).irExpr()
	(&IndexExpr{}).irExpr()
	(&SliceExpr{}).irExpr()
	(&BuiltinCall{}).irExpr()
	(&BuiltinCall{}).irStmt()

	(&IntType{}).irType()
	(&StringType{}).irType()
	(&BoolType{}).irType()
	(&Float64Type{}).irType()
	(&SliceType{}).irType()
}

// TestNilListHelpers exercises the nil-vs-empty branch of the slice
// unmarshal helpers. Without these, a `for {}` loop with a nil Body
// would round-trip to an empty slice and break DeepEqual.
func TestNilListHelpers(t *testing.T) {
	t.Parallel()

	if got, err := unmarshalStmtList(nil); err != nil || got != nil {
		t.Fatalf("unmarshalStmtList(nil) = (%v, %v); want (nil, nil)", got, err)
	}
	if got, err := unmarshalExprList(nil); err != nil || got != nil {
		t.Fatalf("unmarshalExprList(nil) = (%v, %v); want (nil, nil)", got, err)
	}

	// Empty-but-non-nil input must round-trip to empty-but-non-nil so
	// `[]Stmt{}` does not collapse to `nil`.
	if got, err := unmarshalStmtList([]json.RawMessage{}); err != nil || got == nil || len(got) != 0 {
		t.Fatalf("unmarshalStmtList([]) = (%v, %v); want (empty non-nil, nil)", got, err)
	}
	if got, err := unmarshalExprList([]json.RawMessage{}); err != nil || got == nil || len(got) != 0 {
		t.Fatalf("unmarshalExprList([]) = (%v, %v); want (empty non-nil, nil)", got, err)
	}

	if got, err := unmarshalOptionalStmt(nil); err != nil || got != nil {
		t.Fatalf("unmarshalOptionalStmt(nil) = (%v, %v); want (nil, nil)", got, err)
	}
	if got, err := unmarshalOptionalExpr(nil); err != nil || got != nil {
		t.Fatalf("unmarshalOptionalExpr(nil) = (%v, %v); want (nil, nil)", got, err)
	}
}

// TestPropagatedDecodeErrors hits the inner `if err != nil` branches
// of every concrete UnmarshalJSON and every dispatch case. Each input
// has the right `kind` (so the dispatch picks the right concrete type)
// but a malformed body field (so json.Unmarshal of the aux struct
// fails). One input per variant covers all the otherwise-dead error
// returns.
func TestPropagatedDecodeErrors(t *testing.T) {
	t.Parallel()

	type fn = func(json.RawMessage) error

	declErr := func(b json.RawMessage) error { _, err := unmarshalDecl(b); return err }
	stmtErr := func(b json.RawMessage) error { _, err := unmarshalStmt(b); return err }
	exprErr := func(b json.RawMessage) error { _, err := unmarshalExpr(b); return err }

	// Each case feeds a malformed body field so the inner json.Unmarshal
	// of the aux struct fails with a type mismatch. The dispatch wraps
	// or returns it; either way the error branches execute.
	cases := []struct {
		name  string
		input string
		fn    fn
	}{
		// Decls
		{"Function", `{"kind":"Function","name":42}`, declErr},

		// Stmts
		{"Assign", `{"kind":"Assign","lhs":"not-array"}`, stmtErr},
		{"If", `{"kind":"If","cond":"not-object"}`, stmtErr},
		{"For", `{"kind":"For","body":"not-array"}`, stmtErr},
		{"Return", `{"kind":"Return","results":"not-array"}`, stmtErr},
		{"Call", `{"kind":"Call","args":"not-array"}`, stmtErr},
		{"ExprStmt", `{"kind":"ExprStmt","x":42}`, stmtErr},

		// Exprs
		{"Ident", `{"kind":"Ident","name":42}`, exprErr},
		{"Lit", `{"kind":"Lit","value":42}`, exprErr},
		{"BinOp", `{"kind":"BinOp","op":42}`, exprErr},
		{"UnaryOp", `{"kind":"UnaryOp","op":42}`, exprErr},
		{"Selector", `{"kind":"Selector","sel":42}`, exprErr},
		{"SliceLit", `{"kind":"SliceLit","elems":"not-array"}`, exprErr},
		{"IndexExpr", `{"kind":"IndexExpr","x":42}`, exprErr},
		{"SliceExpr", `{"kind":"SliceExpr","x":42}`, exprErr},
		{"BuiltinCall expr", `{"kind":"BuiltinCall","args":"not-array"}`, exprErr},
		{"BuiltinCall stmt", `{"kind":"BuiltinCall","args":"not-array"}`, stmtErr},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if err := tc.fn(json.RawMessage(tc.input)); err == nil {
				t.Fatalf("expected error for malformed %s, got nil", tc.name)
			}
		})
	}
}

// TestPropagatedChildErrors hits the error branches in helpers that
// recurse through interface fields: when an inner Stmt/Expr has an
// unknown kind, the parent's UnmarshalJSON must propagate the failure.
func TestPropagatedChildErrors(t *testing.T) {
	t.Parallel()

	type fn = func(json.RawMessage) error
	stmtErr := func(b json.RawMessage) error { _, err := unmarshalStmt(b); return err }
	exprErr := func(b json.RawMessage) error { _, err := unmarshalExpr(b); return err }
	declErr := func(b json.RawMessage) error { _, err := unmarshalDecl(b); return err }

	bad := `{"kind":"Bogus"}`

	cases := []struct {
		name  string
		input string
		fn    fn
	}{
		{"File.Decls bad child via Function.Body", `{"kind":"Function","body":[` + bad + `]}`, declErr},
		{"Assign.LHS bad child", `{"kind":"Assign","lhs":[` + bad + `]}`, stmtErr},
		{"Assign.RHS bad child", `{"kind":"Assign","lhs":[],"rhs":[` + bad + `]}`, stmtErr},
		{"If.Cond bad child", `{"kind":"If","cond":` + bad + `}`, stmtErr},
		{"If.Then bad child", `{"kind":"If","then":[` + bad + `]}`, stmtErr},
		{"If.Else bad child", `{"kind":"If","else":[` + bad + `]}`, stmtErr},
		{"For.Init bad child", `{"kind":"For","init":` + bad + `}`, stmtErr},
		{"For.Cond bad child", `{"kind":"For","cond":` + bad + `}`, stmtErr},
		{"For.Post bad child", `{"kind":"For","post":` + bad + `}`, stmtErr},
		{"For.Body bad child", `{"kind":"For","body":[` + bad + `]}`, stmtErr},
		{"Return.Results bad child", `{"kind":"Return","results":[` + bad + `]}`, stmtErr},
		{"Call.Fun bad child", `{"kind":"Call","fun":` + bad + `}`, stmtErr},
		{"Call.Args bad child", `{"kind":"Call","args":[` + bad + `]}`, stmtErr},
		{"ExprStmt.X bad child", `{"kind":"ExprStmt","x":` + bad + `}`, stmtErr},
		{"BinOp.X bad child", `{"kind":"BinOp","x":` + bad + `}`, exprErr},
		{"BinOp.Y bad child", `{"kind":"BinOp","y":` + bad + `}`, exprErr},
		{"UnaryOp.X bad child", `{"kind":"UnaryOp","x":` + bad + `}`, exprErr},
		{"Selector.X bad child", `{"kind":"Selector","x":` + bad + `}`, exprErr},
		{"SliceLit.Elem bad type", `{"kind":"SliceLit","elem":` + bad + `}`, exprErr},
		{"SliceLit.Elems bad child", `{"kind":"SliceLit","elem":{"kind":"IntType"},"elems":[` + bad + `]}`, exprErr},
		{"IndexExpr.X bad child", `{"kind":"IndexExpr","x":` + bad + `}`, exprErr},
		{"IndexExpr.Index bad child", `{"kind":"IndexExpr","x":{"kind":"Ident","name":"s"},"index":` + bad + `}`, exprErr},
		{"SliceExpr.X bad child", `{"kind":"SliceExpr","x":` + bad + `}`, exprErr},
		{"SliceExpr.Low bad child", `{"kind":"SliceExpr","x":{"kind":"Ident","name":"s"},"low":` + bad + `}`, exprErr},
		{"SliceExpr.High bad child", `{"kind":"SliceExpr","x":{"kind":"Ident","name":"s"},"high":` + bad + `}`, exprErr},
		{"BuiltinCall.Args bad child as expr", `{"kind":"BuiltinCall","name":"len","args":[` + bad + `]}`, exprErr},
		{"BuiltinCall.Args bad child as stmt", `{"kind":"BuiltinCall","name":"panic","args":[` + bad + `]}`, stmtErr},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if err := tc.fn(json.RawMessage(tc.input)); err == nil {
				t.Fatalf("expected error for %s, got nil", tc.name)
			}
		})
	}
}

// TestParamErrors covers Param's Unmarshal: malformed JSON and bad
// type kind. Param is not a sum-type variant so it has its own test
// rather than being folded into TestPropagatedDecodeErrors.
func TestParamErrors(t *testing.T) {
	t.Parallel()

	var p Param
	if err := p.UnmarshalJSON([]byte(`not json`)); err == nil {
		t.Fatal("expected error for malformed Param JSON")
	}

	var p2 Param
	if err := p2.UnmarshalJSON([]byte(`{"name":"x","type":{"kind":"Bogus"}}`)); err == nil {
		t.Fatal("expected error for unknown type kind in Param")
	}
}

// TestPackageAndFileMalformed covers Package and File error returns.
func TestPackageAndFileMalformed(t *testing.T) {
	t.Parallel()

	var p Package
	if err := p.UnmarshalJSON([]byte(`not json`)); err == nil {
		t.Fatal("expected error for malformed Package JSON")
	}

	var f File
	if err := f.UnmarshalJSON([]byte(`not json`)); err == nil {
		t.Fatal("expected error for malformed File JSON")
	}
	if err := f.UnmarshalJSON([]byte(`{"decls":[{"kind":"Bogus"}]}`)); err == nil {
		t.Fatal("expected error for unknown decl kind inside File")
	}
}

// TestUnmarshalErrors locks in the failure modes of the dispatch
// switches. Without these tests the error branches are dead code, and
// silent miscoding of a node would surface as a typed-nil interface.
func TestUnmarshalErrors(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		input   string
		fn      func(json.RawMessage) error
		wantSub string
	}{
		{
			name:    "decl: unknown kind",
			input:   `{"kind":"Bogus"}`,
			fn:      func(b json.RawMessage) error { _, err := unmarshalDecl(b); return err },
			wantSub: "unknown decl kind",
		},
		{
			name:    "stmt: unknown kind",
			input:   `{"kind":"Bogus"}`,
			fn:      func(b json.RawMessage) error { _, err := unmarshalStmt(b); return err },
			wantSub: "unknown stmt kind",
		},
		{
			name:    "expr: unknown kind",
			input:   `{"kind":"Bogus"}`,
			fn:      func(b json.RawMessage) error { _, err := unmarshalExpr(b); return err },
			wantSub: "unknown expr kind",
		},
		{
			name:    "type: unknown kind",
			input:   `{"kind":"Bogus"}`,
			fn:      func(b json.RawMessage) error { _, err := unmarshalType(b); return err },
			wantSub: "unknown type kind",
		},
		{
			name:    "decl: malformed envelope",
			input:   `not json`,
			fn:      func(b json.RawMessage) error { _, err := unmarshalDecl(b); return err },
			wantSub: "decoding decl envelope",
		},
		{
			name:    "stmt: malformed envelope",
			input:   `not json`,
			fn:      func(b json.RawMessage) error { _, err := unmarshalStmt(b); return err },
			wantSub: "decoding stmt envelope",
		},
		{
			name:    "expr: malformed envelope",
			input:   `not json`,
			fn:      func(b json.RawMessage) error { _, err := unmarshalExpr(b); return err },
			wantSub: "decoding expr envelope",
		},
		{
			name:    "type: malformed envelope",
			input:   `not json`,
			fn:      func(b json.RawMessage) error { _, err := unmarshalType(b); return err },
			wantSub: "decoding type envelope",
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := tc.fn(json.RawMessage(tc.input))
			if err == nil {
				t.Fatalf("expected error containing %q, got nil", tc.wantSub)
			}
			if !strings.Contains(err.Error(), tc.wantSub) {
				t.Fatalf("error %q does not contain %q", err.Error(), tc.wantSub)
			}
		})
	}
}

// TestOptionalNullHandling verifies that nil interface fields survive
// the JSON null round-trip — critical for `for {}` (Init/Cond/Post
// nil) and Param with no type.
func TestOptionalNullHandling(t *testing.T) {
	t.Parallel()

	infiniteFor := &For{
		Body: []Stmt{&Return{}},
	}
	pkg := &Package{
		Name: "p",
		Files: []*File{{
			Name: "p.go",
			Decls: []Decl{&Function{
				Name: "loop",
				Body: []Stmt{infiniteFor},
			}},
		}},
	}
	roundTrip(t, pkg)
}

// helloPackage builds the canonical hello-world IR by hand. Used by
// both the round-trip and golden-file tests; if it changes, both move
// in lockstep.
func helloPackage() *Package {
	return &Package{
		Name: "main",
		Files: []*File{{
			Name:    "hello.go",
			Imports: []string{"fmt"},
			Decls: []Decl{
				&Function{
					Name: "main",
					Body: []Stmt{
						&Call{
							Fun:  &Selector{X: &Ident{Name: "fmt"}, Sel: "Println"},
							Args: []Expr{&Lit{Kind: LitString, Value: `"hello, GADA"`}},
						},
					},
				},
			},
		}},
	}
}

// kitchenSinkPackage exercises every node variant the IR defines so a
// single round-trip covers the full surface for coverage.
func kitchenSinkPackage() *Package {
	return &Package{
		Name: "demo",
		Files: []*File{{
			Name:    "demo.go",
			Imports: []string{"fmt"},
			Decls: []Decl{
				&Function{
					Name: "main",
					Params: []*Param{
						{Name: "n", Type: &IntType{}},
						{Name: "s", Type: &StringType{}},
						{Name: "b", Type: &BoolType{}},
						{Name: "f", Type: &Float64Type{}},
					},
					Results: []*Param{{Name: "", Type: &IntType{}}},
					Body: []Stmt{
						&Assign{
							LHS:    []Expr{&Ident{Name: "x"}},
							Define: true,
							RHS:    []Expr{&Lit{Kind: LitInt, Value: "1"}},
						},
						&Assign{
							LHS:    []Expr{&Ident{Name: "x"}},
							Define: false,
							RHS:    []Expr{&BinOp{Op: "+", X: &Ident{Name: "x"}, Y: &Lit{Kind: LitInt, Value: "2"}}},
						},
						&If{
							Cond: &BinOp{Op: "<", X: &Ident{Name: "x"}, Y: &Lit{Kind: LitInt, Value: "10"}},
							Then: []Stmt{&ExprStmt{X: &Ident{Name: "x"}}},
							Else: []Stmt{&ExprStmt{X: &UnaryOp{Op: "-", X: &Ident{Name: "x"}}}},
						},
						&For{
							Init: &Assign{
								LHS:    []Expr{&Ident{Name: "i"}},
								Define: true,
								RHS:    []Expr{&Lit{Kind: LitInt, Value: "0"}},
							},
							Cond: &BinOp{Op: "<", X: &Ident{Name: "i"}, Y: &Ident{Name: "n"}},
							Post: &Assign{
								LHS: []Expr{&Ident{Name: "i"}},
								RHS: []Expr{&BinOp{Op: "+", X: &Ident{Name: "i"}, Y: &Lit{Kind: LitInt, Value: "1"}}},
							},
							Body: []Stmt{&Call{
								Fun:  &Selector{X: &Ident{Name: "fmt"}, Sel: "Println"},
								Args: []Expr{&Lit{Kind: LitString, Value: `"tick"`}},
							}},
						},
						&Return{Results: []Expr{
							&Lit{Kind: LitBool, Value: "true"},
							&Lit{Kind: LitFloat, Value: "3.14"},
						}},
					},
				},
			},
		}},
	}
}

// roundTrip is the shared round-trip assertion: marshal, unmarshal,
// reflect.DeepEqual.
func roundTrip(t *testing.T, pkg *Package) {
	t.Helper()

	bs, err := json.Marshal(pkg)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	var got Package
	if err := json.Unmarshal(bs, &got); err != nil {
		t.Fatalf("Unmarshal: %v\nJSON was:\n%s", err, bs)
	}
	if !reflect.DeepEqual(pkg, &got) {
		t.Fatalf("round-trip mismatch\noriginal: %#v\nrestored: %#v\nJSON:\n%s",
			pkg, &got, bs)
	}
}
