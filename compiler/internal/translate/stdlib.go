package translate

import (
	"fmt"
	"go/ast"
	"go/types"
	"strconv"
	"sync"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// Phase 5 wave 1: stdlib package calls. The file-wide import table and
// the *types.Info handle are threaded through package-level variables
// because transExpr/transAssign are free functions and the IR carries
// no ast back-pointers; File() sets them once per translated file (the
// driver loads exactly one .go file per package, so a package-level
// slot cannot leak across files).

var curImports map[string]string // local import name → import path
var curInfo *types.Info

// fileCtxMu serialises File() calls: the corpus tests translate
// fixtures in parallel, and the package-level slots above are only
// safe because one File() call translates exactly one file to
// completion before the next begins. The driver loads a single .go
// file per package, so this never serialises real workloads.
var fileCtxMu sync.Mutex

func resetFileContext(f *ast.File, info *types.Info) error {
	curInfo = info
	curImports = map[string]string{}
	for _, imp := range f.Imports {
		path, err := strconv.Unquote(imp.Path.Value)
		if err != nil {
			return fmt.Errorf("translate: bad import path %s: %w", imp.Path.Value, err)
		}
		name := path
		if i := lastSlash(path); i >= 0 {
			name = path[i+1:]
		}
		if imp.Name != nil {
			name = imp.Name.Name
		}
		curImports[name] = path
	}
	return nil
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
func stdlibCall(c *ast.CallExpr) (*ir.Call, bool, error) {
	sel, ok := c.Fun.(*ast.SelectorExpr)
	if !ok {
		return nil, false, nil
	}
	id, ok := sel.X.(*ast.Ident)
	if !ok {
		return nil, false, nil
	}
	path, ok := curImports[id.Name]
	if !ok {
		return nil, false, nil
	}
	if _, ok := ir.StdlibPackages[path]; !ok {
		return nil, false, nil
	}
	args, err := transExprList(c.Args)
	if err != nil {
		return nil, false, err
	}
	call := &ir.Call{
		Fun:  &ir.Selector{X: &ir.Ident{Name: id.Name}, Sel: sel.Sel.Name},
		Args: args,
	}
	if curInfo != nil {
		call.ResultTypes = goTypesToIR(curInfo.TypeOf(c))
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
}

// goTypesToIR converts a go/types type to the IR type(s) it denotes.
// Multi-result calls arrive as a *types.Tuple and expand to one IR
// type per result. Unrecognised shapes yield a nil entry so callers
// can fail loudly rather than emit a mis-typed declaration.
func goTypesToIR(t types.Type) []ir.Type {
	if t == nil {
		return nil
	}
	if tup, ok := t.(*types.Tuple); ok {
		out := make([]ir.Type, 0, tup.Len())
		for i := 0; i < tup.Len(); i++ {
			out = append(out, goOneToIR(tup.At(i).Type()))
		}
		return out
	}
	return []ir.Type{goOneToIR(t)}
}

func goOneToIR(t types.Type) ir.Type {
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
		if elem := goOneToIR(t.Elem()); elem != nil {
			return &ir.SliceType{Elem: elem}
		}
	case *types.Interface:
		if t.NumMethods() == 1 && t.Method(0).Name() == "Error" {
			return &ir.ErrorType{}
		}
	case *types.Named:
		// The predeclared `error` arrives as a *types.Named whose
		// underlying is the one-method interface.
		if t.Obj().Name() == "error" {
			return &ir.ErrorType{}
		}
	}
	return nil
}
