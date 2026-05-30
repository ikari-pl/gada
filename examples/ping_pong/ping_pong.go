// ping_pong bounces a token between two goroutines a million times over
// a pair of channels, then prints the iteration count. It exercises the
// whole Phase 3 concurrency surface end-to-end: `go f(args)` argument
// capture (the relays receive their channels by value), buffered
// channels, `select` (both the comma-ok and trivial-for shapes),
// `close`, and multi-argument `fmt.Println` with integer rendering.
//
// main waits on an explicit `done` channel so the program behaves
// identically under `go run` and under GADA: without it, Go's main
// would exit before the relays printed. The ponger owns the counter,
// the final print, and the close of `ping` that releases the pinger.
package main

import "fmt"

// pinger forwards whatever it receives on ping out to pong, until ping
// is closed (ok == false), at which point it returns.
func pinger(ping chan int, pong chan int) {
	for {
		select {
		case v, ok := <-ping:
			if ok {
				pong <- v
			} else {
				return
			}
		}
	}
}

// ponger seeds the bounce, then receives a million times from pong,
// echoing each value back onto ping and counting. When the count is
// reached it closes ping (releasing the pinger), prints the total, and
// signals done.
func ponger(ping chan int, pong chan int, done chan int) {
	count := 0
	ping <- 0
	for i := 0; i < 1000000; i = i + 1 {
		select {
		case v := <-pong:
			ping <- v
			count = count + 1
		}
	}
	close(ping)
	fmt.Println("iterations:", count)
	done <- count
}

func main() {
	ping := make(chan int, 1)
	pong := make(chan int, 1)
	done := make(chan int, 1)
	go pinger(ping, pong)
	go ponger(ping, pong, done)
	<-done
}
