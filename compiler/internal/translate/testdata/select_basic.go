package p

func selectAll(c1 chan int, c2 chan int) {
	select {
	case v := <-c1:
		c2 <- v
	case v, ok := <-c1:
		if ok {
			c2 <- v
		}
	case _, ok := <-c1:
		if ok {
			c2 <- 0
		}
	case <-c1:
		c2 <- 0
	case c2 <- 42:
	default:
	}
}
