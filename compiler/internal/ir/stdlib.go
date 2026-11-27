package ir

import "sort"

// StdlibPackages maps a Go standard-library import path to the Ada
// package that ports it (Phase 5, stdlib wave 1). "fmt" is deliberately
// absent: it keeps the Phase 1 Gada.Core.IO special case until
// Gada.Std.Fmt supersedes it. The map lives in ir (not emit) so both
// the translator (which needs to recognise stdlib-qualified calls in
// expression position) and the emitter (which maps imports to `with`
// clauses) share one source of truth.
var StdlibPackages = map[string]string{
	"errors":  "Gada.Std.Errors",
	"strings": "Gada.Std.Strings",
	"strconv": "Gada.Std.Strconv",
	"bytes":   "Gada.Std.Bytes",
	"io":      "Gada.Std.IO",
	"bufio":   "Gada.Std.Bufio",
	"os":      "Gada.Std.OS",
}

// StdlibWave1 is StdlibPackages' keys, sorted — used in the emitter's
// unknown-import error message.
var StdlibWave1 = func() []string {
	out := make([]string, 0, len(StdlibPackages))
	for k := range StdlibPackages {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}()
