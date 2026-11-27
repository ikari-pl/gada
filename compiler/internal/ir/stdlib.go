package ir

// StdlibPackages maps a Go standard-library import path to the Ada
// package that ports it (Phase 5, stdlib wave 1). "fmt" is deliberately
// absent: it keeps the Phase 1 Gada.Core.IO special case until
// Gada.Std.Fmt supersedes it. The map lives in ir (not emit) so both
// the translator (which needs to recognise stdlib-qualified calls in
// expression position) and the emitter (which maps imports to `with`
// clauses) share one source of truth. StdlibWave1 is the sorted path
// list, used for the unknown-import error message.
var StdlibPackages = map[string]string{
	"errors":        "Gada.Std.Errors",
	"strings":       "Gada.Std.Strings",
	"strconv":       "Gada.Std.Strconv",
	"bytes":         "Gada.Std.Bytes",
	"io":            "Gada.Std.IO",
	"bufio":         "Gada.Std.Bufio",
	"os":            "Gada.Std.OS",
	"sync":          "Gada.Std.Sync",
	"time":          "Gada.Std.Time",
	"runtime":       "Gada.Std.Runtime",
	"net":           "Gada.Std.Net",
	"encoding/json": "Gada.Std.Json",
	"net/http":      "Gada.Std.Http",
	"hash/crc32":    "Gada.Std.Hash.Crc32",
	"hash/crc64":    "Gada.Std.Hash.Crc64",
	"hash/fnv":      "Gada.Std.Hash.Fnv",
	"hash/adler32":  "Gada.Std.Hash.Adler32",
}
