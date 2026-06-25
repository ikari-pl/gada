package main

// A struct type in a `package main` program (Phase 4 item 5a-i): the
// record type is emitted in the Main procedure's declarative part, the
// reflect metadata in its prologue. main does nothing with it yet —
// struct values (literals, field access) are item 5a-ii.
type Point struct {
	X, Y int
}

// An empty struct emits as `type Empty is null record;` (a fieldless
// `record … end record` is illegal Ada).
type Empty struct{}

func main() {
}
