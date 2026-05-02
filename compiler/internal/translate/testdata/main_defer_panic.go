package main

import "fmt"

func rescue() {
	if recover() != 0 {
		fmt.Println("rescued")
	}
}

func main() {
	defer rescue()
	panic(42)
}
