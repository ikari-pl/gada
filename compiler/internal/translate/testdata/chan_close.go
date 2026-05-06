package p

func produce(c chan int) {
	c <- 1
	c <- 2
	close(c)
}

func drain(c chan int) {
	v, ok := <-c
	if !ok {
		return
	}
	c <- v
	close(c)
}

func closeString(c chan string) {
	close(c)
}
