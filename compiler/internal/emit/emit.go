// Package emit produces Ada source from GADA IR.
//
// Phase 1 scope mirrors the corpus in
// compiler/internal/translate/testdata: package-level functions made
// of assignments, ifs, classic-or-infinite for-loops, returns, and
// calls; expressions over the four basic types int / string / bool /
// float64; and a single recognised standard-library call,
// `fmt.Println`. Anything outside that subset returns an explicit
// "not supported in Phase 1" error rather than producing silently
// wrong Ada.
//
// Output shape, one Ada compilation unit per ir.File:
//
//   - Go `package main` becomes a standalone subprogram, `procedure
//     Main is ... end Main;`. If the file contains a `func main()`
//     (no params, no results), its body forms the procedure body and
//     any other top-level functions become nested subprograms.
//     Otherwise the procedure body is `null;` and every Go func is
//     nested.
//   - Any other package becomes an Ada package body, `package body P
//     is ... end P;`, with each top-level Go func emitted as a
//     sibling subprogram.
//
// Type mapping: int→Integer, string→String, bool→Boolean,
// float64→Long_Float.
//
// `:=` assignments at the head of a function body are hoisted into
// the declarative region; subsequent plain `=` becomes Ada `:=`. The
// trivial integer for-loop pattern
// `for i := S; i < E; i = i + 1 { ... }` is recognised and emitted as
// `for I in S .. E - 1 loop ... end loop;`. The bare `for { ... }`
// becomes Ada `loop ... end loop;`.
//
// `fmt.Println(...)` is rewritten to `Println (...)` and a top-of-
// file `with Gada.Core.IO; use Gada.Core.IO;` is added when the file
// imports "fmt".
//
// Identifier policy: Go names are first-letter-capitalised so they
// look canonically Ada. A name whose lowercase form is an Ada reserved
// word (e.g. Go `loop`) gains a `_K` suffix to avoid the collision.
package emit

import (
	_ "embed"
	"fmt"
	"io"
	"strconv"
	"strings"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// ProjectTemplate is the text/template body of the GNAT project file
// the `gada build` driver renders alongside emitted Ada sources. It
// is exposed as a string so the driver in compiler/cmd/gada can fill
// it without depending on an on-disk path. The fields are:
//
//	{{.ProjectName}}    Ada project name (also the .gpr base name)
//	{{.RuntimeProject}} Path (without extension) to gada_core.gpr
//	{{.SourceDir}}      Directory holding emitted .adb / .ads files
//	{{.ObjectDir}}      gprbuild's object directory
//	{{.ExecDir}}        Where the produced binary lands
//	{{.MainFile}}       Main subprogram's source file (e.g. "main.adb")
//
//go:embed template.gpr.tmpl
var ProjectTemplate string

// Package writes the Ada compilation unit for the given IR package
// to w. Phase 1 expects the package to contain exactly one file; the
// translator currently produces one *ir.File per Go source file, so
// this contract holds end-to-end.
func Package(p *ir.Package, w io.Writer) error {
	if p == nil {
		return fmt.Errorf("emit: nil package")
	}
	if len(p.Files) != 1 {
		return fmt.Errorf("emit: expected exactly one file, got %d", len(p.Files))
	}
	e := newEmitter(p.Name, p.Files[0])
	if err := e.run(); err != nil {
		return err
	}
	_, err := io.WriteString(w, e.buf.String())
	return err
}

// emitter accumulates Ada source into buf with a current indent
// level. Errors are sticky on err and silence further work via the
// guards in emitStmt / emitExpr / etc.
type emitter struct {
	pkgName string
	file    *ir.File

	buf    strings.Builder
	indent int

	needsCoreIO bool
	err         error
}

func newEmitter(pkg string, f *ir.File) *emitter {
	e := &emitter{pkgName: pkg, file: f}
	for _, imp := range f.Imports {
		if imp == "fmt" {
			e.needsCoreIO = true
		}
	}
	return e
}

func (e *emitter) run() error {
	if e.needsCoreIO {
		e.println("with Gada.Core.IO; use Gada.Core.IO;")
		e.println("")
	}
	if e.pkgName == "main" {
		e.emitMainProcedure()
	} else {
		e.emitPackageBody()
	}
	return e.err
}

// println writes a single line, prefixed with the current indent
// (three spaces per level — matches the runtime style). An empty
// string emits a bare newline with no indentation, used for the
// blank lines that separate sections.
func (e *emitter) println(s string) {
	if s == "" {
		e.buf.WriteByte('\n')
		return
	}
	for i := 0; i < e.indent; i++ {
		e.buf.WriteString("   ")
	}
	e.buf.WriteString(s)
	e.buf.WriteByte('\n')
}

func (e *emitter) fail(err error) {
	if e.err == nil {
		e.err = err
	}
}

// findMain returns the file's `func main()` (no params, no results)
// if any; otherwise nil. Only useful when pkgName == "main".
func (e *emitter) findMain() *ir.Function {
	for _, d := range e.file.Decls {
		fn, ok := d.(*ir.Function)
		if !ok {
			continue
		}
		if fn.Name == "main" && len(fn.Params) == 0 && len(fn.Results) == 0 {
			return fn
		}
	}
	return nil
}

// emitMainProcedure handles every Go `package main` file: it produces
// `procedure Main is <nested-subs + hoisted-decls> begin <main-body>
// end Main;`. With no nested subprograms and no hoisted declarations
// the layout collapses to the tight `procedure Main is begin ... end
// Main;` form.
func (e *emitter) emitMainProcedure() {
	main := e.findMain()
	var others []*ir.Function
	for _, d := range e.file.Decls {
		fn, ok := d.(*ir.Function)
		if !ok {
			e.fail(fmt.Errorf("emit: top-level %T not supported in Phase 1", d))
			return
		}
		if fn != main {
			others = append(others, fn)
		}
	}

	var mainDecls []*ir.Assign
	var mainBody []ir.Stmt
	if main != nil {
		mainDecls, mainBody = splitDecls(main.Body)
	}

	hasDeclSection := len(others) > 0 || len(mainDecls) > 0

	e.println("procedure Main is")
	if hasDeclSection {
		e.println("")
	}

	e.indent++
	for i, fn := range others {
		if i > 0 {
			e.println("")
		}
		e.emitSubprogram(fn)
	}
	if len(others) > 0 && len(mainDecls) > 0 {
		e.println("")
	}
	for _, a := range mainDecls {
		e.emitVarDecl(a)
	}
	e.indent--

	if hasDeclSection {
		e.println("")
	}

	e.println("begin")
	e.indent++
	if len(mainBody) == 0 {
		e.println("null;")
	} else {
		for _, s := range mainBody {
			e.emitStmt(s)
		}
	}
	e.indent--
	e.println("end Main;")
}

// emitPackageBody handles non-main packages: emits `package body P
// is ... end P;` with one sibling subprogram per top-level Go func.
func (e *emitter) emitPackageBody() {
	pkg := adaIdent(e.pkgName)

	var fns []*ir.Function
	for _, d := range e.file.Decls {
		fn, ok := d.(*ir.Function)
		if !ok {
			e.fail(fmt.Errorf("emit: top-level %T not supported in Phase 1", d))
			return
		}
		fns = append(fns, fn)
	}

	e.println("package body " + pkg + " is")
	if len(fns) > 0 {
		e.println("")
	}

	e.indent++
	for i, fn := range fns {
		if i > 0 {
			e.println("")
		}
		e.emitSubprogram(fn)
	}
	e.indent--

	if len(fns) > 0 {
		e.println("")
	}
	e.println("end " + pkg + ";")
}

// emitSubprogram writes one function or procedure body, with its
// hoisted declarations and statement body.
func (e *emitter) emitSubprogram(fn *ir.Function) {
	if e.err != nil {
		return
	}
	header, name, ok := e.subpHeader(fn)
	if !ok {
		return
	}
	e.println(header)

	decls, body := splitDecls(fn.Body)
	e.indent++
	for _, a := range decls {
		e.emitVarDecl(a)
	}
	e.indent--

	e.println("begin")

	e.indent++
	if len(body) == 0 {
		e.println("null;")
	} else {
		for _, s := range body {
			e.emitStmt(s)
		}
	}
	e.indent--

	e.println("end " + name + ";")
}

// subpHeader returns the Ada header line for fn ("function Foo (...)
// return T is" or "procedure Bar (...) is"), the (renamed) Ada
// identifier, and ok=false if any part of the signature is
// unsupported.
func (e *emitter) subpHeader(fn *ir.Function) (string, string, bool) {
	name := adaIdent(fn.Name)

	var params string
	if len(fn.Params) > 0 {
		ps := make([]string, 0, len(fn.Params))
		for _, p := range fn.Params {
			t, err := typeName(p.Type)
			if err != nil {
				e.fail(err)
				return "", name, false
			}
			ps = append(ps, adaIdent(p.Name)+" : "+t)
		}
		params = " (" + strings.Join(ps, "; ") + ")"
	}

	if len(fn.Results) == 0 {
		return "procedure " + name + params + " is", name, true
	}
	if len(fn.Results) > 1 {
		e.fail(fmt.Errorf("emit: multi-value return on %s not supported in Phase 1", fn.Name))
		return "", name, false
	}
	rt, err := typeName(fn.Results[0].Type)
	if err != nil {
		e.fail(err)
		return "", name, false
	}
	return "function " + name + params + " return " + rt + " is", name, true
}

// splitDecls peels the leading run of `Assign{Define:true}` off the
// front of body and returns them separately. Any `:=` later in the
// body falls through to emitAssign and is rejected as a Phase 1
// limitation.
func splitDecls(body []ir.Stmt) ([]*ir.Assign, []ir.Stmt) {
	var decls []*ir.Assign
	i := 0
	for i < len(body) {
		a, ok := body[i].(*ir.Assign)
		if !ok || !a.Define {
			break
		}
		decls = append(decls, a)
		i++
	}
	return decls, body[i:]
}

func (e *emitter) emitVarDecl(a *ir.Assign) {
	if e.err != nil {
		return
	}
	if len(a.LHS) != 1 || len(a.RHS) != 1 {
		e.fail(fmt.Errorf("emit: multi-value := not supported in Phase 1"))
		return
	}
	id, ok := a.LHS[0].(*ir.Ident)
	if !ok {
		e.fail(fmt.Errorf("emit: := lhs must be a plain identifier in Phase 1"))
		return
	}
	typ, err := inferDeclType(a.RHS[0])
	if err != nil {
		e.fail(err)
		return
	}
	rhs := e.emitExpr(a.RHS[0])
	e.println(adaIdent(id.Name) + " : " + typ + " := " + rhs + ";")
}

// inferDeclType maps a literal RHS to its Ada type name. Phase 1
// only supports literal RHS in `:=` because we have no real
// type-inference plumbing yet; non-literal RHS would need to consult
// types.Info, which the translator does not yet pass through.
func inferDeclType(x ir.Expr) (string, error) {
	l, ok := x.(*ir.Lit)
	if !ok {
		return "", fmt.Errorf("emit: := requires a literal RHS in Phase 1, got %T", x)
	}
	switch l.Kind {
	case ir.LitInt:
		return "Integer", nil
	case ir.LitString:
		return "String", nil
	case ir.LitBool:
		return "Boolean", nil
	case ir.LitFloat:
		return "Long_Float", nil
	}
	return "", fmt.Errorf("emit: unknown literal kind %q", l.Kind)
}

// --- statements -----------------------------------------------------------

func (e *emitter) emitStmt(s ir.Stmt) {
	if e.err != nil {
		return
	}
	switch s := s.(type) {
	case *ir.Assign:
		e.emitAssign(s)
	case *ir.If:
		e.emitIf(s)
	case *ir.For:
		e.emitFor(s)
	case *ir.Return:
		e.emitReturn(s)
	case *ir.Call:
		e.emitCallStmt(s)
	case *ir.ExprStmt:
		e.emitExprStmt(s)
	default:
		e.fail(fmt.Errorf("emit: unsupported stmt %T", s))
	}
}

func (e *emitter) emitAssign(a *ir.Assign) {
	if a.Define {
		e.fail(fmt.Errorf("emit: := outside head of function body not supported in Phase 1"))
		return
	}
	if len(a.LHS) != 1 || len(a.RHS) != 1 {
		e.fail(fmt.Errorf("emit: multi-value assignment not supported in Phase 1"))
		return
	}
	lhs := e.emitExpr(a.LHS[0])
	rhs := e.emitExpr(a.RHS[0])
	e.println(lhs + " := " + rhs + ";")
}

func (e *emitter) emitIf(s *ir.If) {
	cond := e.emitExpr(s.Cond)
	e.println("if " + cond + " then")
	e.indent++
	for _, t := range s.Then {
		e.emitStmt(t)
	}
	e.indent--
	e.emitElseChain(s.Else)
}

// emitElseChain handles the `else` / `elsif` cascade. A single
// nested *ir.If becomes `elsif`; everything else becomes a plain
// `else` block. The recursion folds chains of `else if` statements
// into a single Ada if/elsif/else/end-if construct.
func (e *emitter) emitElseChain(els []ir.Stmt) {
	if len(els) == 0 {
		e.println("end if;")
		return
	}
	if len(els) == 1 {
		if nested, ok := els[0].(*ir.If); ok {
			e.println("elsif " + e.emitExpr(nested.Cond) + " then")
			e.indent++
			for _, t := range nested.Then {
				e.emitStmt(t)
			}
			e.indent--
			e.emitElseChain(nested.Else)
			return
		}
	}
	e.println("else")
	e.indent++
	for _, s := range els {
		e.emitStmt(s)
	}
	e.indent--
	e.println("end if;")
}

func (e *emitter) emitReturn(r *ir.Return) {
	if len(r.Results) == 0 {
		e.println("return;")
		return
	}
	if len(r.Results) > 1 {
		e.fail(fmt.Errorf("emit: multi-value return not supported in Phase 1"))
		return
	}
	e.println("return " + e.emitExpr(r.Results[0]) + ";")
}

func (e *emitter) emitFor(f *ir.For) {
	// Bare `for { ... }`.
	if f.Init == nil && f.Cond == nil && f.Post == nil {
		e.println("loop")
		e.indent++
		if len(f.Body) == 0 {
			e.println("null;")
		} else {
			for _, s := range f.Body {
				e.emitStmt(s)
			}
		}
		e.indent--
		e.println("end loop;")
		return
	}
	// Trivial integer for: `for V := S; V < E; V = V + 1 { ... }`.
	if v, start, end, ok := matchTrivialFor(f); ok {
		header := "for " + adaIdent(v) +
			" in " + e.emitExpr(start) +
			" .. " + e.emitBinOperand(end) +
			" - 1 loop"
		e.println(header)
		e.indent++
		if len(f.Body) == 0 {
			e.println("null;")
		} else {
			for _, s := range f.Body {
				e.emitStmt(s)
			}
		}
		e.indent--
		e.println("end loop;")
		return
	}
	e.fail(fmt.Errorf("emit: only trivial integer for-loops and bare for {} are supported in Phase 1"))
}

// matchTrivialFor recognises the `for V := <start>; V < <end>; V = V
// + 1 { ... }` shape and returns its components. Anything else
// returns ok=false so the caller can fall back to an error.
func matchTrivialFor(f *ir.For) (string, ir.Expr, ir.Expr, bool) {
	initA, ok := f.Init.(*ir.Assign)
	if !ok || !initA.Define || len(initA.LHS) != 1 || len(initA.RHS) != 1 {
		return "", nil, nil, false
	}
	initIdent, ok := initA.LHS[0].(*ir.Ident)
	if !ok {
		return "", nil, nil, false
	}
	v := initIdent.Name

	cond, ok := f.Cond.(*ir.BinOp)
	if !ok || cond.Op != "<" {
		return "", nil, nil, false
	}
	condIdent, ok := cond.X.(*ir.Ident)
	if !ok || condIdent.Name != v {
		return "", nil, nil, false
	}

	postA, ok := f.Post.(*ir.Assign)
	if !ok || postA.Define || len(postA.LHS) != 1 || len(postA.RHS) != 1 {
		return "", nil, nil, false
	}
	postIdent, ok := postA.LHS[0].(*ir.Ident)
	if !ok || postIdent.Name != v {
		return "", nil, nil, false
	}
	postBin, ok := postA.RHS[0].(*ir.BinOp)
	if !ok || postBin.Op != "+" {
		return "", nil, nil, false
	}
	postX, _ := postBin.X.(*ir.Ident)
	postY, _ := postBin.Y.(*ir.Lit)
	if postX == nil || postX.Name != v || postY == nil ||
		postY.Kind != ir.LitInt || postY.Value != "1" {
		return "", nil, nil, false
	}
	return v, initA.RHS[0], cond.Y, true
}

func (e *emitter) emitCallStmt(c *ir.Call) {
	fun := e.emitExpr(c.Fun)
	args := make([]string, 0, len(c.Args))
	for _, a := range c.Args {
		args = append(args, e.emitExpr(a))
	}
	if len(args) == 0 {
		e.println(fun + ";")
		return
	}
	e.println(fun + " (" + strings.Join(args, ", ") + ");")
}

// emitExprStmt renders Go's bare expression-statement (e.g. a stray
// `-x` line) as Ada `null;`. Ada does not allow expression-position
// statements, and Go's `gc` would reject these too — but the corpus
// includes one to exercise the IR path, so we accept it lossily.
func (e *emitter) emitExprStmt(s *ir.ExprStmt) {
	_ = s
	e.println("null;")
}

// --- expressions ----------------------------------------------------------

func (e *emitter) emitExpr(x ir.Expr) string {
	if e.err != nil {
		return ""
	}
	switch x := x.(type) {
	case *ir.Ident:
		return adaIdent(x.Name)
	case *ir.Lit:
		return e.emitLit(x)
	case *ir.BinOp:
		return e.emitBinOp(x)
	case *ir.UnaryOp:
		return e.emitUnaryOp(x)
	case *ir.Selector:
		return e.emitSelector(x)
	}
	e.fail(fmt.Errorf("emit: unsupported expr %T", x))
	return ""
}

func (e *emitter) emitLit(l *ir.Lit) string {
	switch l.Kind {
	case ir.LitInt, ir.LitFloat:
		return l.Value
	case ir.LitBool:
		if l.Value == "true" {
			return "True"
		}
		return "False"
	case ir.LitString:
		unq, err := strconv.Unquote(l.Value)
		if err != nil {
			e.fail(fmt.Errorf("emit: bad string literal %s: %w", l.Value, err))
			return l.Value
		}
		for _, r := range unq {
			if r < 0x20 || r == 0x7F {
				e.fail(fmt.Errorf("emit: control characters in string literals are not supported in Phase 1"))
				return l.Value
			}
		}
		return `"` + strings.ReplaceAll(unq, `"`, `""`) + `"`
	}
	e.fail(fmt.Errorf("emit: unknown literal kind %q", l.Kind))
	return l.Value
}

func (e *emitter) emitBinOp(b *ir.BinOp) string {
	op := translateBinOp(b.Op)
	if op == "" {
		e.fail(fmt.Errorf("emit: unsupported binary op %q", b.Op))
		return ""
	}
	return e.emitBinOperand(b.X) + " " + op + " " + e.emitBinOperand(b.Y)
}

// emitBinOperand emits a sub-expression of a BinOp, parenthesising
// it if it is itself a BinOp. This re-imposes the parentheses the
// translator stripped via *ast.ParenExpr; it is conservative but
// always-correct for Phase 1 precedence.
func (e *emitter) emitBinOperand(x ir.Expr) string {
	s := e.emitExpr(x)
	if _, ok := x.(*ir.BinOp); ok {
		return "(" + s + ")"
	}
	return s
}

func translateBinOp(goOp string) string {
	switch goOp {
	case "+", "-", "*", "/", "<", ">", "<=", ">=":
		return goOp
	case "==":
		return "="
	case "!=":
		return "/="
	case "&&":
		return "and"
	case "||":
		return "or"
	case "%":
		return "mod"
	}
	return ""
}

func (e *emitter) emitUnaryOp(u *ir.UnaryOp) string {
	s := e.emitExpr(u.X)
	if _, ok := u.X.(*ir.BinOp); ok {
		s = "(" + s + ")"
	}
	switch u.Op {
	case "-":
		return "-" + s
	case "+":
		return "+" + s
	case "!":
		return "not " + s
	}
	e.fail(fmt.Errorf("emit: unsupported unary op %q", u.Op))
	return s
}

// emitSelector special-cases `fmt.Println` (the only stdlib symbol
// the Phase 1 corpus uses). Every other selector falls through to a
// dotted Ada reference; that path is exercised in error tests but
// won't produce compilable Ada until later phases plumb proper
// package translation.
func (e *emitter) emitSelector(s *ir.Selector) string {
	if id, ok := s.X.(*ir.Ident); ok && id.Name == "fmt" && s.Sel == "Println" {
		return "Println"
	}
	return e.emitExpr(s.X) + "." + s.Sel
}

// --- identifiers ----------------------------------------------------------

// adaIdent capitalises the first rune of a Go identifier and appends
// `_K` if its lowercase form collides with an Ada reserved word.
// Unlike a trailing underscore (which Ada disallows in identifiers),
// `_K` is always a valid identifier suffix.
func adaIdent(s string) string {
	caps := capitalize(s)
	if isAdaReserved(s) {
		return caps + "_K"
	}
	return caps
}

func capitalize(s string) string {
	if s == "" {
		return s
	}
	r := []rune(s)
	if r[0] >= 'a' && r[0] <= 'z' {
		r[0] = r[0] - 'a' + 'A'
	}
	return string(r)
}

// isAdaReserved tests s (lowercased) against the Ada 2022 reserved
// word list. The list is the union of Ada 83/95/2005/2012/2022
// reserved words.
func isAdaReserved(s string) bool {
	switch strings.ToLower(s) {
	case "abort", "abs", "abstract", "accept", "access", "aliased", "all",
		"and", "array", "at", "begin", "body", "case", "constant", "declare",
		"delay", "delta", "digits", "do", "else", "elsif", "end", "entry",
		"exception", "exit", "for", "function", "generic", "goto", "if",
		"in", "interface", "is", "limited", "loop", "mod", "new", "not",
		"null", "of", "or", "others", "out", "overriding", "package",
		"parallel", "pragma", "private", "procedure", "protected", "raise",
		"range", "record", "rem", "renames", "requeue", "return", "reverse",
		"select", "separate", "some", "subtype", "synchronized", "tagged",
		"task", "terminate", "then", "type", "until", "use", "when", "while",
		"with", "xor":
		return true
	}
	return false
}

// typeName maps a Phase 1 IR type to its Ada equivalent. Anything
// outside the four basic types is rejected.
func typeName(t ir.Type) (string, error) {
	switch t.(type) {
	case *ir.IntType:
		return "Integer", nil
	case *ir.StringType:
		return "String", nil
	case *ir.BoolType:
		return "Boolean", nil
	case *ir.Float64Type:
		return "Long_Float", nil
	case nil:
		return "", fmt.Errorf("emit: missing type")
	}
	return "", fmt.Errorf("emit: unsupported type %T", t)
}
