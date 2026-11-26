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

// TestSyncImportEmit pins the Phase 6 `sync` import mapping: the
// with-clause and a qualified call lower through goNameToAdaMember.
func TestSyncImportEmit(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"sync"},
		&ir.Call{
			Fun:  &ir.Selector{X: idn("sync"), Sel: "NewCond"},
			Args: []ir.Expr{&ir.Lit{Kind: ir.LitNil}},
		},
	)
	for _, want := range []string{
		"with Gada.Std.Sync;",
		"Gada.Std.Sync.New_Cond (null);",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// TestTimeImportEmit pins the Phase 6 `time` import mapping.
func TestTimeImportEmit(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"time"},
		&ir.Call{
			Fun:  &ir.Selector{X: idn("time"), Sel: "NewTimer"},
			Args: []ir.Expr{litInt("5_000_000_000")},
		},
	)
	for _, want := range []string{
		"with Gada.Std.Time;",
		"Gada.Std.Time.New_Timer (",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// TestRuntimeImportEmit pins the Phase 6 `runtime` import mapping.
func TestRuntimeImportEmit(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"runtime"},
		&ir.Call{
			Fun:  &ir.Selector{X: idn("runtime"), Sel: "NumGoroutine"},
			Args: nil,
		},
	)
	for _, want := range []string{
		"with Gada.Std.Runtime;",
		"Gada.Std.Runtime.Num_Goroutine",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// TestTimeChanImportEmit pins the Phase 6 `chan time.Time` mapping:
// `timer := time.After(...)` declares a Gada.Std.Time.Time_Channels
// channel and no per-file Channels_Of_Time instantiation is emitted.
func TestTimeChanImportEmit(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"time"},
		&ir.Assign{
			LHS:    []ir.Expr{idn("timer")},
			Define: true,
			RHS: []ir.Expr{&ir.Call{
				Fun: &ir.Selector{X: idn("time"), Sel: "After"},
				Args: []ir.Expr{&ir.BinOp{
					Op: "*",
					X:  litInt("200"),
					Y:  &ir.Selector{X: idn("time"), Sel: "Millisecond"},
				}},
				ResultTypes: []ir.Type{
					&ir.ChanType{Elem: &ir.NamedType{Name: "Time"}},
				},
			}},
		},
	)
	for _, want := range []string{
		"with Gada.Std.Time; use type Gada.Std.Time.Duration;",
		"Gada.Std.Time.Time_Channels.Channel",
		"Gada.Std.Time.After (200 * Gada.Std.Time.Millisecond)",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
	if strings.Contains(out, "Channels_Of_Time") {
		t.Errorf("must not instantiate Channels_Of_Time:\n%s", out)
	}
}

// TestSyncMutexVarEmit pins the Phase 6 `var mu sync.Mutex` +
// `mu.Lock()` lowering: a bare `Mu : Gada.Std.Sync.Mutex;` declaration
// (via ir.ZeroVal) and protected dot-calls `Mu.Lock;` / `Mu.Unlock;`.
func TestSyncMutexVarEmit(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"sync"},
		&ir.Assign{
			LHS:    []ir.Expr{idn("mu")},
			Define: true,
			RHS:    []ir.Expr{&ir.ZeroVal{Type: &ir.NamedType{Name: "Mutex"}}},
		},
		&ir.Call{Fun: &ir.Selector{X: idn("mu"), Sel: "Lock"}},
		&ir.Call{Fun: &ir.Selector{X: idn("mu"), Sel: "Unlock"}},
	)
	for _, want := range []string{
		"with Gada.Std.Sync;",
		"Mu : Gada.Std.Sync.Mutex;",
		"Mu.Lock;",
		"Mu.Unlock;",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// TestLenOsArgsEmit pins the `len(os.Args)` special case: it lowers to
// String_Vectors.Length over Gada.Std.OS.Args (a String_Slice).
func TestLenOsArgsEmit(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"os"},
		&ir.Assign{
			LHS:    []ir.Expr{idn("argc")},
			Define: true,
			RHS: []ir.Expr{&ir.BuiltinCall{
				Name: "len",
				Args: []ir.Expr{&ir.Selector{X: idn("os"), Sel: "Args"}},
			}},
		},
	)
	want := "Integer (Gada.Std.Strings.String_Vectors.Length (Gada.Std.OS.Args))"
	if !strings.Contains(out, want) {
		t.Errorf("missing %q in:\n%s", want, out)
	}
}

// TestLenOsArgsInIfCond pins that len(os.Args) in ANY expression
// position (here an if-condition) pulls in `with Gada.Std.Strings;`.
func TestLenOsArgsInIfCond(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"os"},
		&ir.If{
			Cond: &ir.BinOp{
				Op: ">",
				X: &ir.BuiltinCall{
					Name: "len",
					Args: []ir.Expr{&ir.Selector{X: idn("os"), Sel: "Args"}},
				},
				Y: litInt("1"),
			},
			Then: []ir.Stmt{&ir.Return{}},
		},
	)
	if !strings.Contains(out, "with Gada.Std.Strings;") {
		t.Errorf("missing with Gada.Std.Strings; in:\n%s", out)
	}
	want := "Integer (Gada.Std.Strings.String_Vectors.Length (Gada.Std.OS.Args))"
	if !strings.Contains(out, want) {
		t.Errorf("missing %q in:\n%s", want, out)
	}
}

// TestBareRecvStmt pins that a bare `<-c` statement lowers to a real
// Receive block (value discarded), not a `null;` no-op.
func TestBareRecvStmt(t *testing.T) {
	t.Parallel()
	out := emitMain(t, nil,
		&ir.Assign{
			LHS:    []ir.Expr{idn("c")},
			Define: true,
			RHS:    []ir.Expr{&ir.MakeChan{Elem: &ir.IntType{}, Capacity: litInt("1")}},
		},
		&ir.ExprStmt{X: &ir.ChanRecv{Chan: idn("c")}},
	)
	want := "Channels_Of_Integer.Receive (C, V, OK);"
	if !strings.Contains(out, want) {
		t.Errorf("missing %q in:\n%s", want, out)
	}
}

// TestZeroValScalarZero pins Go's zero-value guarantee for
// `var n int` (and friends): the decl carries an explicit zero
// initializer, not a bare uninitialized object.
func TestZeroValScalarZero(t *testing.T) {
	t.Parallel()
	out := emitMain(t, nil,
		&ir.Assign{
			LHS:    []ir.Expr{idn("n")},
			Define: true,
			RHS:    []ir.Expr{&ir.ZeroVal{Type: &ir.IntType{}}},
		},
	)
	if !strings.Contains(out, "N : Integer := 0;") {
		t.Errorf("missing zero initializer in:\n%s", out)
	}
}

// TestUserTimeChanNotMisrouted pins that a LOCAL type named Time never
// gets routed to Gada.Std.Time.Time_Channels: without the time import
// `make(chan Time)` fails loudly (unsupported element type), and with
// the time import present the local type shadows the special case
// (also a loud failure, never a silent misroute).
func TestUserTimeChanNotMisrouted(t *testing.T) {
	t.Parallel()
	for _, imports := range [][]string{nil, {"time"}} {
		pkg := &ir.Package{Name: "p", Files: []*ir.File{
			{Name: "x.go", Imports: imports, Decls: []ir.Decl{
				&ir.TypeDecl{Name: "Time", Underlying: &ir.StructType{}},
				funcMain(
					&ir.Assign{
						LHS:    []ir.Expr{idn("c")},
						Define: true,
						RHS:    []ir.Expr{&ir.MakeChan{Elem: &ir.NamedType{Name: "Time"}}},
					},
				),
			}},
		}}
		var buf bytes.Buffer
		err := Package(pkg, &buf)
		if err == nil {
			t.Fatalf("imports=%v: emit succeeded, want loud error; out:\n%s", imports, buf.String())
		}
		if strings.Contains(buf.String(), "Time_Channels") {
			t.Fatalf("imports=%v: local Time misrouted to Time_Channels:\n%s", imports, buf.String())
		}
	}
}

// TestUserMutexNoSyncImport pins that a method call on a LOCAL type
// named Mutex (no sync import) does NOT take the sync dot-call path —
// it must fail loudly like any other non-dispatching method call.
func TestUserMutexNoSyncImport(t *testing.T) {
	t.Parallel()
	pkg := &ir.Package{Name: "p", Files: []*ir.File{
		{Name: "x.go", Decls: []ir.Decl{
			&ir.TypeDecl{Name: "Mutex", Underlying: &ir.StructType{}},
			funcMain(
				&ir.Assign{
					LHS:    []ir.Expr{idn("mu")},
					Define: true,
					RHS:    []ir.Expr{&ir.ZeroVal{Type: &ir.NamedType{Name: "Mutex"}}},
				},
				&ir.Call{Fun: &ir.Selector{X: idn("mu"), Sel: "Lock"}},
			),
		}},
	}}
	var buf bytes.Buffer
	err := Package(pkg, &buf)
	if err == nil {
		t.Fatalf("emit succeeded, want loud error; out:\n%s", buf.String())
	}
	if !strings.Contains(err.Error(), "dispatching") {
		t.Fatalf("wrong error: %v", err)
	}
}

// TestVarDurationZero pins `var d time.Duration`: scalar stdlib value
// type gets an explicit zero literal and the Duration use-type clause.
func TestVarDurationZero(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"time"},
		&ir.Assign{
			LHS:    []ir.Expr{idn("d")},
			Define: true,
			RHS:    []ir.Expr{&ir.ZeroVal{Type: &ir.NamedType{Name: "Duration"}}},
		},
	)
	for _, want := range []string{
		"D : Gada.Std.Time.Duration := 0;",
		"use type Gada.Std.Time.Duration;",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// TestVarTimeValue pins `var t time.Time`: the struct value type
// declares bare (records default-initialise).
func TestVarTimeValue(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"time"},
		&ir.Assign{
			LHS:    []ir.Expr{idn("t")},
			Define: true,
			RHS:    []ir.Expr{&ir.ZeroVal{Type: &ir.NamedType{Name: "Time"}}},
		},
	)
	if !strings.Contains(out, "T : Gada.Std.Time.Time;") {
		t.Errorf("missing bare Time decl in:\n%s", out)
	}
}

// TestSyncWaitGroupArgCall pins the with-args sync dot-call shape:
// `wg.Add(1)` -> `Wg.Add (1);`.
func TestSyncWaitGroupArgCall(t *testing.T) {
	t.Parallel()
	out := emitMain(t, []string{"sync"},
		&ir.Assign{
			LHS:    []ir.Expr{idn("wg")},
			Define: true,
			RHS:    []ir.Expr{&ir.ZeroVal{Type: &ir.NamedType{Name: "WaitGroup"}}},
		},
		&ir.Call{
			Fun:  &ir.Selector{X: idn("wg"), Sel: "Add"},
			Args: []ir.Expr{litInt("1")},
		},
	)
	for _, want := range []string{
		"Wg : Gada.Std.Sync.Wait_Group;",
		"Wg.Add (1);",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// TestBareRecvUnknownChan pins the loud failure for a bare `<-c`
// whose operand cannot be resolved to a chan type.
func TestBareRecvUnknownChan(t *testing.T) {
	t.Parallel()
	pkg := &ir.Package{Name: "p", Files: []*ir.File{
		{Name: "x.go", Decls: []ir.Decl{funcMain(
			&ir.ExprStmt{X: &ir.ChanRecv{Chan: idn("c")}},
		)}},
	}}
	var buf bytes.Buffer
	err := Package(pkg, &buf)
	if err == nil || !strings.Contains(err.Error(), "unresolvable chan") {
		t.Fatalf("want unresolvable-chan error, got %v", err)
	}
}
