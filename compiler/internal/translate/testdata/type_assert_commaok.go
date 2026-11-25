package p

// Comma-ok type assertion (Phase 4 item 6b). check takes a Speaker
// (class-wide `Speaker'Class`) and asserts it holds a Dog with
// `d, ok := s.(Dog)`: this lowers to the membership test
// `OK := S in Dog'Class` plus a guarded view conversion `D := Dog (S)`,
// with D declared at Dog's zero value so a failed assertion leaves the
// zero (Go semantics). On ok, check returns the Dog's Legs; otherwise 0.
type Speaker interface {
	Speak()
}

type Dog struct {
	Legs int
}

func (d Dog) Speak() {}

func check(s Speaker) int {
	d, ok := s.(Dog)
	if ok {
		return d.Legs
	}
	return 0
}
