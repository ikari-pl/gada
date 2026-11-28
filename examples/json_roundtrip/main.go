package main

import (
	"encoding/json"
	"fmt"
)

type Point struct {
	X  int
	Y  int
	On bool
	R  float64
}

func main() {
	var p Point
	var q Point
	var data []byte
	var err error
	var err2 error
	p.X = 3
	p.Y = 4
	p.On = true
	p.R = 2.5
	data, err = json.Marshal(p)
	if err != nil {
		fmt.Println("marshal failed")
		return
	}
	fmt.Println(string(data))
	err2 = json.Unmarshal(data, &q)
	if err2 != nil {
		fmt.Println("unmarshal failed")
		return
	}
	if q.X == p.X && q.Y == p.Y && q.On == p.On && q.R == p.R {
		fmt.Println("roundtrip equal")
	} else {
		fmt.Println("roundtrip mismatch")
	}
}
