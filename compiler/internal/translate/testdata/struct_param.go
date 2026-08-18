package p

// A struct-typed parameter (Phase 4 item 5d). A NamedType that resolves
// to a struct renders the plain record type `Point` (passed by copy),
// not a class-wide view — no dispatch is involved. Field access on the
// parameter is an ordinary record-component read, `p.X` → `P.X`; this is
// the struct arm of typeName's NamedType resolution, exercised end to
// end. (A method *call* on a struct value is a separate, later item.)
type Point struct {
	X, Y int
}

func area(p Point) int {
	return p.X
}
