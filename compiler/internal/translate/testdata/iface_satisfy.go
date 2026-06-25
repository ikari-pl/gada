package p

// An interface and a concrete type that satisfies it (Phase 4 item
// 4c-ii). Point has String() string, so it structurally satisfies
// Stringer: the compiler emits Add_Method on both descriptors and a
// Gada.Reflect.Interfaces.Register call for the (Point, Stringer) pair.
// The method body itself is reflect-metadata-only for now — its dispatch
// emission is item 5 — so it does not appear as an Ada subprogram.
type Stringer interface {
	String() string
}

type Point struct {
	X, Y int
}

func (pt Point) String() string {
	return "pt"
}
