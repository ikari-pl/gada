package emit

import (
	"fmt"

	"github.com/gada-lang/gada/compiler/internal/ir"
)

// Phase 7 item 2b — compiler-specialized struct JSON marshalers.
//
// Go's encoding/json is reflection-heavy; a transpiler can do better.
// When `json.Marshal(v)` / `json.Unmarshal(data, &v)` names a struct
// type declared in the same file, the emitter rewrites the call to a
// generated `Json_Marshal_T` / `Json_Unmarshal_T` procedure (emitted
// into the unit that declares T) and the runtime Gada.Std.Json supplies
// the text primitives (Escape, Encode_*, Parse_Object). Scalar-typed
// operands keep the Gada.Std.Json.Marshal/Unmarshal overloads from
// item 2a. v1 supports struct fields of kind int / bool / float only
// (string record components are already rejected at struct-decl time);
// anything else fails loudly here.

// jsonStructCall inspects c for a json.Marshal / json.Unmarshal call
// whose value argument is a local struct value. Returns the Go type
// name and whether it is Marshal (true) or Unmarshal (false).
func (e *emitter) jsonStructCall(c *ir.Call) (tname string, marshal bool, ok bool) {
	sel, isSel := c.Fun.(*ir.Selector)
	if !isSel {
		return "", false, false
	}
	id, isID := sel.X.(*ir.Ident)
	if !isID || e.stdlibImports[id.Name] != "Gada.Std.Json" {
		return "", false, false
	}
	var arg ir.Expr
	switch sel.Sel {
	case "Marshal":
		if len(c.Args) != 1 {
			return "", false, false
		}
		arg = c.Args[0]
		marshal = true
	case "Unmarshal":
		if len(c.Args) != 2 {
			return "", false, false
		}
		arg = c.Args[1]
	default:
		return "", false, false
	}
	// The operand must be a plain identifier whose declared type is a
	// struct declared in this file (or a struct literal naming one).
	switch a := arg.(type) {
	case *ir.Ident:
		nt, isNT := e.localTypes[a.Name].(*ir.NamedType)
		if !isNT {
			return "", false, false
		}
		if _, isStruct := e.structByName[nt.Name]; isStruct {
			return nt.Name, marshal, true
		}
	case *ir.StructLit:
		if _, isStruct := e.structByName[a.TypeName]; isStruct {
			return a.TypeName, marshal, true
		}
	}
	return "", false, false
}

// rewriteJsonStructCall rewrites one call in place (Fun becomes the
// generated procedure name) and records the type for marshaler
// generation.
func (e *emitter) rewriteJSONStructCall(c *ir.Call) {
	tname, marshal, ok := e.jsonStructCall(c)
	if !ok {
		return
	}
	verb := "Unmarshal"
	if marshal {
		verb = "Marshal"
	}
	c.Fun = &ir.Ident{Name: "Json_" + verb + "_" + tname}
	if !e.jsonStructSeen[tname] {
		e.jsonStructSeen[tname] = true
		e.jsonStructOrder = append(e.jsonStructOrder, tname)
	}
	e.needsUnbounded = true
}

// rewriteJsonStructCalls walks fn's statements rewriting struct-typed
// json.Marshal/Unmarshal calls. Must run after populateLocals(fn) so
// localTypes is populated for the function.
func (e *emitter) rewriteJSONStructCalls(fn *ir.Function) {
	e.walkJSONStmts(fn.Body)
}

func (e *emitter) walkJSONStmts(stmts []ir.Stmt) {
	for _, s := range stmts {
		e.walkJSONStmt(s)
	}
}

func (e *emitter) walkJSONStmt(s ir.Stmt) {
	switch x := s.(type) {
	case *ir.Assign:
		for _, r := range x.RHS {
			e.walkJSONExpr(r)
		}
	case *ir.ExprStmt:
		e.walkJSONExpr(x.X)
	case *ir.If:
		e.walkJSONExpr(x.Cond)
		e.walkJSONStmts(x.Then)
		e.walkJSONStmts(x.Else)
	case *ir.For:
		if x.Init != nil {
			e.walkJSONStmt(x.Init)
		}
		e.walkJSONExpr(x.Cond)
		if x.Post != nil {
			e.walkJSONStmt(x.Post)
		}
		e.walkJSONStmts(x.Body)
	case *ir.RangeStmt:
		e.walkJSONExpr(x.X)
		e.walkJSONStmts(x.Body)
	case *ir.Return:
		for _, r := range x.Results {
			e.walkJSONExpr(r)
		}
	case *ir.DeferStmt:
		e.walkJSONStmt(x.Call)
	case *ir.GoStmt:
		e.walkJSONStmt(x.Call)
	}
}

func (e *emitter) walkJSONExpr(x ir.Expr) {
	switch v := x.(type) {
	case *ir.Call:
		e.rewriteJSONStructCall(v)
		e.walkJSONExpr(v.Fun)
		for _, a := range v.Args {
			e.walkJSONExpr(a)
		}
	case *ir.BinOp:
		e.walkJSONExpr(v.X)
		e.walkJSONExpr(v.Y)
	case *ir.UnaryOp:
		e.walkJSONExpr(v.X)
	case *ir.Selector:
		e.walkJSONExpr(v.X)
	case *ir.IndexExpr:
		e.walkJSONExpr(v.X)
		e.walkJSONExpr(v.Index)
	case *ir.SliceExpr:
		e.walkJSONExpr(v.X)
		e.walkJSONExpr(v.Low)
		e.walkJSONExpr(v.High)
	case *ir.StructLit:
		for _, f := range v.Fields {
			e.walkJSONExpr(f.Value)
		}
	case *ir.SliceLit:
		for _, el := range v.Elems {
			e.walkJSONExpr(el)
		}
	case *ir.MapLit:
		for _, en := range v.Entries {
			e.walkJSONExpr(en.Key)
			e.walkJSONExpr(en.Value)
		}
	case *ir.TypeAssert:
		e.walkJSONExpr(v.X)
	case *ir.ChanRecv:
		e.walkJSONExpr(v.Chan)
	case *ir.MakeSlice:
		e.walkJSONExpr(v.Len)
	case *ir.MakeChan:
		e.walkJSONExpr(v.Capacity)
	}
}

// emitJSONMarshalers emits one Json_Marshal_T / Json_Unmarshal_T pair
// per collected struct type, into the current buffer (the unit that
// declares the type). Caller owns indent and separation.
func (e *emitter) emitJSONMarshalers() {
	for i, tname := range e.jsonStructOrder {
		if i > 0 {
			e.println("")
		}
		st := e.structByName[tname]
		name := adaIdent(tname)
		e.emitJSONMarshaler(name, st)
		e.println("")
		e.emitJSONUnmarshaler(name, st)
	}
}

// jsonFieldEncode returns the Ada expression encoding struct field V.F
// as JSON text (an Unbounded_String).
func (e *emitter) jsonFieldEncode(fieldName string, t ir.Type) (string, error) {
	f := "V." + adaIdent(fieldName)
	switch t.(type) {
	case *ir.IntType:
		return "Gada.Std.Json.Encode_Int (" + f + ")", nil
	case *ir.BoolType:
		return "Gada.Std.Json.Encode_Bool (" + f + ")", nil
	case *ir.Float64Type:
		return "Gada.Std.Json.Encode_Float (" + f + ")", nil
	}
	return "", fmt.Errorf("emit: json: struct field %q has unsupported type %T (v1: int/bool/float only)", fieldName, t)
}

func (e *emitter) emitJSONMarshaler(name string, st *ir.StructType) {
	e.println("procedure Json_Marshal_" + name)
	e.println("  (V : " + name + "; Data : out Gada.Std.Bytes.Byte_Slice;")
	e.println("   Err : out Gada.Std.Errors.Error_Access) is")
	e.println("   R : Ada.Strings.Unbounded.Unbounded_String;")
	e.println("begin")
	e.indent++
	e.println("Err := Gada.Std.Errors.No_Error;")
	e.println("Ada.Strings.Unbounded.Append (R, \"{\");")
	for i, f := range st.Fields {
		if i > 0 {
			e.println("Ada.Strings.Unbounded.Append (R, \",\");")
		}
		e.println("Ada.Strings.Unbounded.Append (R, '\"' & Gada.Std.Json.Escape (\"" +
			f.Name + "\") & '\"' & \":\");")
		enc, err := e.jsonFieldEncode(f.Name, f.Type)
		if err != nil {
			e.fail(err)
			return
		}
		e.println("Ada.Strings.Unbounded.Append (R, " + enc + ");")
	}
	e.println("Ada.Strings.Unbounded.Append (R, \"}\");")
	e.println("Data := Gada.Std.Bytes.To_Bytes")
	e.println("  (Ada.Strings.Unbounded.To_String (R));")
	e.indent--
	e.println("end Json_Marshal_" + name + ";")
}

// jsonFieldDecode emits the case arm assigning one object member to
// struct field V.F, kind-checked per the field type.
func (e *emitter) jsonFieldDecode(fieldName string, t ir.Type) []string {
	f := "V." + adaIdent(fieldName)
	msg := "json: field " + fieldName + " type mismatch"
	switch t.(type) {
	case *ir.IntType:
		return []string{
			"when Gada.Std.Json.K_Int =>",
			"   begin",
			"      " + f + " := Integer (Mem.Val.I);",
			"   exception",
			"      when Constraint_Error =>",
			"         Err := Gada.Std.Errors.New_K (\"json: field " + fieldName + " out of range\");",
			"   end;",
			"when Gada.Std.Json.K_Null =>",
			"   null;",
			"when others =>",
			"   Err := Gada.Std.Errors.New_K (\"" + msg + "\");",
		}
	case *ir.BoolType:
		return []string{
			"when Gada.Std.Json.K_Bool =>",
			"   " + f + " := Mem.Val.B;",
			"when Gada.Std.Json.K_Null =>",
			"   null;",
			"when others =>",
			"   Err := Gada.Std.Errors.New_K (\"" + msg + "\");",
		}
	case *ir.Float64Type:
		return []string{
			"when Gada.Std.Json.K_Int =>",
			"   " + f + " := Long_Float (Mem.Val.I);",
			"when Gada.Std.Json.K_Float =>",
			"   " + f + " := Mem.Val.F;",
			"when Gada.Std.Json.K_Null =>",
			"   null;",
			"when others =>",
			"   Err := Gada.Std.Errors.New_K (\"" + msg + "\");",
		}
	}
	e.fail(fmt.Errorf("emit: json: struct field %q has unsupported type %T (v1: int/bool/float only)", fieldName, t))
	return nil
}

func (e *emitter) emitJSONUnmarshaler(name string, st *ir.StructType) {
	e.println("procedure Json_Unmarshal_" + name)
	e.println("  (Data : Gada.Std.Bytes.Byte_Slice; V : in out " + name + ";")
	e.println("   Err : out Gada.Std.Errors.Error_Access) is")
	e.println("   M : Gada.Std.Json.Member_Vectors.Vector;")
	e.println("   OK : Boolean;")
	e.println("begin")
	e.indent++
	e.println("Err := Gada.Std.Errors.No_Error;")
	e.println("Gada.Std.Json.Parse_Object")
	e.println("  (Gada.Std.Bytes.To_String (Data), M, OK);")
	e.println("if not OK then")
	e.indent++
	e.println("Err := Gada.Std.Errors.New_K (\"json: invalid JSON object\");")
	e.println("return;")
	e.indent--
	e.println("end if;")
	e.println("for I in 1 .. Integer (Gada.Std.Json.Member_Vectors.Length (M)) loop")
	e.indent++
	e.println("declare")
	e.indent++
	e.println("Mem : constant Gada.Std.Json.Member :=")
	e.println("  Gada.Std.Json.Member_Vectors.Element (M, I);")
	e.indent--
	e.println("begin")
	e.indent++
	for i, f := range st.Fields {
		kw := "if"
		if i > 0 {
			kw = "elsif"
		}
		e.println(kw + " Ada.Strings.Unbounded.To_String (Mem.Key) = \"" +
			f.Name + "\" then")
		e.indent++
		e.println("case Mem.Val.Kind is")
		e.indent++
		arms := e.jsonFieldDecode(f.Name, f.Type)
		if arms == nil {
			return
		}
		for _, a := range arms {
			e.println(a)
		}
		e.indent--
		e.println("end case;")
		e.indent--
	}
	e.println("end if;")
	e.indent--
	e.println("end;")
	e.indent--
	e.println("end loop;")
	e.indent--
	e.println("end Json_Unmarshal_" + name + ";")
}
