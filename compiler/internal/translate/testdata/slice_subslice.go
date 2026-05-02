package p

func mid(s []int) []int {
	return s[1:3]
}

func tail(s []int) []int {
	return s[1:]
}

func head_n(s []int, n int) []int {
	return s[:n]
}

func full(s []int) []int {
	return s[:]
}
