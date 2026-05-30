package p

// relay receives one value from ping and forwards it to pong. Used to
// exercise `go relay(a, b)` argument capture: both chan operands are
// snapshotted at the spawn site and unpacked inside the goroutine.
func relay(ping chan int, pong chan int) {
	v := <-ping
	pong <- v
}

func start() {
	a := make(chan int, 1)
	b := make(chan int, 1)
	go relay(a, b)
}
