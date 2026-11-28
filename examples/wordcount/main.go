// wordcount is the Phase 5 cross-package integration example: it
// reads a file (os), splits it into words (strings), sorts them with
// a bubble sort over a []string, groups equal neighbours, and prints
// "word count" lines (fmt). It exercises the whole stdlib wave-1
// surface end-to-end through the transpiler: the 2-LHS (T, error)
// out-call, string([]byte), []string index/assign/len, and nil
// comparison. Loops are kept in the trivial `for v := a; v < b;
// v = v + 1` shape the Phase 1 emitter supports.
package main

import (
	"fmt"
	"os"
	"strings"
)

func main() {
	data, err := os.ReadFile("examples/wordcount/input.txt")
	text := string(data)
	words := strings.Fields(text)
	n := len(words)
	tmp := ""
	c := 0
	if err != nil {
		fmt.Println("cannot read input")
		return
	}
	// Bubble sort.
	for i := 0; i < n; i = i + 1 {
		for k := 0; k < n-1; k = k + 1 {
			if words[k] > words[k+1] {
				tmp = words[k]
				words[k] = words[k+1]
				words[k+1] = tmp
			}
		}
	}
	// For each distinct word (sorted, so runs are adjacent), count
	// and print. `i == 0` guards words[i-1] — Ada `or` does not
	// short-circuit, so the guard is a nested if, not `||`.
	for i := 0; i < n; i = i + 1 {
		c = 0
		for k := 0; k < n; k = k + 1 {
			if words[k] == words[i] {
				c = c + 1
			}
		}
		if i == 0 {
			fmt.Println(words[i], c)
		} else {
			if words[i] != words[i-1] {
				fmt.Println(words[i], c)
			}
		}
	}
}
