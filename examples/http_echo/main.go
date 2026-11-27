package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
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
	var body []byte
	var rerr error
	body, rerr = io.ReadAll(r.Body)
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

func serve() {
	var err error
	err = http.ListenAndServe("127.0.0.1:18099", nil)
	if err != nil {
		fmt.Println("serve returned")
	}
}

func main() {
	var resp *http.Response
	var err error
	var rb []byte
	var rerr2 error
	http.HandleFunc("/echo", echo)
	go serve()
	for i := 0; i < 20; i = i + 1 {
		resp, err = http.Get("http://127.0.0.1:18099/echo")
		time.Sleep(50 * time.Millisecond)
	}
	if err != nil {
		fmt.Println("server did not start")
		return
	}
	fmt.Println(resp.StatusCode)
	resp, err = http.Post("http://127.0.0.1:18099/echo", "application/json",
		bytes.NewReader([]byte("{\"N\":41,\"On\":true,\"R\":0.5}")))
	if err != nil {
		fmt.Println("post failed")
		return
	}
	fmt.Println(resp.StatusCode)
	rb, rerr2 = io.ReadAll(resp.Body)
	if rerr2 != nil {
		fmt.Println("read resp body failed")
		return
	}
	fmt.Println(string(rb))
}
