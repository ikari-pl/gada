package p

// Interface method dispatch (Phase 4 item 5d). describe takes a value of
// interface type Speaker — held as the class-wide `Speaker'Class` — and
// calls its method. `s.Speak()` lowers to the Ada prefixed-view call
// `S.Speak`, which on a class-wide operand dispatches at run time by the
// value's tag (RM 3.9.2) — the Hybrid model's native vtable, no
// hand-rolled itable. The concrete types that satisfy Speaker and their
// overriding bodies ride items 5b/5c; this fixture is about the call.
type Speaker interface {
	Speak()
}

func describe(s Speaker) {
	s.Speak()
}
