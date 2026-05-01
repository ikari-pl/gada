package version

import (
	"strings"
	"testing"
)

// TestDescribe pins the `gada --version` output shape: the prefix, the
// embedded Version constant, and the embedded Phase label all appear in
// the returned string. The exact format is part of the Phase 0 verify
// contract (see roadmap/00-foundation.md "Initialize Go module").
func TestDescribe(t *testing.T) {
	got := Describe()

	if !strings.HasPrefix(got, "gada ") {
		t.Errorf("Describe() = %q; want prefix \"gada \"", got)
	}
	if !strings.Contains(got, Version) {
		t.Errorf("Describe() = %q; want it to contain Version %q", got, Version)
	}
	if !strings.Contains(got, Phase) {
		t.Errorf("Describe() = %q; want it to contain Phase %q", got, Phase)
	}
}
