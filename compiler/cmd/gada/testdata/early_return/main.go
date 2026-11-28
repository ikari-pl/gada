// early_return pins that a `return` inside main ends the process like
// Go does (ADR-0011): a goroutine parked forever on a channel and a live
// ticker must not keep the program alive, and main's defers still run.
package main

import (
	"fmt"
	"time"
)

func worker(c chan int) {
	v := <-c
	fmt.Println(v)
}

func bye() {
	fmt.Println("deferred")
}

func main() {
	c := make(chan int)
	tick := time.Tick(time.Hour)
	x := 1
	go worker(c)
	defer bye()
	fmt.Println("before")
	if x == 1 {
		return
	}
	<-tick
	fmt.Println("unreachable")
}
