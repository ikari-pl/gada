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

// transType maps the four basic Go type names recognised in Phase 1
// to their IR counterparts. Anything else (composite types, named
// types, etc.) is rejected.
func transType(e ast.Expr) (ir.Type, error) {
	id, ok := e.(*ast.Ident)
	if !ok {
		return nil, fmt.Errorf("translate: unsupported type expr %T", e)
	}
	switch id.Name {
	case "int":
		return &ir.IntType{}, nil
	case "string":
		return &ir.StringType{}, nil
	case "bool":
		return &ir.BoolType{}, nil
	case "float64":
		return &ir.Float64Type{}, nil
	default:
		return nil, fmt.Errorf("translate: unsupported type %q", id.Name)
	}
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
	case *ast.ReturnStmt:
		return transReturn(s)
	case *ast.ExprStmt:
		return transExprStmt(s)
	default:
		return nil, fmt.Errorf("translate: unsupported stmt %T", s)
	}
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
// common case for the corpus, e.g. `fmt.Println(...)`) or the more
// general ir.ExprStmt wrapper.
func transExprStmt(s *ast.ExprStmt) (ir.Stmt, error) {
	if call, ok := s.X.(*ast.CallExpr); ok {
		return transCall(call)
	}
	x, err := transExpr(s.X)
	if err != nil {
		return nil, err
	}
	return &ir.ExprStmt{X: x}, nil
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
	default:
		return nil, fmt.Errorf("translate: unsupported expr %T", e)
	}
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
