package p

func consumeInt(c chan int)       {}
func consumeString(c chan string) {}

func makeBuffered() {
	consumeInt(make(chan int, 8))
	consumeInt(make(chan int))
	consumeString(make(chan string, 4))
}
