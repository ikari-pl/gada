package p

// Multi-interface derivation (Phase 4 item 5b-ii). Buffer satisfies both
// Reader and Writer, so its record derives both — `is new Reader and
// Writer with record …` — and declares an `overriding` spec for each
// method it implements. Close is declared by both interfaces but
// overridden once (dedup by name). Nop is a fieldless struct that still
// satisfies Reader, exercising `is new Reader with null record;`.
type Reader interface {
	Read() int
	Close()
}

type Writer interface {
	Write(n int)
	Close()
}

type Buffer struct {
	data int
}

func (b Buffer) Read() int   { return b.data }
func (b Buffer) Write(n int) {}
func (b Buffer) Close()      {}

type Nop struct{}

func (n Nop) Read() int { return 0 }
func (n Nop) Close()    {}
