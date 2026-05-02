package p

func f() int {
	m := map[int]int{1: 2, 3: 4}
	e := map[int]int{}
	return len(m) + len(e)
}
