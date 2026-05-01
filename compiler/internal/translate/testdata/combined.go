package main

import "fmt"

func demo(n int) int {
	x := 0
	for i := 0; i < n; i = i + 1 {
		x = x + (i * 2)
	}
	if x > 100 {
		fmt.Println("big")
		return -x
	} else if x < -10 {
		fmt.Println("small")
		return x
	}
	fmt.Println("ok")
	return x
}
