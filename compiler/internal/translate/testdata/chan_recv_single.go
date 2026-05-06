package p

func recvInt(c chan int) {
	v := <-c
	c <- v + 1
}

func recvString(c chan string) {
	s := <-c
	c <- s
}
