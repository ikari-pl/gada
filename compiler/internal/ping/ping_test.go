package ping

import "testing"

func TestPing(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name string
		want string
	}{
		{name: "returns pong", want: "pong"},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := Ping(); got != tc.want {
				t.Fatalf("Ping() = %q, want %q", got, tc.want)
			}
		})
	}
}
