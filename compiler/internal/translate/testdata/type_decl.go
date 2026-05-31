package p

// A named scalar (defined type over a basic type) and a struct type
// with a grouped multi-name field. Both become *ir.TypeDecl; the
// reflect layer emits one Register_Type per defined type.
type Celsius float64

type Point struct {
	X, Y int
}
