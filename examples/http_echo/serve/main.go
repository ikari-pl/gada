package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

type Msg struct {
	N  int
	On bool
	R  float64
}

func echo(w http.ResponseWriter, r *http.Request) {
	var m Msg
	var b []byte
	var err error
	var err2 error
	body, rerr := io.ReadAll(r.Body)
	if rerr != nil {
		w.Write([]byte("read body failed"))
		return
	}
	err = json.Unmarshal(body, &m)
	if err != nil {
		w.Write([]byte("bad json"))
		return
	}
	m.N = m.N + 1
	b, err2 = json.Marshal(m)
	if err2 != nil {
		return
	}
	w.Write(b)
}

func main() {
	var err error
	http.HandleFunc("/echo", echo)
	err = http.ListenAndServe("127.0.0.1:8080", nil)
	if err != nil {
		fmt.Println("serve returned")
	}
}
