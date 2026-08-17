package main

import "fmt"

// Struct zero-value and partial literals (Phase 4 item 5a-iii): fields
// omitted from a composite literal fill with each field's Go zero value,
// so the Ada record aggregate is complete (Ada requires a value for
// every component). A zero-value `Config{}` fills every field; a partial
// `Config{Width: 80}` fills only the unmentioned ones — each in the
// record's declared order, regardless of literal order.
//
// All fields are int: a struct with a `string` field is deferred because
// an unconstrained `String` record component is not valid Ada yet (a
// 5a-i record-emission concern, tracked separately). The scalar zero
// *spellings* for string/bool/float are covered by emit unit tests.
type Config struct {
	Width, Height, Depth int
}

func main() {
	zero := Config{}
	partial := Config{Width: 80}
	fmt.Println(zero.Width, zero.Height, zero.Depth)
	fmt.Println(partial.Width, partial.Height, partial.Depth)
}
