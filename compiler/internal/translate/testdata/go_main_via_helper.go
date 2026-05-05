package main

func worker() {}

func helper() {
	go worker()
}

func main() {
	helper()
}
