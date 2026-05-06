package p

func sendInts(c chan int) {
	x := 42
	c <- 1
	c <- x
}

func sendStrings(c chan string) {
	c <- "hello"
}
