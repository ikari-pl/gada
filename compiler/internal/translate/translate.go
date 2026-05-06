// Package translate converts a Go AST file into the GADA intermediate
// representation defined in compiler/internal/ir.
//
// Phase 1 scope: the small handful of constructs needed by the
// `hello, GADA` corpus and the nine other small fixtures listed in
// roadmap/01-minimal-transpiler.md. Anything outside that subset
// returns a typed "feature not supported in Phase 1" error so the
// caller can surface a clear message instead of producing
// silently-wrong IR. Each later phase widens the supported subset by
// adding cases to the dispatch switches below.
//
// The translator is intentionally syntax-driven: it works from the
// raw *ast.File and does not (yet) require *types.Info. The corpus
// uses only basic types resolvable by identifier name, and the
// emitter consumes the same names. Later phases will plumb info
// through to disambiguate, e.g., method calls vs. selector
// expressions on packages.
package translate

import (
	"fmt"
	"go/ast"
	"go/token"
	"go/types"
	"strconv"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// File translates a parsed Go AST file into a one-file *ir.Package.
//
// The returned package contains exactly one *ir.File whose Name is
// left empty; the driver in compiler/cmd/gada knows the source path
// and is expected to set it before further processing. Tests do the
// same so goldens are stable.
//
// info may be nil; Phase 1 does not consult it. The parameter is
// kept in the signature so later phases need not break callers.
func File(f *ast.File, info *types.Info) (*ir.Package, error) {
	_ = info // reserved for later phases
	if f == nil {
		return nil, fmt.Errorf("translate: nil ast.File")
	}
	if f.Name == nil {
		return nil, fmt.Errorf("translate: file has no package clause")
	}

	pkg := &ir.Package{Name: f.Name.Name}
	irFile := &ir.File{}

	// f.Imports preserves source-declaration order; that order ends
	// up in the IR so the emitter can produce a stable Ada `with`
	// list.
	for _, imp := range f.Imports {
		path, err := strconv.Unquote(imp.Path.Value)
		if err != nil {
			return nil, fmt.Errorf("translate: bad import path %s: %w", imp.Path.Value, err)
		}
		irFile.Imports = append(irFile.Imports, path)
	}

	for _, d := range f.Decls {
		switch d := d.(type) {
		case *ast.GenDecl:
			// Imports are already collected via f.Imports above; any
			// other GenDecl (Var/Const/Type) is deferred to later
			// phases.
			if d.Tok != token.IMPORT {
				return nil, fmt.Errorf("translate: top-level %s decls not supported in Phase 1", d.Tok)
			}
		case *ast.FuncDecl:
			if d.Recv != nil {
				return nil, fmt.Errorf("translate: methods not supported in Phase 1")
			}
			fn, err := transFunc(d)
			if err != nil {
				return nil, err
			}
			irFile.Decls = append(irFile.Decls, fn)
		default:
			return nil, fmt.Errorf("translate: unsupported top-level decl %T", d)
		}
	}

	pkg.Files = []*ir.File{irFile}
	return pkg, nil
}

// transFunc produces the IR for a top-level function declaration.
// Methods (Recv != nil) are filtered out by File before this is
// called.
func transFunc(fd *ast.FuncDecl) (*ir.Function, error) {
	if fd.Body == nil {
		return nil, fmt.Errorf("translate: function %s has no body", fd.Name.Name)
	}

	fn := &ir.Function{Name: fd.Name.Name}

	params, err := transFieldList(fd.Type.Params)
	if err != nil {
		return nil, err
	}
	fn.Params = params

	results, err := transFieldList(fd.Type.Results)
	if err != nil {
		return nil, err
	}
	fn.Results = results

	body, err := transStmtList(fd.Body.List)
	if err != nil {
		return nil, err
	}
	fn.Body = body
	return fn, nil
}

// transFieldList expands a Go FieldList (which groups parameters by
// shared type) into the IR's flat per-name list. Unnamed fields,
// e.g. `func f() int`, become a single Param with Name == "".
func transFieldList(fl *ast.FieldList) ([]*ir.Param, error) {
	if fl == nil || len(fl.List) == 0 {
		return nil, nil
	}
	var out []*ir.Param
	for _, field := range fl.List {
		t, err := transType(field.Type)
		if err != nil {
			return nil, err
		}
		if len(field.Names) == 0 {
			out = append(out, &ir.Param{Name: "", Type: t})
			continue
		}
		for _, n := range field.Names {
			out = append(out, &ir.Param{Name: n.Name, Type: t})
		}
	}
	return out, nil
}

// transType maps the recognised Go type names and shapes to their IR
// counterparts. Phase 1 covered the four basic types; Phase 2 adds
// `[]T` (slice) and `map[K]V`; Phase 3 adds `chan T`. Fixed-size
// arrays (`[N]T`), named types, struct types, function types, and
// directional channel types (`chan<- T`, `<-chan T`) are deferred.
func transType(e ast.Expr) (ir.Type, error) {
	switch t := e.(type) {
	case *ast.Ident:
		switch t.Name {
		case "int":
			return &ir.IntType{}, nil
		case "string":
			return &ir.StringType{}, nil
		case "bool":
			return &ir.BoolType{}, nil
		case "float64":
			return &ir.Float64Type{}, nil
		default:
			return nil, fmt.Errorf("translate: unsupported type %q", t.Name)
		}
	case *ast.ArrayType:
		if t.Len != nil {
			return nil, fmt.Errorf("translate: fixed-size array types not supported in Phase 2")
		}
		elem, err := transType(t.Elt)
		if err != nil {
			return nil, err
		}
		return &ir.SliceType{Elem: elem}, nil
	case *ast.MapType:
		k, err := transType(t.Key)
		if err != nil {
			return nil, err
		}
		v, err := transType(t.Value)
		if err != nil {
			return nil, err
		}
		return &ir.MapType{Key: k, Value: v}, nil
	case *ast.ChanType:
		// Phase 3 supports only bidirectional `chan T`; Go's directional
		// `chan<- T` and `<-chan T` (Dir != SEND|RECV) are deferred until
		// the runtime gets dedicated send-only / recv-only subtypes.
		// `ast.SEND | ast.RECV` is the bidirectional bitmask.
		if t.Dir != ast.SEND|ast.RECV {
			return nil, fmt.Errorf("translate: directional channel types (chan<-, <-chan) not supported in Phase 3")
		}
		elem, err := transType(t.Value)
		if err != nil {
			return nil, err
		}
		return &ir.ChanType{Elem: elem}, nil
	default:
		return nil, fmt.Errorf("translate: unsupported type expr %T", e)
	}
}

// builtinNames is the closed set of Go predeclared functions Phase 2's
// translate layer recognises. A bare-identifier call whose Fun.Name
// matches one of these becomes an *ir.BuiltinCall instead of *ir.Call,
// so the emitter can dispatch by name. The set widens with each Go
// builtin Phase 2+ supports; staying explicit keeps a future Go-source
// shadowing pun (e.g. `len := 1; _ = len(xs)`) from silently miscoding.
var builtinNames = map[string]bool{
	"append":  true,
	"cap":     true,
	"len":     true,
	"delete":  true,
	"panic":   true,
	"recover": true,
}

// --- statements -----------------------------------------------------------

func transStmtList(stmts []ast.Stmt) ([]ir.Stmt, error) {
	if len(stmts) == 0 {
		return nil, nil
	}
	out := make([]ir.Stmt, 0, len(stmts))
	for _, s := range stmts {
		ts, err := transStmt(s)
		if err != nil {
			return nil, err
		}
		out = append(out, ts)
	}
	return out, nil
}

func transStmt(s ast.Stmt) (ir.Stmt, error) {
	switch s := s.(type) {
	case *ast.AssignStmt:
		return transAssign(s)
	case *ast.IfStmt:
		return transIf(s)
	case *ast.ForStmt:
		return transFor(s)
	case *ast.RangeStmt:
		return transRange(s)
	case *ast.DeferStmt:
		return transDefer(s)
	case *ast.GoStmt:
		return transGo(s)
	case *ast.ReturnStmt:
		return transReturn(s)
	case *ast.ExprStmt:
		return transExprStmt(s)
	default:
		return nil, fmt.Errorf("translate: unsupported stmt %T", s)
	}
}

// transRange handles `for k, v := range x { ... }` plus the elided
// shapes `for k := range x`, `for k, _ := range x`, and `for range x`.
// The blank identifier (`_`) and the absent-name case both decode to
// an empty Name on the IR side.
func transRange(s *ast.RangeStmt) (*ir.RangeStmt, error) {
	if s.Tok != token.ASSIGN && s.Tok != token.DEFINE && s.Tok != token.ILLEGAL {
		return nil, fmt.Errorf("translate: unsupported range token %s", s.Tok)
	}
	keyName, err := identNameOrBlank(s.Key)
	if err != nil {
		return nil, err
	}
	valueName, err := identNameOrBlank(s.Value)
	if err != nil {
		return nil, err
	}
	x, err := transExpr(s.X)
	if err != nil {
		return nil, err
	}
	body, err := transStmtList(s.Body.List)
	if err != nil {
		return nil, err
	}
	return &ir.RangeStmt{
		KeyName:   keyName,
		ValueName: valueName,
		Define:    s.Tok == token.DEFINE,
		X:         x,
		Body:      body,
	}, nil
}

// transDefer handles `defer f(args)`. The Go AST's `*ast.DeferStmt`
// holds a single `*ast.CallExpr`; we lower it to either an
// `*ir.BuiltinCall` (for `defer panic(x)` — unusual but legal) or
// the general `*ir.Call`. Both implement Stmt and so satisfy the
// IR `DeferStmt.Call Stmt` field. Other defer-able shapes (method
// values, function literals) re-route through transExpr's standard
// dispatch and surface the usual unsupported errors at the right
// failure axis.
func transDefer(s *ast.DeferStmt) (*ir.DeferStmt, error) {
	if b, ok, err := tryBuiltinCall(s.Call); err != nil {
		return nil, err
	} else if ok {
		return &ir.DeferStmt{Call: b}, nil
	}
	c, err := transCall(s.Call)
	if err != nil {
		return nil, err
	}
	return &ir.DeferStmt{Call: c}, nil
}

// transGo handles `go f(args)`. Mirrors transDefer — the Go AST's
// `*ast.GoStmt` carries a single `*ast.CallExpr`, lowered through
// the same builtin-vs-general split. `go panic(x)` and `go recover()`
// are rejected by the Go compiler at semantic analysis (gc emits
// `go discards result of recover()` / parser-level for panic),
// but the parser still produces the AST shape; widening Call to
// Stmt keeps the IR symmetrical with DeferStmt and lets the emit
// layer surface the rejection on the right axis (the Phase 3
// emit's GoStmt handler refuses BuiltinCall payloads).
func transGo(s *ast.GoStmt) (*ir.GoStmt, error) {
	if b, ok, err := tryBuiltinCall(s.Call); err != nil {
		return nil, err
	} else if ok {
		return &ir.GoStmt{Call: b}, nil
	}
	c, err := transCall(s.Call)
	if err != nil {
		return nil, err
	}
	return &ir.GoStmt{Call: c}, nil
}

// identNameOrBlank extracts a bare identifier name from a Go AST
// expression, treating nil and the blank `_` identifier identically
// (both lower to an empty IR name). Anything more complex — selector
// chains, index expressions — is rejected because Go's range syntax
// only ever binds bare identifiers as the key/value receivers.
func identNameOrBlank(e ast.Expr) (string, error) {
	if e == nil {
		return "", nil
	}
	id, ok := e.(*ast.Ident)
	if !ok {
		return "", fmt.Errorf("translate: range key/value must be an identifier (got %T)", e)
	}
	if id.Name == "_" {
		return "", nil
	}
	return id.Name, nil
}

func transAssign(s *ast.AssignStmt) (*ir.Assign, error) {
	if s.Tok != token.ASSIGN && s.Tok != token.DEFINE {
		return nil, fmt.Errorf("translate: unsupported assign token %s", s.Tok)
	}
	lhs, err := transExprList(s.Lhs)
	if err != nil {
		return nil, err
	}
	rhs, err := transExprList(s.Rhs)
	if err != nil {
		return nil, err
	}
	return &ir.Assign{LHS: lhs, Define: s.Tok == token.DEFINE, RHS: rhs}, nil
}

func transIf(s *ast.IfStmt) (*ir.If, error) {
	if s.Init != nil {
		return nil, fmt.Errorf("translate: if-with-init not supported in Phase 1")
	}
	cond, err := transExpr(s.Cond)
	if err != nil {
		return nil, err
	}
	then, err := transStmtList(s.Body.List)
	if err != nil {
		return nil, err
	}

	var els []ir.Stmt
	switch e := s.Else.(type) {
	case nil:
		els = nil
	case *ast.BlockStmt:
		els, err = transStmtList(e.List)
		if err != nil {
			return nil, err
		}
	case *ast.IfStmt:
		nested, nerr := transIf(e)
		if nerr != nil {
			return nil, nerr
		}
		els = []ir.Stmt{nested}
	default:
		return nil, fmt.Errorf("translate: unsupported else %T", e)
	}
	return &ir.If{Cond: cond, Then: then, Else: els}, nil
}

func transFor(s *ast.ForStmt) (*ir.For, error) {
	var init ir.Stmt
	var cond ir.Expr
	var post ir.Stmt
	var err error
	if s.Init != nil {
		init, err = transStmt(s.Init)
		if err != nil {
			return nil, err
		}
	}
	if s.Cond != nil {
		cond, err = transExpr(s.Cond)
		if err != nil {
			return nil, err
		}
	}
	if s.Post != nil {
		post, err = transStmt(s.Post)
		if err != nil {
			return nil, err
		}
	}
	body, err := transStmtList(s.Body.List)
	if err != nil {
		return nil, err
	}
	return &ir.For{Init: init, Cond: cond, Post: post, Body: body}, nil
}

func transReturn(s *ast.ReturnStmt) (*ir.Return, error) {
	results, err := transExprList(s.Results)
	if err != nil {
		return nil, err
	}
	return &ir.Return{Results: results}, nil
}

// transExprStmt narrows an *ast.ExprStmt into either the IR's Call
// (when the wrapped expression is a function call — by far the
// common case for the corpus, e.g. `fmt.Println(...)`), an
// *ir.BuiltinCall (when the call's Fun is a recognised Go predeclared
// identifier — `panic("boom")` is the Phase 2 driver), or the more
// general ir.ExprStmt wrapper.
func transExprStmt(s *ast.ExprStmt) (ir.Stmt, error) {
	if call, ok := s.X.(*ast.CallExpr); ok {
		if b, ok, err := tryBuiltinCall(call); err != nil {
			return nil, err
		} else if ok {
			return b, nil
		}
		return transCall(call)
	}
	x, err := transExpr(s.X)
	if err != nil {
		return nil, err
	}
	return &ir.ExprStmt{X: x}, nil
}

// tryBuiltinCall returns (b, true, nil) iff c is a call to one of the
// recognised Go predeclared identifiers. Returns (nil, false, nil)
// for non-builtin calls so the caller falls through to its general
// path; an error iff arg translation fails.
//
// The detection is name-based and shadowing-aware only by accident:
// if a user's local `len := 1` is later called, this still routes to
// BuiltinCall — Phase 2 accepts that. Real disambiguation needs
// *types.Info, which the translator does not yet plumb through.
func tryBuiltinCall(c *ast.CallExpr) (*ir.BuiltinCall, bool, error) {
	id, ok := c.Fun.(*ast.Ident)
	if !ok || !builtinNames[id.Name] {
		return nil, false, nil
	}
	args, err := transExprList(c.Args)
	if err != nil {
		return nil, false, err
	}
	return &ir.BuiltinCall{Name: id.Name, Args: args}, true, nil
}

func transCall(c *ast.CallExpr) (*ir.Call, error) {
	fun, err := transExpr(c.Fun)
	if err != nil {
		return nil, err
	}
	args, err := transExprList(c.Args)
	if err != nil {
		return nil, err
	}
	return &ir.Call{Fun: fun, Args: args}, nil
}

// --- expressions ----------------------------------------------------------

func transExprList(es []ast.Expr) ([]ir.Expr, error) {
	if len(es) == 0 {
		return nil, nil
	}
	out := make([]ir.Expr, 0, len(es))
	for _, e := range es {
		te, err := transExpr(e)
		if err != nil {
			return nil, err
		}
		out = append(out, te)
	}
	return out, nil
}

func transExpr(e ast.Expr) (ir.Expr, error) {
	switch e := e.(type) {
	case *ast.Ident:
		return transIdent(e), nil
	case *ast.BasicLit:
		return transBasicLit(e)
	case *ast.BinaryExpr:
		return transBinary(e)
	case *ast.UnaryExpr:
		return transUnary(e)
	case *ast.SelectorExpr:
		return transSelector(e)
	case *ast.ParenExpr:
		// Phase 1 IR has no paren node — operator precedence is
		// captured by tree shape, and the emitter can re-paren on
		// output if it needs to. So we transparently unwrap.
		return transExpr(e.X)
	case *ast.CompositeLit:
		return transCompositeLit(e)
	case *ast.IndexExpr:
		return transIndex(e)
	case *ast.SliceExpr:
		return transSlice(e)
	case *ast.CallExpr:
		// Only builtin calls are valid in expression position in
		// Phase 2; general call-as-expression (e.g. `f()` on the RHS
		// of an assign) still needs *types.Info plumbing to
		// distinguish a function call from a type conversion. The
		// builtins return values that the corpus already needs:
		// `xs = append(xs, 4)`, `n := len(xs)`, `if r := recover(); …`.
		b, ok, err := tryBuiltinCall(e)
		if err != nil {
			return nil, err
		}
		if !ok {
			return nil, fmt.Errorf("translate: general call-as-expression not supported in Phase 2 (only builtin calls are)")
		}
		return b, nil
	default:
		return nil, fmt.Errorf("translate: unsupported expr %T", e)
	}
}

// transCompositeLit handles slice and map composite literals —
// `[]T{e1, e2}` and `map[K]V{k1: v1, k2: v2}` — which lower to
// `*ir.SliceLit` and `*ir.MapLit` respectively. Struct literals and
// fixed-size array literals are post-1.0.
func transCompositeLit(c *ast.CompositeLit) (ir.Expr, error) {
	if c.Type == nil {
		return nil, fmt.Errorf("translate: composite literal with elided type not supported in Phase 2")
	}
	switch ct := c.Type.(type) {
	case *ast.ArrayType:
		if ct.Len != nil {
			return nil, fmt.Errorf("translate: fixed-size array composite literals not supported in Phase 2")
		}
		elem, err := transType(ct.Elt)
		if err != nil {
			return nil, err
		}
		elems, err := transExprList(c.Elts)
		if err != nil {
			return nil, err
		}
		return &ir.SliceLit{Elem: elem, Elems: elems}, nil
	case *ast.MapType:
		k, err := transType(ct.Key)
		if err != nil {
			return nil, err
		}
		v, err := transType(ct.Value)
		if err != nil {
			return nil, err
		}
		entries, err := transMapEntries(c.Elts)
		if err != nil {
			return nil, err
		}
		return &ir.MapLit{Key: k, Value: v, Entries: entries}, nil
	default:
		return nil, fmt.Errorf("translate: only []T and map[K]V composite literals are supported in Phase 2 (got %T)", c.Type)
	}
}

// transMapEntries lifts a Go composite-literal element list into the
// IR's *MapEntry slice. Each element must be a `*ast.KeyValueExpr` —
// Go's grammar guarantees that for `map[K]V{...}` literals, but we
// re-check at the IR boundary so a malformed AST surfaces here
// instead of crashing the emitter.
func transMapEntries(es []ast.Expr) ([]*ir.MapEntry, error) {
	if len(es) == 0 {
		return nil, nil
	}
	out := make([]*ir.MapEntry, 0, len(es))
	for _, e := range es {
		kv, ok := e.(*ast.KeyValueExpr)
		if !ok {
			return nil, fmt.Errorf("translate: map composite literal entry must be K: V (got %T)", e)
		}
		k, err := transExpr(kv.Key)
		if err != nil {
			return nil, err
		}
		v, err := transExpr(kv.Value)
		if err != nil {
			return nil, err
		}
		out = append(out, &ir.MapEntry{Key: k, Value: v})
	}
	return out, nil
}

func transIndex(e *ast.IndexExpr) (*ir.IndexExpr, error) {
	x, err := transExpr(e.X)
	if err != nil {
		return nil, err
	}
	idx, err := transExpr(e.Index)
	if err != nil {
		return nil, err
	}
	return &ir.IndexExpr{X: x, Index: idx}, nil
}

// transSlice handles `s[Low:High]`, including the elided forms
// `s[:H]`, `s[L:]`, and `s[:]`. The three-index form `s[L:H:M]` is
// rejected for Phase 2 — capacity-bounded sub-slices are post-1.0.
func transSlice(e *ast.SliceExpr) (*ir.SliceExpr, error) {
	if e.Slice3 || e.Max != nil {
		return nil, fmt.Errorf("translate: three-index slice expression (s[l:h:m]) not supported in Phase 2")
	}
	x, err := transExpr(e.X)
	if err != nil {
		return nil, err
	}
	var lo, hi ir.Expr
	if e.Low != nil {
		lo, err = transExpr(e.Low)
		if err != nil {
			return nil, err
		}
	}
	if e.High != nil {
		hi, err = transExpr(e.High)
		if err != nil {
			return nil, err
		}
	}
	return &ir.SliceExpr{X: x, Low: lo, High: hi}, nil
}

// transIdent normalises predeclared bool literals (`true`/`false`)
// into ir.Lit with Kind=LitBool. Go represents them as plain Idents
// because they are predeclared identifiers, but the IR — and the
// emitter — treats them as literal values.
func transIdent(i *ast.Ident) ir.Expr {
	switch i.Name {
	case "true", "false":
		return &ir.Lit{Kind: ir.LitBool, Value: i.Name}
	default:
		return &ir.Ident{Name: i.Name}
	}
}

func transBasicLit(b *ast.BasicLit) (ir.Expr, error) {
	var k ir.LitKind
	switch b.Kind {
	case token.INT:
		k = ir.LitInt
	case token.STRING:
		k = ir.LitString
	case token.FLOAT:
		k = ir.LitFloat
	default:
		return nil, fmt.Errorf("translate: unsupported literal kind %s", b.Kind)
	}
	return &ir.Lit{Kind: k, Value: b.Value}, nil
}

func transBinary(b *ast.BinaryExpr) (*ir.BinOp, error) {
	x, err := transExpr(b.X)
	if err != nil {
		return nil, err
	}
	y, err := transExpr(b.Y)
	if err != nil {
		return nil, err
	}
	return &ir.BinOp{Op: b.Op.String(), X: x, Y: y}, nil
}

func transUnary(u *ast.UnaryExpr) (*ir.UnaryOp, error) {
	x, err := transExpr(u.X)
	if err != nil {
		return nil, err
	}
	return &ir.UnaryOp{Op: u.Op.String(), X: x}, nil
}

func transSelector(sel *ast.SelectorExpr) (*ir.Selector, error) {
	x, err := transExpr(sel.X)
	if err != nil {
		return nil, err
	}
	return &ir.Selector{X: x, Sel: sel.Sel.Name}, nil
}
