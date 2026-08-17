package main

import "fmt"

// Struct *values* (Phase 4 item 5a-ii): keyed and positional composite
// literals plus field access — the forms that let a struct-using program
// round-trip end to end. The record type declaration itself rides item
// 5a-i; here `Point{...}` lowers to a qualified Ada aggregate and `p.X`
// to the record component `P.X`.
type Point struct {
	X, Y int
}

// A single-field struct: a positional literal `Tick{7}` must lower to
// the *named* aggregate `Tick'(N => 7)`, because Ada parses a
// one-component positional aggregate `Tick'(7)` as a qualified
// expression (a type error), not a record aggregate.
type Tick struct {
	N int
}

func main() {
	p := Point{X: 1, Y: 2}
	q := Point{3, 4}
	t := Tick{7}
	fmt.Println(p.X, p.Y)
	fmt.Println(q.X, q.Y)
	fmt.Println(t.N)
}
