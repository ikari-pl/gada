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

func main() {
	p := Point{X: 1, Y: 2}
	q := Point{3, 4}
	fmt.Println(p.X, p.Y)
	fmt.Println(q.X, q.Y)
}
