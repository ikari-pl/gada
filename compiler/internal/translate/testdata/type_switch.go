package p

// Type switch (Phase 4 item 6c). describe takes a Speaker (class-wide
// `Speaker'Class`) and switches on its dynamic type with
// `switch d := s.(type)`: this lowers to an Ada if/elsif/else chain of
// membership tests (`if S in Dog'Class then … elsif S in Cat'Class then
// … else …`), with d viewed as each case's type inside its arm
// (`declare D : Dog := Dog (S); begin … end;`). Dog and Cat are tagged
// types deriving Speaker (5b/5c).
type Speaker interface {
	Speak()
}

type Dog struct {
	Legs int
}

func (d Dog) Speak() {}

type Cat struct {
	Lives int
}

func (c Cat) Speak() {}

func describe(s Speaker) int {
	switch d := s.(type) {
	case Dog:
		return d.Legs
	case Cat:
		return d.Lives
	default:
		return 0
	}
}
