package p

// Interface types (Phase 4 item 4a). Each becomes a *ir.TypeDecl whose
// underlying is an *ir.InterfaceType: a parameterless string method, a
// method set with named params and a multi-value result, and the empty
// interface{} (Go's any, an InterfaceType with no methods).
type Stringer interface {
	String() string
}

type ReadWriter interface {
	Read(p []int) (int, bool)
	Write(n int)
}

type Any interface{}
