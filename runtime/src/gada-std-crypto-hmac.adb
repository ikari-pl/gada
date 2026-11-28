--  Gada.Std.Crypto.Hmac body — see spec. RFC 2104: keys longer than
--  the block size are hashed first, then zero-padded; ipad = 0x36,
--  opad = 0x5C per byte.

with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Crypto.Sha256;
with Gada.Std.Crypto.Sha512;
with Gada.Std.Crypto.Sha1;
with Gada.Std.Crypto.Md5;

package body Gada.Std.Crypto.Hmac is

   function Block_Of (Algo : Algorithm) return Natural is
   begin
      case Algo is
         when Sha256 | Sha1 | Md5 => return 64;
         when Sha512              => return 128;
      end case;
   end Block_Of;

   function Digest_Size (Algo : Algorithm) return Natural is
   begin
      case Algo is
         when Sha256 => return 32;
         when Sha512 => return 64;
         when Sha1   => return 20;
         when Md5    => return 16;
      end case;
   end Digest_Size;

   --  RFC 2104 step 1/2: hash the key if longer than the block size,
   --  then zero-pad to exactly the block size.
   function Pad_Key (Algo : Algorithm; Key : Byte_Slice) return Byte_Slice is
      Block : constant Natural := Block_Of (Algo);
      K     : Byte_Slice := Key;
   begin
      if Natural (Byte_Vectors.Length (K)) > Block then
         case Algo is
            when Sha256 => K := Gada.Std.Crypto.Sha256.Sum256 (K);
            when Sha512 => K := Gada.Std.Crypto.Sha512.Sum512 (K);
            when Sha1   => K := Gada.Std.Crypto.Sha1.Sum (K);
            when Md5    => K := Gada.Std.Crypto.Md5.Sum (K);
         end case;
      end if;
      while Natural (Byte_Vectors.Length (K)) < Block loop
         Byte_Vectors.Append (K, Character'Val (0));
      end loop;
      return K;
   end Pad_Key;

   function Xor_Pad (K : Byte_Slice; Pad : Character) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      for I in 1 .. Natural (Byte_Vectors.Length (K)) loop
         Byte_Vectors.Append
           (R, Character'Val
              (Character'Pos (Byte_Vectors.Element (K, I))
               xor Character'Pos (Pad)));
      end loop;
      return R;
   end Xor_Pad;

   function New_K (Algo : Algorithm; Key : Byte_Slice) return Hmac is
      K : constant Byte_Slice := Pad_Key (Algo, Key);
   begin
      return
        (Algo  => Algo,
         I_Pad => Xor_Pad (K, Character'Val (16#36#)),
         O_Pad => Xor_Pad (K, Character'Val (16#5C#)),
         Buf   => Byte_Vectors.Empty_Vector);
   end New_K;

   procedure Write (H : in out Hmac; Data : Byte_Slice) is
   begin
      for I in 1 .. Natural (Byte_Vectors.Length (Data)) loop
         Byte_Vectors.Append (H.Buf, Byte_Vectors.Element (Data, I));
      end loop;
   end Write;

   function Sum (H : Hmac; B : Byte_Slice) return Byte_Slice is
   begin
      --  inner = H(ipad || message); mac = H(opad || inner)
      case H.Algo is
         when Sha256 =>
            declare
               I : Gada.Std.Crypto.Sha256.Digest := Gada.Std.Crypto.Sha256.New_K;
               O : Gada.Std.Crypto.Sha256.Digest := Gada.Std.Crypto.Sha256.New_K;
            begin
               Gada.Std.Crypto.Sha256.Write (I, H.I_Pad);
               Gada.Std.Crypto.Sha256.Write (I, H.Buf);
               Gada.Std.Crypto.Sha256.Write (O, H.O_Pad);
               Gada.Std.Crypto.Sha256.Write
                 (O, Gada.Std.Crypto.Sha256.Sum (I, Byte_Vectors.Empty_Vector));
               return Gada.Std.Crypto.Sha256.Sum (O, B);
            end;
         when Sha512 =>
            declare
               I : Gada.Std.Crypto.Sha512.Digest := Gada.Std.Crypto.Sha512.New_K;
               O : Gada.Std.Crypto.Sha512.Digest := Gada.Std.Crypto.Sha512.New_K;
            begin
               Gada.Std.Crypto.Sha512.Write (I, H.I_Pad);
               Gada.Std.Crypto.Sha512.Write (I, H.Buf);
               Gada.Std.Crypto.Sha512.Write (O, H.O_Pad);
               Gada.Std.Crypto.Sha512.Write
                 (O, Gada.Std.Crypto.Sha512.Sum (I, Byte_Vectors.Empty_Vector));
               return Gada.Std.Crypto.Sha512.Sum (O, B);
            end;
         when Sha1 =>
            declare
               I : Gada.Std.Crypto.Sha1.Digest := Gada.Std.Crypto.Sha1.New_K;
               O : Gada.Std.Crypto.Sha1.Digest := Gada.Std.Crypto.Sha1.New_K;
            begin
               Gada.Std.Crypto.Sha1.Write (I, H.I_Pad);
               Gada.Std.Crypto.Sha1.Write (I, H.Buf);
               Gada.Std.Crypto.Sha1.Write (O, H.O_Pad);
               Gada.Std.Crypto.Sha1.Write
                 (O, Gada.Std.Crypto.Sha1.Sum (I, Byte_Vectors.Empty_Vector));
               return Gada.Std.Crypto.Sha1.Sum (O, B);
            end;
         when Md5 =>
            declare
               I : Gada.Std.Crypto.Md5.Digest := Gada.Std.Crypto.Md5.New_K;
               O : Gada.Std.Crypto.Md5.Digest := Gada.Std.Crypto.Md5.New_K;
            begin
               Gada.Std.Crypto.Md5.Write (I, H.I_Pad);
               Gada.Std.Crypto.Md5.Write (I, H.Buf);
               Gada.Std.Crypto.Md5.Write (O, H.O_Pad);
               Gada.Std.Crypto.Md5.Write
                 (O, Gada.Std.Crypto.Md5.Sum (I, Byte_Vectors.Empty_Vector));
               return Gada.Std.Crypto.Md5.Sum (O, B);
            end;
      end case;
   end Sum;

   procedure Reset (H : in out Hmac) is
   begin
      H.Buf := Byte_Vectors.Empty_Vector;
   end Reset;

   function Size (H : Hmac) return Natural is
   begin
      return Digest_Size (H.Algo);
   end Size;

   function Block_Size (H : Hmac) return Natural is
   begin
      return Block_Of (H.Algo);
   end Block_Size;

   function Equal (A, B : Byte_Slice) return Boolean is
      N    : constant Natural := Natural (Byte_Vectors.Length (A));
      M    : constant Natural := Natural (Byte_Vectors.Length (B));
      Diff : Natural := N xor M;  --  non-zero if lengths differ
   begin
      --  Accumulate instead of early-exit, like Go's
      --  subtle.ConstantTimeCompare (loop runs over the min length).
      for I in 1 .. Natural'Min (N, M) loop
         Diff := Diff
           or (Character'Pos (Byte_Vectors.Element (A, I))
               xor Character'Pos (Byte_Vectors.Element (B, I)));
      end loop;
      return Diff = 0;
   end Equal;

end Gada.Std.Crypto.Hmac;
