package main

import "fmt"

// printRescued is the deferred call from handleOnce. recover() returns
// the panic payload (here: 42) so the != 0 check fires and the
// program reports that the recovery worked.
//
// Declared before handleOnce so the Ada-side declaration order
// satisfies "declare before use" — Phase 2 emit does not yet hoist
// forward declarations.
func printRescued() {
	if recover() != 0 {
		fmt.Println("recovered")
	}
}

// handleOnce demonstrates Go's defer + panic + recover trio:
//   1. Set up a deferred call that owns recovery.
//   2. Trigger a panic; runtime unwinds toward the deferred call.
//   3. The deferred call's `recover()` returns the panic payload,
//      stops the unwind, and the panicking function returns
//      normally so its caller never sees the exception.
func handleOnce() {
	defer printRescued()
	panic(42)
}

func main() {
	// All `:=` declarations are hoisted to the head of the body so
	// they land in Ada's declarative region. After this block only
	// statements (assigns, ifs, calls, range loops) follow.
	nums := []int{10, 20, 30}
	counts := map[int]int{1: 10, 2: 20}
	total := 0

	defer fmt.Println("end")

	// Slice: literal + length.
	if len(nums) == 3 {
		fmt.Println("slice ok")
	}

	// Map: insert + delete.
	counts[3] = 30
	delete(counts, 1)

	// Map: range iteration. After the delete the surviving entries
	// are (2 => 20) and (3 => 30). Sum of keys + values = 55.
	for k, v := range counts {
		total = total + k + v
	}
	if total == 55 {
		fmt.Println("range ok")
	}

	// Defer + panic + recover, exercised inside a helper.
	handleOnce()

	fmt.Println("complete")
}
