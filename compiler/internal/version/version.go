// Package version exposes the GADA compiler's version string.
//
// The version string is split out of cmd/gada so future build-stamping
// (git describe, ldflags -X, etc.) has exactly one place to land.
package version

// Version is the semantic-version core of the GADA compiler.
//
// Phase 0 ships 0.0.0-dev as a deliberate placeholder; the first
// tagged release will replace it during Phase 11 cut.
const Version = "0.0.0-dev"

// Phase is the human-readable bootstrap stage label appended to the
// version string. It exists so `gada --version` output tells a reader
// at a glance which roadmap phase produced the binary.
const Phase = "phase 0 bootstrap"

// Describe returns the full one-line version string printed by
// `gada --version`. The exact format is part of the Phase 0
// verification contract — do not change it without updating the
// matching roadmap item and its verify command.
func Describe() string {
	return "gada " + Version + " (" + Phase + ")"
}
