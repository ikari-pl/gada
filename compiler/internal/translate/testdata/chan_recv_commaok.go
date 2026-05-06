package p

func recvCommaOk(c chan int) {
	v, ok := <-c
	if ok {
		c <- v + 1
	}
}

func recvCommaOkString(c chan string) {
	s, ok := <-c
	if ok {
		c <- s
	}
}
