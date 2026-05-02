package main

import "fmt"

func main() {
	defer fmt.Println("end")
	fmt.Println("hello")
}
