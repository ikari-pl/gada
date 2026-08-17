package main

import "fmt"

// Struct zero-value and partial literals (Phase 4 item 5a-iii): fields
// omitted from a composite literal fill with each field's Go zero value,
// so the Ada record aggregate is complete (Ada requires a value for
// every component). A zero-value `Config{}` fills every field; a partial
// `Config{Width: 80}` fills only the unmentioned ones — each in the
// record's declared order, regardless of literal order.
//
// Fields are int, bool and float — the scalar types that lower to valid
// Ada record components with a synthesisable Go zero. A `string` field
// is deferred: an unconstrained `String` record component is not valid
// Ada yet, so emit rejects a string struct field at its declaration
// (its zero *spelling* is not needed until a bounded string component
// lands). Only the int fields are printed — Gada.Core.IO.Print has no
// Boolean/Long_Float overload yet — but Verbose and Ratio still exercise
// the bool/float record components and their zero fills.
type Config struct {
	Width, Height, Depth int
	Verbose              bool
	Ratio                float64
}

func main() {
	zero := Config{}
	partial := Config{Width: 80}
	fmt.Println(zero.Width, zero.Height, zero.Depth)
	fmt.Println(partial.Width, partial.Height, partial.Depth)
}
