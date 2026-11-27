package translate

import (
	"fmt"
	"go/ast"
	"go/types"
	"strconv"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// translator carries the per-file translation context: the import
// table (local name → path, needed to recognise stdlib package calls
// in expression position) and the *types.Info handle (needed to type
// call results). All trans*/try* functions are methods on it, so
// parallel corpus tests never share mutable state (CI runs -race).
type translator struct {
	imports map[string]string // local import name → import path
	info    *types.Info
}

// newTranslator builds the context for one file (the driver loads
// exactly one .go file per package).
func newTranslator(f *ast.File, info *types.Info) (*translator, error) {
	tr := &translator{imports: map[string]string{}, info: info}
	for _, imp := range f.Imports {
		path, err := strconv.Unquote(imp.Path.Value)
		if err != nil {
			return nil, fmt.Errorf("translate: bad import path %s: %w", imp.Path.Value, err)
		}
		name := path
		if i := lastSlash(path); i >= 0 {
			name = path[i+1:]
		}
		if imp.Name != nil {
			name = imp.Name.Name
		}
		tr.imports[name] = path
	}
	return tr, nil
}

// Test-facing wrappers: the corpus and unit tests call the leaf
// translators directly. Each builds a fresh empty translator so no
// state is shared between parallel tests.
func transType(e ast.Expr) (ir.Type, error) { return (&translator{}).transType(e) }
func transIdent(i *ast.Ident) ir.Expr       { return (&translator{}).transIdent(i) }
func transExpr(e ast.Expr) (ir.Expr, error) { return (&translator{}).transExpr(e) }
func transAssign(s *ast.AssignStmt) (*ir.Assign, error) {
	return (&translator{}).transAssign(s)
}
func transTypeAssert(e *ast.TypeAssertExpr) (*ir.TypeAssert, error) {
	return (&translator{}).transTypeAssert(e)
}
func transTypeSwitch(s *ast.TypeSwitchStmt) (*ir.TypeSwitch, error) {
	return (&translator{}).transTypeSwitch(s)
}

func lastSlash(s string) int {
	for i := len(s) - 1; i >= 0; i-- {
		if s[i] == '/' {
			return i
		}
	}
	return -1
}

// stdlibCall recognises `pkg.Member(args...)` where pkg is the local
// name of a wave-1 stdlib import, and lowers it to an *ir.Call whose
// Fun is the Selector `pkg.Member`. The call's result types are
// resolved from *types.Info so the emitter can type `:=` targets
// (`words := strings.Fields(s)`, `data, err := os.ReadFile(p)`).
// ok=false for any other call shape.
func (tr *translator) stdlibCall(c *ast.CallExpr) (*ir.Call, bool, error) {
	sel, ok := c.Fun.(*ast.SelectorExpr)
	if !ok {
		return nil, false, nil
	}
	id, ok := sel.X.(*ast.Ident)
	if !ok {
		return nil, false, nil
	}
	path, ok := tr.imports[id.Name]
	if !ok {
		return nil, false, nil
	}
	if _, ok := ir.StdlibPackages[path]; !ok {
		return nil, false, nil
	}
	args, err := tr.transExprList(c.Args)
	if err != nil {
		return nil, false, err
	}
	// Phase 7: `http.ListenAndServe(addr, nil)` — the nil handler
	// means "the default mux", which the Ada port serves implicitly,
	// so drop the argument.
	if path == "net/http" && sel.Sel.Name == "ListenAndServe" &&
		len(args) == 2 {
		if lit, ok := args[1].(*ir.Lit); ok && lit.Kind == ir.LitNil {
			args = args[:1]
		}
	}
	// Phase 7: `json.Unmarshal(data, &v)` — the Go pointer-to-target
	// becomes the Ada out-parameter directly, so drop the `&` and pass
	// the operand itself; the emitter appends it as an out-arg.
	if path == "encoding/json" && sel.Sel.Name == "Unmarshal" &&
		len(args) == 2 {
		if u, ok := args[1].(*ir.UnaryOp); ok && u.Op == "&" {
			args[1] = u.X
		}
	}
	call := &ir.Call{
		Fun:  &ir.Selector{X: &ir.Ident{Name: id.Name}, Sel: sel.Sel.Name},
		Args: args,
	}
	if tr.info != nil {
		call.ResultTypes = tr.goTypesToIR(tr.info.TypeOf(c))
	}
	if call.ResultTypes == nil {
		// Corpus fixtures translate without *types.Info (parser only);
		// fall back to the known wave-1 signatures so goldens still
		// pin the result types. The real driver always has types.Info.
		call.ResultTypes = fallbackResultTypes[path+"."+sel.Sel.Name]
	}
	return call, true, nil
}

// fallbackResultTypes pins the result types of the wave-1 stdlib
// members the corpus fixtures call, for translation without
// *types.Info. The driver path (packages.Load + NeedTypesInfo) always
// resolves these from go/types instead.
var fallbackResultTypes = map[string][]ir.Type{
	"os.ReadFile": {
		&ir.SliceType{Elem: &ir.ByteType{}},
		&ir.ErrorType{},
	},
	"strings.Fields":    {&ir.SliceType{Elem: &ir.StringType{}}},
	"strings.TrimSpace": {&ir.StringType{}},
	"encoding/json.Marshal": {
		&ir.SliceType{Elem: &ir.ByteType{}},
		&ir.ErrorType{},
	},
	"encoding/json.Unmarshal": {&ir.ErrorType{}},
	"net/http.ListenAndServe": {&ir.ErrorType{}},
	"net/http.Get": {
		&ir.PointerType{Elem: &ir.NamedType{Name: "Response"}},
		&ir.ErrorType{},
	},
	"net/http.Post": {
		&ir.PointerType{Elem: &ir.NamedType{Name: "Response"}},
		&ir.ErrorType{},
	},
}

// goTypesToIR converts a go/types type to the IR type(s) it denotes.
// Multi-result calls arrive as a *types.Tuple and expand to one IR
// type per result. Unrecognised shapes yield a nil entry so callers
// can fail loudly rather than emit a mis-typed declaration.
func (tr *translator) goTypesToIR(t types.Type) []ir.Type {
	if t == nil {
		return nil
	}
	if tup, ok := t.(*types.Tuple); ok {
		out := make([]ir.Type, 0, tup.Len())
		for i := 0; i < tup.Len(); i++ {
			out = append(out, tr.goOneToIR(tup.At(i).Type()))
		}
		return out
	}
	return []ir.Type{tr.goOneToIR(t)}
}

func (tr *translator) goOneToIR(t types.Type) ir.Type {
	switch t := t.(type) {
	case *types.Basic:
		switch t.Kind() {
		case types.Int:
			return &ir.IntType{}
		case types.String:
			return &ir.StringType{}
		case types.Bool:
			return &ir.BoolType{}
		case types.Float64:
			return &ir.Float64Type{}
		case types.Byte: // types.Uint8 == types.Byte (alias)
			return &ir.ByteType{}
		}
	case *types.Slice:
		if elem := tr.goOneToIR(t.Elem()); elem != nil {
			return &ir.SliceType{Elem: elem}
		}
	case *types.Interface:
		if t.NumMethods() == 1 && t.Method(0).Name() == "Error" {
			return &ir.ErrorType{}
		}
	case *types.Chan:
		if elem := tr.goOneToIR(t.Elem()); elem != nil {
			return &ir.ChanType{Elem: elem}
		}
	case *types.Pointer:
		// Phase 7: *http.Response / *http.Request arrive here from
		// call result types; carry the pointee.
		if elem := tr.goOneToIR(t.Elem()); elem != nil {
			return &ir.PointerType{Elem: elem}
		}
	case *types.Named:
		// The predeclared `error` arrives as a *types.Named whose
		// underlying is the one-method interface.
		if t.Obj().Name() == "error" {
			return &ir.ErrorType{}
		}
		// Any other named type (sync.Mutex, time.Time, time.Duration,
		// or a user type): carry the name; the emitter resolves it
		// against the file's declarations / stdlib imports.
		return &ir.NamedType{Name: t.Obj().Name()}
	}
	return nil
}
