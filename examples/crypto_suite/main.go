package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
)

func main() {
	msg := []byte("hello gada")
	key := []byte("0123456789abcdef0123456789abcdef")
	sum := sha256.Sum256(msg)
	mac := hmac.New(sha256.New, key)
	block, err := aes.NewCipher(key)
	gcm, err2 := cipher.NewGCM(block)
	nonce := []byte("012345678901")
	sealed := gcm.Seal(make([]byte, 0), nonce, msg, make([]byte, 0))
	opened, err3 := gcm.Open(make([]byte, 0), nonce, sealed, make([]byte, 0))
	var sig []byte

	mac.Write(msg)
	sig = mac.Sum(make([]byte, 0))

	if err != nil {
		fmt.Println("aes error")
		return
	}
	if err2 != nil {
		fmt.Println("gcm error")
		return
	}
	if err3 != nil {
		fmt.Println("open error")
		return
	}
	fmt.Println("sha256:", hex.EncodeToString(sum[:]))
	fmt.Println("hmac:", hex.EncodeToString(sig))
	if hmac.Equal(sig, sig) {
		fmt.Println("verify: true")
	} else {
		fmt.Println("verify: false")
	}
	fmt.Println("gcm:", hex.EncodeToString(sealed))
	fmt.Println("plain:", string(opened))
}
