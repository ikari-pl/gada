package p

import "strings"

// Stdlib import mapping (Phase 5): `import "strings"` emits
// `with Gada.Std.Strings;` and the qualified statement call
// `strings.ToUpper(s)` lowers to `Gada.Std.Strings.To_Upper (S);`.
// (Call results in expression position — `x := strings.ToUpper(s)` —
// ride a later item; the IR's Call node is statement-only today.)
func f(s string) {
	strings.ToUpper(s)
}
