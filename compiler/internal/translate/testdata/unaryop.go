package p

func flip(x int, ok bool) int {
	-x
	if !ok {
		return -x
	}
	return x
}

func always() bool {
	return true
}
