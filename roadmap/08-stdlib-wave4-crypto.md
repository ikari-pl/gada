# Phase 8 — Stdlib wave 4: crypto, hash, encoding/*

[← Phase 7](07-stdlib-wave3-network.md) · [Index](README.md) · Next: [Phase 9 →](09-verification-spark.md)

**Status:** `IN_PROGRESS` (opened 2026-11-27)
**Prerequisites:** [Phase 5](05-stdlib-wave1.md) `DONE`
**Goal:** Port `crypto/*`, `hash/*`, the rest of `encoding/*`. These
are pure-Go packages; the work is mostly about correctness against
test vectors.
**Exit criterion:** all NIST CAVS test vectors for SHA-256, SHA-512,
HMAC-SHA-256 pass; AES-GCM round-trips; base64/hex round-trip.

## Items

- [x] **Stdlib packages: `hash/crc32`, `hash/crc64`, `hash/fnv`, `hash/adler32`** (done 2026-11-27, CI green on 9928f3b, run 46084031724)
      *Files:* `runtime/src/gada-std-hash{,-crc32,-crc64,-fnv,-adler32}.{ads,adb}`, `runtime/tests/stdlib/std_hash_suite.{ads,adb}` (suite `stdlib.hash`), `compiler/internal/ir/stdlib.go`
      *Verify:* `make stdlib-test PKG=hash`
      *Done when:* met — all vectors pinned from Go 1.27 via `go run`
      (incl. classic check values CRC-32/IEEE \"123456789\" = CBF43926,
      CRC-64/ECMA = 995DC9BBDF1939FA, ISO = B90956C775A41001, FNV offset
      bases, Adler-32 RFC 1950 incl. a 6000-byte input crossing the
      NMAX=5552 batch boundary); runtime/ 100% gate green (two
      `end Make_Table;` terminators excluded with rationale in
      runtime/COVERAGE.md).

- [ ] **Stdlib packages: `crypto/sha256`, `crypto/sha512`, `crypto/sha1`, `crypto/md5`**
      *Files:* `stdlib/crypto/...`
      *Verify:* `make stdlib-test PKG=crypto.hash`
      *Done when:* CAVS vectors pass; coverage 100%.

- [ ] **Stdlib package: `crypto/hmac`**
      *Files:* `stdlib/crypto/hmac/`
      *Verify:* `make stdlib-test PKG=crypto.hmac`
      *Done when:* RFC 2202 + RFC 4231 test vectors pass.

- [ ] **Stdlib packages: `crypto/aes`, `crypto/cipher`**
      *Files:* `stdlib/crypto/aes/`, `stdlib/crypto/cipher/`
      *Verify:* `make stdlib-test PKG=crypto.aes`
      *Done when:* AES-128/192/256, ECB/CBC/CTR/GCM all match NIST KAT; coverage 100%.

- [ ] **Stdlib packages: `encoding/base64`, `encoding/hex`, `encoding/binary`**
      *Files:* `stdlib/encoding/...`
      *Verify:* `make stdlib-test PKG=encoding`
      *Done when:* round-trip on randomized inputs; coverage 100%.

- [ ] **Stdlib packages: `encoding/csv`, `encoding/xml`**
      *Files:* `stdlib/encoding/csv/`, `stdlib/encoding/xml/`
      *Verify:* `make stdlib-test PKG=encoding.text`
      *Done when:* round-trip on representative documents; coverage ≥ 90%.

- [ ] **Crypto-suite example**
      *Files:* `examples/crypto_suite/main.go`
      *Verify:* `make example HELLO=crypto_suite`
      *Done when:* example computes hashes, signs and verifies an HMAC, encrypts and decrypts an AES-GCM payload, prints expected output.
