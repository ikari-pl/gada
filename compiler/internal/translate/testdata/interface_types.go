package p

// Interface type emission (Phase 4 item 5b-i): each interface becomes an
// Ada interface type with one abstract operation per method — a function
// for a single-result method, a procedure for a result-less one, with
// the interface as the controlling `Self` parameter. Exercises a
// parameterless function, a function and a procedure with parameters,
// and the empty interface (a bare `is interface;` with no operations).
type Stringer interface {
	String() string
}

type Shape interface {
	Area() int
	Scale(factor int)
	SetName(name string) bool
}

type Any interface{}
