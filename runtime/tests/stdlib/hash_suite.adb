--  Body of Std_Hash_Suite — see spec for test rationale. All expected
--  values pinned from Go 1.27 via `go run`.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces; use Interfaces;

with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Hash.Crc32;
with Gada.Std.Hash.Crc64;
with Gada.Std.Hash.Fnv;
with Gada.Std.Hash.Adler32;

package body Std_Hash_Suite is

   use type Unsigned_32;
   use type Unsigned_64;

   overriding function Name
     (T : Std_Hash_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Hash suite (PKG=stdlib.hash)"));

   overriding procedure Register_Tests (T : in out Std_Hash_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Crc32_Vectors'Access, "crc32 vectors");
      Register_Routine
        (T, Test_Crc32_Update_Split'Access, "crc32 Update split + table");
      Register_Routine (T, Test_Crc64_Vectors'Access, "crc64 vectors");
      Register_Routine (T, Test_Adler32_Vectors'Access, "adler32 vectors");
      Register_Routine (T, Test_Fnv32'Access, "fnv 32/32a vectors + API");
      Register_Routine (T, Test_Fnv64'Access, "fnv 64/64a vectors + API");
   end Register_Tests;

   procedure Test_Crc32_Vectors (T : in out
      AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      type Vec is record
         S : Unbounded_String;
         IEEE, Cast, Koop : Unsigned_32;
      end record;
      Vecs : constant array (Positive range <>) of Vec :=
        ((To_Unbounded_String (""), 16#00000000#, 16#00000000#, 16#00000000#),
         (To_Unbounded_String ("123456789"),
          16#CBF43926#, 16#E3069283#, 16#2D3DD0AE#),
         (To_Unbounded_String ("The quick brown fox jumps over the lazy dog"),
          16#414FA339#, 16#22620404#, 16#E021DB90#),
         (To_Unbounded_String ("a"),
          16#E8B7BE43#, 16#C1D04330#, 16#0DA2AA8A#));
   begin
      for V of Vecs loop
         declare
            B : constant Byte_Slice := To_Bytes (To_String (V.S));
         begin
            Assert (Crc32.Checksum_IEEE (B) = V.IEEE,
                    "IEEE(" & To_String (V.S) & ")");
            Assert (Crc32.Checksum (B, Crc32.Make_Table (Crc32.Castagnoli))
                      = V.Cast,
                    "Castagnoli(" & To_String (V.S) & ")");
            Assert (Crc32.Checksum (B, Crc32.Make_Table (Crc32.Koopman))
                      = V.Koop,
                    "Koopman(" & To_String (V.S) & ")");
         end;
      end loop;
   end Test_Crc32_Vectors;

   procedure Test_Crc32_Update_Split (T : in out
      AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Tab : constant Crc32.Table := Crc32.Make_Table (Crc32.IEEE);
   begin
      --  classic table entries: tab(0) = 0, tab(1) = 16#77073096#
      Assert (Tab (0) = 0, "tab(0)");
      Assert (Tab (1) = 16#77073096#, "tab(1)");
      --  incremental Update equals the one-shot checksum
      Assert (Crc32.Update
                (Crc32.Update (0, Tab, To_Bytes ("1234")), Tab,
                 To_Bytes ("56789")) = 16#CBF43926#,
              "split Update");
      --  long input crosses many table lookups (pinned from Go)
      declare
         Long : constant String (1 .. 6000) := (others => 'a');
      begin
         Assert (Crc32.Checksum_IEEE (To_Bytes (Long)) = 16#29A9DF9B#,
                 "6000xa IEEE");
      end;
   end Test_Crc32_Update_Split;

   procedure Test_Crc64_Vectors (T : in out
      AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      type Vec is record
         S : Unbounded_String;
         ECMA, ISO : Unsigned_64;
      end record;
      Vecs : constant array (Positive range <>) of Vec :=
        ((To_Unbounded_String (""),
          16#0000000000000000#, 16#0000000000000000#),
         (To_Unbounded_String ("123456789"),
          16#995DC9BBDF1939FA#, 16#B90956C775A41001#),
         (To_Unbounded_String ("The quick brown fox jumps over the lazy dog"),
          16#5B5EB8C2E54AA1C4#, 16#4EF14E19F4C6E28E#),
         (To_Unbounded_String ("a"),
          16#330284772E652B05#, 16#3420000000000000#));
   begin
      for V of Vecs loop
         declare
            B : constant Byte_Slice := To_Bytes (To_String (V.S));
         begin
            Assert (Crc64.Checksum (B, Crc64.Make_Table (Crc64.ECMA))
                      = V.ECMA,
                    "ECMA(" & To_String (V.S) & ")");
            Assert (Crc64.Checksum (B, Crc64.Make_Table (Crc64.ISO))
                      = V.ISO,
                    "ISO(" & To_String (V.S) & ")");
         end;
      end loop;
   end Test_Crc64_Vectors;

   procedure Test_Adler32_Vectors (T : in out
      AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Adler32.Checksum (To_Bytes ("")) = 16#00000001#, "empty");
      Assert (Adler32.Checksum (To_Bytes ("123456789")) = 16#091E01DE#,
              "123456789");
      Assert (Adler32.Checksum
                (To_Bytes ("The quick brown fox jumps over the lazy dog"))
                = 16#5BDC0FDA#,
              "fox");
      Assert (Adler32.Checksum (To_Bytes ("a")) = 16#00620062#, "a");
      --  6000 bytes crosses the NMAX = 5552 batching boundary
      declare
         Long : constant String (1 .. 6000) := (others => 'a');
      begin
         Assert (Adler32.Checksum (To_Bytes (Long)) = 16#7A4CE1E9#,
                 "6000xa batching");
      end;
   end Test_Adler32_Vectors;

   procedure Test_Fnv32 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      type Vec is record
         S : Unbounded_String;
         A, One : Unsigned_32;  --  FNV-1a, FNV-1
      end record;
      Vecs : constant array (Positive range <>) of Vec :=
        ((To_Unbounded_String (""), 16#811C9DC5#, 16#811C9DC5#),
         (To_Unbounded_String ("123456789"),
          16#BB86B11C#, 16#24148816#),
         (To_Unbounded_String ("The quick brown fox jumps over the lazy dog"),
          16#048FFF90#, 16#E9C86C6E#),
         (To_Unbounded_String ("a"), 16#E40C292C#, 16#050C5D7E#));
   begin
      for V of Vecs loop
         declare
            B : constant Byte_Slice := To_Bytes (To_String (V.S));
            H1 : Fnv.Hash32 := Fnv.New32a;
            H2 : Fnv.Hash32 := Fnv.New32;
         begin
            Fnv.Write (H1, B);
            Fnv.Write (H2, B);
            Assert (Fnv.Sum32 (H1) = V.A, "fnv32a(" & To_String (V.S) & ")");
            Assert (Fnv.Sum32 (H2) = V.One, "fnv32(" & To_String (V.S) & ")");
         end;
      end loop;
      --  multi-chunk Write equals one-shot; Reset returns to the basis;
      --  Sum appends big-endian; Size is 4
      declare
         H : Fnv.Hash32 := Fnv.New32a;
      begin
         Fnv.Write (H, To_Bytes ("1234"));
         Fnv.Write (H, To_Bytes ("56789"));
         Assert (Fnv.Sum32 (H) = 16#BB86B11C#, "split write");
         declare
            S : constant Byte_Slice := Fnv.Sum (H, Byte_Vectors.Empty_Vector);
         begin
            Assert (Byte_Vectors.Length (S) = 4, "Sum length");
            Assert (Byte_Vectors.Element (S, 1) = Character'Val (16#BB#)
                      and then Byte_Vectors.Element (S, 2) = Character'Val (16#86#)
                      and then Byte_Vectors.Element (S, 3) = Character'Val (16#B1#)
                      and then Byte_Vectors.Element (S, 4) = Character'Val (16#1C#),
                    "Sum big-endian bytes");
         end;
         Assert (Fnv.Size (H) = 4, "Size32");
         Fnv.Reset (H);
         Assert (Fnv.Sum32 (H) = 16#811C9DC5#, "Reset");
      end;
   end Test_Fnv32;

   procedure Test_Fnv64 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      type Vec is record
         S : Unbounded_String;
         A, One : Unsigned_64;
      end record;
      Vecs : constant array (Positive range <>) of Vec :=
        ((To_Unbounded_String (""),
          16#CBF29CE484222325#, 16#CBF29CE484222325#),
         (To_Unbounded_String ("123456789"),
          16#06D5573923C6CDFC#, 16#A72FFC362BF916D6#),
         (To_Unbounded_String ("The quick brown fox jumps over the lazy dog"),
          16#F3F9B7F5E7E47110#, 16#A8B2F3117DE37ACE#),
         (To_Unbounded_String ("a"),
          16#AF63DC4C8601EC8C#, 16#AF63BD4C8601B7BE#));
   begin
      for V of Vecs loop
         declare
            B : constant Byte_Slice := To_Bytes (To_String (V.S));
            H1 : Fnv.Hash64 := Fnv.New64a;
            H2 : Fnv.Hash64 := Fnv.New64;
         begin
            Fnv.Write (H1, B);
            Fnv.Write (H2, B);
            Assert (Fnv.Sum64 (H1) = V.A, "fnv64a(" & To_String (V.S) & ")");
            Assert (Fnv.Sum64 (H2) = V.One, "fnv64(" & To_String (V.S) & ")");
         end;
      end loop;
      declare
         H : Fnv.Hash64 := Fnv.New64a;
      begin
         Fnv.Write (H, To_Bytes ("1234"));
         Fnv.Write (H, To_Bytes ("56789"));
         Assert (Fnv.Sum64 (H) = 16#06D5573923C6CDFC#, "split write");
         declare
            S : constant Byte_Slice := Fnv.Sum (H, Byte_Vectors.Empty_Vector);
         begin
            Assert (Byte_Vectors.Length (S) = 8, "Sum length");
            Assert (Byte_Vectors.Element (S, 1) = Character'Val (16#06#)
                      and then Byte_Vectors.Element (S, 8) = Character'Val (16#FC#),
                    "Sum big-endian first/last");
         end;
         Assert (Fnv.Size (H) = 8, "Size64");
         Fnv.Reset (H);
         Assert (Fnv.Sum64 (H) = 16#CBF29CE484222325#, "Reset");
      end;
   end Test_Fnv64;

end Std_Hash_Suite;
