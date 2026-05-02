package p

func f(m map[int]int) int {
	total := 0
	for k, v := range m {
		total = total + k + v
	}
	return total
}
