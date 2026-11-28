// timer_pool is the Phase 6 exit-criterion example: a worker pool
// processes jobs from a channel, a deadline from time.After bounds the
// run, a sync.Mutex guards the result counter, os.Args tunes the job
// count, and runtime.NumGoroutine reports the live goroutine count.
//
// Shapes stay within the Phase 1-6 emitter subset: head-of-body
// defines, trivial for loops, single-type select cases, go-with-args,
// close, and multi-arg fmt.Println.
package main

import (
	"fmt"
	"os"
	"runtime"
	"sync"
	"time"
)

// worker pulls jobs until jobs is closed; each job reports j*2 on
// results.
func worker(jobs chan int, results chan int) {
	for {
		select {
		case j, ok := <-jobs:
			if ok {
				results <- j * 2
			} else {
				return
			}
		}
	}
}

func main() {
	argc := len(os.Args)
	n := 4
	jobs := make(chan int, 8)
	results := make(chan int, 8)
	timer := time.After(200 * time.Millisecond)
	var mu sync.Mutex
	done := 0
	g := 0

	if argc >= 2 {
		n = argc
	}
	go worker(jobs, results)
	go worker(jobs, results)
	// Spawn bumps the scheduler's live count synchronously, so this
	// is deterministically main + 2 workers.
	g = runtime.NumGoroutine()
	for j := 0; j < n; j = j + 1 {
		jobs <- j
	}
	close(jobs)
	for i := 0; i < n; i = i + 1 {
		select {
		case r := <-results:
			mu.Lock()
			done = done + r
			mu.Unlock()
		}
	}
	<-timer

	fmt.Println("jobs:", n)
	fmt.Println("sum:", done)
	fmt.Println("goroutines:", g)
	fmt.Println("argc:", argc)
}
