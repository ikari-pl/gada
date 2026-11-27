--  Body of Std_Crypto_Hash_Suite — see spec for test rationale. All
--  expected values pinned from Go 1.27 via `go run`.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Crypto.Sha256;
with Gada.Std.Crypto.Sha512;
with Gada.Std.Crypto.Sha1;
with Gada.Std.Crypto.Md5;

package body Std_Crypto_Hash_Suite is

   overriding function Name
     (T : Std_Crypto_Hash_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Crypto hash suite (PKG=stdlib.crypto.hash)"));

   overriding procedure Register_Tests (T : in out Std_Crypto_Hash_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Sha256'Access, "sha256 vectors + API");
      Register_Routine (T, Test_Sha512'Access, "sha512 vectors + API");
      Register_Routine (T, Test_Sha1'Access, "sha1 vectors + API");
      Register_Routine (T, Test_Md5'Access, "md5 vectors + API");
   end Register_Tests;

   function To_Hex (B : Byte_Slice) return String is
      Hex : constant String := "0123456789abcdef";
      R   : String (1 .. 2 * Natural (Byte_Vectors.Length (B)));
   begin
      for I in 1 .. Natural (Byte_Vectors.Length (B)) loop
         declare
            V : constant Natural :=
              Character'Pos (Byte_Vectors.Element (B, I));
         begin
            R (2 * I - 1) := Hex (V / 16 + 1);
            R (2 * I)     := Hex (V mod 16 + 1);
         end;
      end loop;
      return R;
   end To_Hex;

   --  Byte_Slice sub-range copy (Ada.Containers.Vectors.Slice is not
   --  relied on; an explicit loop keeps the suite obvious).
   function Sub (B : Byte_Slice; First, Last : Positive) return Byte_Slice is
      R : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      for I in First .. Last loop
         Byte_Vectors.Append (R, Byte_Vectors.Element (B, I));
      end loop;
      return R;
   end Sub;

   --  The shared input corpus, in order: "", "abc", the 56-byte FIPS
   --  two-block message, then 55/56/63/64/65/1000 x 'a' to hit every
   --  padding boundary around the 64- and 128-byte block sizes.
   Inputs : constant array (Positive range <>) of Unbounded_String :=
     (To_Unbounded_String (""),
      To_Unbounded_String ("abc"),
      To_Unbounded_String
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
      To_Unbounded_String ((1 .. 55 => 'a')),
      To_Unbounded_String ((1 .. 56 => 'a')),
      To_Unbounded_String ((1 .. 63 => 'a')),
      To_Unbounded_String ((1 .. 64 => 'a')),
      To_Unbounded_String ((1 .. 65 => 'a')),
      To_Unbounded_String ((1 .. 1000 => 'a')));

   type Hexes is array (Positive range <>) of Unbounded_String;

   Sha256_Expect : constant Hexes (Inputs'Range) :=
     (To_Unbounded_String
        ("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
      To_Unbounded_String
        ("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
      To_Unbounded_String
        ("248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
      To_Unbounded_String
        ("9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
      To_Unbounded_String
        ("b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
      To_Unbounded_String
        ("7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"),
      To_Unbounded_String
        ("ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"),
      To_Unbounded_String
        ("635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"),
      To_Unbounded_String
        ("41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5a5d134645adb5db1b9737ea3"));

   Sha512_Expect : constant Hexes (Inputs'Range) :=
     (To_Unbounded_String
        ("cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
         & "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"),
      To_Unbounded_String
        ("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
         & "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"),
      To_Unbounded_String
        ("204a8fc6dda82f0a0ced7beb8e08a41657c16ef468b228a8279be331a703c335"
         & "96fd15c13b1b07f9aa1d3bea57789ca031ad85c7a71dd70354ec631238ca3445"),
      To_Unbounded_String
        ("b0220c772cbf6c1822e2cb38a437d0e1d58772417a4bbb21c961364f8b6143e0"
         & "5aa6316dca8d0d7b19e16448419076395f6086cb55101fbd6d5497b148e1745f"),
      To_Unbounded_String
        ("962b64aae357d2a4fee3ded8b539bdc9d325081822b0bfc55583133aab44f18b"
         & "afe11d72a7ae16c79ce2ba620ae2242d5144809161945f1367f41b3972e26e04"),
      To_Unbounded_String
        ("c1b0f5c6d3b03dfe4a2602e67242f54e344090b66e01100a469b129f583f016c"
         & "7e27dddeaa438393dcc7ec54b0b57c9ba7af007f9b56db5f6fb677d972a31362"),
      To_Unbounded_String
        ("01d35c10c6c38c2dcf48f7eebb3235fb5ad74a65ec4cd016e2354c637a8fb49"
         & "b695ef3c1d6f7ae4cd74d78cc9c9bcac9d4f23a73019998a7f73038a5c9b2dbde"),
      To_Unbounded_String
        ("b83086cd8494e55708ad7ecd82dfb4bca1bda61ecbb7caf0c68967902e709345"
         & "e5d8305eb7ac0d588afc6cbb75161aa9c8c7e0ea986bd833dafe5e1ccd37345a"),
      To_Unbounded_String
        ("67ba5535a46e3f86dbfbed8cbbaf0125c76ed549ff8b0b9e03e0c88cf90fa634"
         & "fa7b12b47d77b694de488ace8d9a65967dc96df599727d3292a8d9d447709c97"));

   Sha1_Expect : constant Hexes (Inputs'Range) :=
     (To_Unbounded_String ("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
      To_Unbounded_String ("a9993e364706816aba3e25717850c26c9cd0d89d"),
      To_Unbounded_String ("84983e441c3bd26ebaae4aa1f95129e5e54670f1"),
      To_Unbounded_String ("c1c8bbdc22796e28c0e15163d20899b65621d65a"),
      To_Unbounded_String ("c2db330f6083854c99d4b5bfb6e8f29f201be699"),
      To_Unbounded_String ("03f09f5b158a7a8cdad920bddc29b81c18a551f5"),
      To_Unbounded_String ("0098ba824b5c16427bd7a1122a5a442a25ec644d"),
      To_Unbounded_String ("11655326c708d70319be2610e8a57d9a5b959b3b"),
      To_Unbounded_String ("291e9a6c66994949b57ba5e650361e98fc36b8a9"));

   Md5_Expect : constant Hexes (Inputs'Range) :=
     (To_Unbounded_String ("d41d8cd98f00b204e9800998ecf8427e"),
      To_Unbounded_String ("900150983cd24fb0d6963f7d28e17f72"),
      To_Unbounded_String ("8215ef0796a20bcaaae116d3876c664a"),
      To_Unbounded_String ("ef1772b6dff9a122358552954ad0df65"),
      To_Unbounded_String ("3b0c8ac703f828b04c6c197006d17218"),
      To_Unbounded_String ("b06521f39153d618550606be297466d5"),
      To_Unbounded_String ("014842d480b571495a4a0363793f7367"),
      To_Unbounded_String ("c743a45e0d2e6a95cb859adae0248435"),
      To_Unbounded_String ("cabe45dcc9ae5b66ba86600cca6b8ba8"));

   procedure Test_Sha256 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for I in Inputs'Range loop
         declare
            B : constant Byte_Slice := To_Bytes (To_String (Inputs (I)));
            N : constant Natural := Natural (Byte_Vectors.Length (B));
            H : Gada.Std.Crypto.Sha256.Digest := Gada.Std.Crypto.Sha256.New;
         begin
            Assert
              (To_Hex (Gada.Std.Crypto.Sha256.Sum256 (B))
                 = To_String (Sha256_Expect (I)),
               "sha256 one-shot #" & Integer'Image (I));
            --  split Write at the midpoint equals the one-shot digest
            Gada.Std.Crypto.Sha256.Write (H, Sub (B, 1, N / 2));
            Gada.Std.Crypto.Sha256.Write (H, Sub (B, N / 2 + 1, N));
            Assert
              (To_Hex (Gada.Std.Crypto.Sha256.Sum
                 (H, Byte_Vectors.Empty_Vector))
                 = To_String (Sha256_Expect (I)),
               "sha256 split write #" & Integer'Image (I));
         end;
      end loop;
      --  API shape: Size / Block_Size / Sum appends to B / Reset
      declare
         H : Gada.Std.Crypto.Sha256.Digest := Gada.Std.Crypto.Sha256.New;
         S : Byte_Slice;
      begin
         Assert (Gada.Std.Crypto.Sha256.Size (H) = 32, "sha256 Size");
         Assert (Gada.Std.Crypto.Sha256.Block_Size (H) = 64,
                 "sha256 Block_Size");
         Gada.Std.Crypto.Sha256.Write (H, To_Bytes ("abc"));
         S := Gada.Std.Crypto.Sha256.Sum (H, To_Bytes ("xy"));
         Assert (Integer (Byte_Vectors.Length (S)) = 34, "Sum appends len");
         Assert (Byte_Vectors.Element (S, 1) = 'x'
                   and then Byte_Vectors.Element (S, 2) = 'y',
                 "Sum keeps prefix");
         Assert (To_Hex (Sub (S, 3, 34))
                   = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                 "Sum appends digest");
         Gada.Std.Crypto.Sha256.Reset (H);
         Assert (To_Hex (Gada.Std.Crypto.Sha256.Sum
                   (H, Byte_Vectors.Empty_Vector))
                   = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                 "sha256 Reset");
      end;
   end Test_Sha256;

   procedure Test_Sha512 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for I in Inputs'Range loop
         declare
            B : constant Byte_Slice := To_Bytes (To_String (Inputs (I)));
            N : constant Natural := Natural (Byte_Vectors.Length (B));
            H : Gada.Std.Crypto.Sha512.Digest := Gada.Std.Crypto.Sha512.New;
         begin
            Assert
              (To_Hex (Gada.Std.Crypto.Sha512.Sum512 (B))
                 = To_String (Sha512_Expect (I)),
               "sha512 one-shot #" & Integer'Image (I));
            Gada.Std.Crypto.Sha512.Write (H, Sub (B, 1, N / 2));
            Gada.Std.Crypto.Sha512.Write (H, Sub (B, N / 2 + 1, N));
            Assert
              (To_Hex (Gada.Std.Crypto.Sha512.Sum
                 (H, Byte_Vectors.Empty_Vector))
                 = To_String (Sha512_Expect (I)),
               "sha512 split write #" & Integer'Image (I));
         end;
      end loop;
      declare
         H : Gada.Std.Crypto.Sha512.Digest := Gada.Std.Crypto.Sha512.New;
         S : Byte_Slice;
      begin
         Assert (Gada.Std.Crypto.Sha512.Size (H) = 64, "sha512 Size");
         Assert (Gada.Std.Crypto.Sha512.Block_Size (H) = 128,
                 "sha512 Block_Size");
         Gada.Std.Crypto.Sha512.Write (H, To_Bytes ("abc"));
         S := Gada.Std.Crypto.Sha512.Sum (H, To_Bytes ("xy"));
         Assert (Integer (Byte_Vectors.Length (S)) = 66, "Sum appends len");
         Gada.Std.Crypto.Sha512.Reset (H);
         Assert (To_Hex (Gada.Std.Crypto.Sha512.Sum
                   (H, Byte_Vectors.Empty_Vector))
                   = "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
                     & "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
                 "sha512 Reset");
      end;
   end Test_Sha512;

   procedure Test_Sha1 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for I in Inputs'Range loop
         declare
            B : constant Byte_Slice := To_Bytes (To_String (Inputs (I)));
            N : constant Natural := Natural (Byte_Vectors.Length (B));
            H : Gada.Std.Crypto.Sha1.Digest := Gada.Std.Crypto.Sha1.New;
         begin
            Assert
              (To_Hex (Gada.Std.Crypto.Sha1.Sum (B))
                 = To_String (Sha1_Expect (I)),
               "sha1 one-shot #" & Integer'Image (I));
            Gada.Std.Crypto.Sha1.Write (H, Sub (B, 1, N / 2));
            Gada.Std.Crypto.Sha1.Write (H, Sub (B, N / 2 + 1, N));
            Assert
              (To_Hex (Gada.Std.Crypto.Sha1.Sum
                 (H, Byte_Vectors.Empty_Vector))
                 = To_String (Sha1_Expect (I)),
               "sha1 split write #" & Integer'Image (I));
         end;
      end loop;
      declare
         H : Gada.Std.Crypto.Sha1.Digest := Gada.Std.Crypto.Sha1.New;
         S : Byte_Slice;
      begin
         Assert (Gada.Std.Crypto.Sha1.Size (H) = 20, "sha1 Size");
         Assert (Gada.Std.Crypto.Sha1.Block_Size (H) = 64,
                 "sha1 Block_Size");
         Gada.Std.Crypto.Sha1.Write (H, To_Bytes ("abc"));
         S := Gada.Std.Crypto.Sha1.Sum (H, To_Bytes ("xy"));
         Assert (Integer (Byte_Vectors.Length (S)) = 22, "Sum appends len");
         Gada.Std.Crypto.Sha1.Reset (H);
         Assert (To_Hex (Gada.Std.Crypto.Sha1.Sum
                   (H, Byte_Vectors.Empty_Vector))
                   = "da39a3ee5e6b4b0d3255bfef95601890afd80709",
                 "sha1 Reset");
      end;
   end Test_Sha1;

   procedure Test_Md5 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for I in Inputs'Range loop
         declare
            B : constant Byte_Slice := To_Bytes (To_String (Inputs (I)));
            N : constant Natural := Natural (Byte_Vectors.Length (B));
            H : Gada.Std.Crypto.Md5.Digest := Gada.Std.Crypto.Md5.New;
         begin
            Assert
              (To_Hex (Gada.Std.Crypto.Md5.Sum (B))
                 = To_String (Md5_Expect (I)),
               "md5 one-shot #" & Integer'Image (I));
            Gada.Std.Crypto.Md5.Write (H, Sub (B, 1, N / 2));
            Gada.Std.Crypto.Md5.Write (H, Sub (B, N / 2 + 1, N));
            Assert
              (To_Hex (Gada.Std.Crypto.Md5.Sum
                 (H, Byte_Vectors.Empty_Vector))
                 = To_String (Md5_Expect (I)),
               "md5 split write #" & Integer'Image (I));
         end;
      end loop;
      declare
         H : Gada.Std.Crypto.Md5.Digest := Gada.Std.Crypto.Md5.New;
         S : Byte_Slice;
      begin
         Assert (Gada.Std.Crypto.Md5.Size (H) = 16, "md5 Size");
         Assert (Gada.Std.Crypto.Md5.Block_Size (H) = 64,
                 "md5 Block_Size");
         Gada.Std.Crypto.Md5.Write (H, To_Bytes ("abc"));
         S := Gada.Std.Crypto.Md5.Sum (H, To_Bytes ("xy"));
         Assert (Integer (Byte_Vectors.Length (S)) = 18, "Sum appends len");
         Gada.Std.Crypto.Md5.Reset (H);
         Assert (To_Hex (Gada.Std.Crypto.Md5.Sum
                   (H, Byte_Vectors.Empty_Vector))
                   = "d41d8cd98f00b204e9800998ecf8427e",
                 "md5 Reset");
      end;
   end Test_Md5;

end Std_Crypto_Hash_Suite;
