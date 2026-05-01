// Package ping is a trivial liveness sentinel used to validate the
// Go test toolchain (Phase 0). It deliberately has no behaviour beyond
// returning a constant string so its test can do nothing but exercise
// `go test -race` against the compiler module.
//
// Once Phase 1 starts emitting real internal packages this file may
// be deleted; the only contract here is the Phase 0 verify command
// in roadmap/00-foundation.md.
package ping

// Ping returns the constant "pong". It exists solely so the test
// toolchain has at least one exported symbol to call.
func Ping() string {
	return "pong"
}
