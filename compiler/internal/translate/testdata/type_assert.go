package p

// Single-value type assertion (Phase 4 item 6a). check takes a Speaker
// (class-wide `Speaker'Class`) and asserts it holds a Dog: `s.(Dog)`
// lowers to the Ada view conversion `Dog (S)`, which checks the tag and
// raises on a mismatch (Go panics). The asserted concrete Dog is a
// tagged type deriving Speaker (5b/5c); this fixture adds the assertion.
type Speaker interface {
	Speak()
}

type Dog struct {
	Legs int
}

func (d Dog) Speak() {}

func check(s Speaker) int {
	d := s.(Dog)
	return d.Legs
}
