--  Gada.Std.Crypto.Hmac — the Go `crypto/hmac` package, ported
--  (Phase 8 wave 4, item 3). RFC 2104 HMAC over the four hash ports
--  in this wave: H((K xor opad) || H((K xor ipad) || m)).
--
--  Go: hmac.New(h func() hash.Hash, key []byte) hash.Hash. The
--  hash.Hash interface port is a later item, so v1 takes the
--  algorithm as an explicit tag: hmac.New(sha256.New, key) becomes
--  New_K (Sha256, Key) (`new` is an Ada reserved word, hence _K —
--  same rule as the sha256.New port).
--
--  Write/Sum/Reset/Size/Block_Size mirror the concrete Digest ports;
--  Equal is Go's hmac.Equal (constant-time compare of two MACs).
--
--  v1 buffers the message in Hmac.Buf and runs fresh digests over
--  pad+message in Sum (the Digest types are private to their own
--  packages, so they cannot be embedded by value here). Semantics
--  are identical to Go's streaming construction.

with Gada.Std.Bytes;

package Gada.Std.Crypto.Hmac is

   type Algorithm is (Sha256, Sha512, Sha1, Md5);

   type Hmac is limited private;

   --  Go: hmac.New(sha256.New, key) — v1: New_K (Sha256, Key).
   function New_K (Algo : Algorithm; Key : Gada.Std.Bytes.Byte_Slice)
      return Hmac;

   --  Go: h.Write(p) (io.Writer) — returns (len p, nil error); v1 is
   --  a procedure, the error half is always nil.
   procedure Write (H : in out Hmac; Data : Gada.Std.Bytes.Byte_Slice);

   --  Go: h.Sum(b) []byte — appends the MAC. Does not modify H.
   function Sum (H : Hmac; B : Gada.Std.Bytes.Byte_Slice)
      return Gada.Std.Bytes.Byte_Slice;

   --  Go: h.Reset(), h.Size() int, h.BlockSize() int.
   procedure Reset (H : in out Hmac);
   function Size (H : Hmac) return Natural;
   function Block_Size (H : Hmac) return Natural;

   --  Go: hmac.Equal(mac1, mac2 []byte) bool — compares in constant
   --  time (lengths are not early-exited).
   function Equal (A, B : Gada.Std.Bytes.Byte_Slice) return Boolean;

private

   type Hmac is record
      Algo             : Algorithm;
      I_Pad, O_Pad     : Gada.Std.Bytes.Byte_Slice;  --  kept for Reset
      Buf              : Gada.Std.Bytes.Byte_Slice;  --  message so far
   end record;

end Gada.Std.Crypto.Hmac;
