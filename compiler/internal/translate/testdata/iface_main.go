package main

import "fmt"

// A `package main` program with an interface, a satisfying struct, and a
// value-receiver method (Phase 4 item 5c). Exercises emitMainProcedure's
// overriding-method path: the interface, the tagged record deriving it,
// the overriding spec, and the overriding body all nest inside
// `procedure Main is … begin … end Main;`. main only constructs the
// value and prints a field — a method *call* (`g.Value()`) is item 5d.
type Meter interface {
	Value() int
}

type Gauge struct {
	Reading int
}

func (g Gauge) Value() int {
	return g.Reading
}

func main() {
	g := Gauge{Reading: 7}
	fmt.Println(g.Reading)
}
