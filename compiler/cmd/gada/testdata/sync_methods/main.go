// sync_methods exercises every sync method lowering plus runtime.Gosched
// / runtime.GOMAXPROCS and a go-free time.Tick main, end to end
// through gprbuild (PR #46 review findings #1, #5, #6).
package main

import (
	"fmt"
	"runtime"
	"sync"
	"time"
)

func hello() {
	fmt.Println("once")
}

func main() {
	var rw sync.RWMutex
	var mu sync.Mutex
	var wg sync.WaitGroup
	var once sync.Once
	p := 0
	tick := time.Tick(time.Millisecond)
	rw.RLock()
	rw.RUnlock()
	rw.TryRLock()
	rw.RUnlock()
	rw.Lock()
	rw.Unlock()
	rw.TryLock()
	rw.Unlock()
	mu.Lock()
	mu.TryLock()
	mu.Unlock()
	wg.Add(1)
	wg.Done()
	wg.Wait()
	once.Do(hello)
	once.Do(hello)
	runtime.Gosched()
	p = runtime.GOMAXPROCS(0)
	if p > 0 {
		fmt.Println("procs ok")
	}
	<-tick
	fmt.Println("done")
}
