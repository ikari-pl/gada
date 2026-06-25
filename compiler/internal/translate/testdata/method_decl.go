package p

type Counter struct {
	N int
}

// A value-receiver method and a pointer-receiver method (Phase 4 item
// 4b). Each round-trips as an *ir.Function with a non-nil Receiver
// naming Counter; the pointer receiver sets Pointer. Bodies are kept
// trivial — 4b is about the receiver reaching the IR, not method-body
// emission (items 5 / 4c).
func (c Counter) Get() int {
	return 42
}

func (c *Counter) Inc() {
}

// A free function keeps a nil Receiver.
func Zero() int {
	return 0
}
