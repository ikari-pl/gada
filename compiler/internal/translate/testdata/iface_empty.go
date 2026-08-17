package p

// An empty interface coexisting with a struct (Phase 4 item 5b). Blank
// satisfies Any vacuously — every Go type does — but must NOT derive it:
// a method-less interface carries no operation to dispatch, so deriving
// it would only flip Blank from an untagged record (5a-i) to a tagged
// type. Blank stays `is record …`; Any still emits as a bare interface,
// and the reflect registry still records the (Blank, Any) satisfaction.
type Any interface{}

type Blank struct {
	N int
}
