package p

import (
	"os"
	"strings"
)

// Phase 5 wave 1: stdlib package calls in expression position
// (`words := strings.Fields(text)`), the 2-LHS (T, error) out-call
// shape (`data, err := os.ReadFile(path)`), the string([]byte)
// conversion, []string index/assign/len, and the nil comparison.
func f(path string) {
	data, err := os.ReadFile(path)
	text := string(data)
	words := strings.Fields(text)
	n := len(words)
	w := words[0]
	w2 := strings.TrimSpace(w)
	words[0] = w2
	if err != nil {
		panic("read failed")
	}
	if n > 0 && w2 != "" {
		panic("nonempty")
	}
}
