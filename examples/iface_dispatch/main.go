package main

import "fmt"

// iface_dispatch — Phase 4 exit example. Three concrete types (Dog, Cat,
// Robot) each implement two interfaces (Speaker, Mover). Calls through
// the interface-typed parameters dispatch at run time on the Ada tag
// (class-wide prefixed-view calls), and the transpiled package init
// registers every type's method list in Gada.Reflect (one Add_Method per
// method) plus the satisfaction edges (Gada.Reflect.Interfaces.Register)
// — the reflection-based method enumeration this phase delivers. A type
// switch over a Speaker exercises the item-6c lowering end to end.

type Speaker interface {
	Speak()
}

type Mover interface {
	Describe()
}

type Dog struct {
	Legs int
}

func (d Dog) Speak() { fmt.Println("woof") }

func (d Dog) Describe() { fmt.Println("dog with", d.Legs, "legs") }

type Cat struct {
	Lives int
}

func (c Cat) Speak() { fmt.Println("meow") }

func (c Cat) Describe() { fmt.Println("cat with", c.Lives, "lives") }

type Robot struct {
	Battery int
}

func (r Robot) Speak() { fmt.Println("beep") }

func (r Robot) Describe() { fmt.Println("robot at", r.Battery, "%") }

// announce calls through the Speaker interface: the argument's concrete
// type widens to the class-wide `Speaker'Class` at the call site and the
// call dispatches on the value's tag.
func announce(s Speaker) {
	s.Speak()
}

func report(m Mover) {
	m.Describe()
}

// kind switches on the dynamic type of a Speaker; inside each arm k is
// viewed as the case's type.
func kind(s Speaker) {
	switch k := s.(type) {
	case Dog:
		fmt.Println("it's a dog with", k.Legs, "legs")
	case Cat:
		fmt.Println("it's a cat with", k.Lives, "lives")
	case Robot:
		fmt.Println("it's a robot at", k.Battery, "%")
	default:
		fmt.Println("it's something else")
	}
}

func main() {
	d := Dog{Legs: 4}
	c := Cat{Lives: 9}
	r := Robot{Battery: 80}

	announce(d)
	announce(c)
	announce(r)

	report(d)
	report(c)
	report(r)

	kind(d)
	kind(c)
	kind(r)
}
