package p

func f(m map[string]int) int {
	total := 0
	for k, v := range m {
		_ = k
		total = total + v
	}
	return total
}
