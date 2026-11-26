--  Body of Bytes_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with Ada.Containers;
with AUnit.Assertions; use AUnit.Assertions;

with Gada.Std.Bytes; use Gada.Std.Bytes;

use type Ada.Containers.Count_Type;

package body Bytes_Suite is

   overriding function Name
     (T : Bytes_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Bytes suite"));

   overriding procedure Register_Tests (T : in out Bytes_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Conversions'Access, "To_Bytes/To_String");
      Register_Routine (T, Test_Equal_Compare'Access, "Equal/Compare");
      Register_Routine (T, Test_Index_Contains'Access, "Index/Contains");
      Register_Routine (T, Test_Prefix_Suffix'Access, "HasPrefix/HasSuffix");
      Register_Routine (T, Test_Split_Join'Access, "Split/Join");
      Register_Routine (T, Test_Buffer'Access, "Buffer write/read/reset");
      Register_Routine (T, Test_Reader'Access, "Reader read/readbyte/len");
      Register_Routine (T, Test_Edges'Access, "Compare/Contains edges");
   end Register_Tests;

   procedure Test_Conversions (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (To_String (To_Bytes ("hello")) = "hello", "round-trip");
      Assert (To_String (To_Bytes ("")) = "", "empty round-trip");
      --  make([]byte, N): N zero bytes
      declare
         B : constant Byte_Slice := New_Bytes (4);
      begin
         Assert (Byte_Vectors.Length (B) = 4, "New_Bytes length");
         Assert (To_String (B) = Character'Val (0) & Character'Val (0)
                 & Character'Val (0) & Character'Val (0),
                 "New_Bytes zero-filled");
      end;
      Assert (Byte_Vectors.Is_Empty (New_Bytes (0)), "New_Bytes 0 empty");
      Assert (Byte_Vectors.Length (To_Bytes ("abc")) = 3, "length 3");
   end Test_Conversions;

   procedure Test_Equal_Compare (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Equal (To_Bytes ("abc"), To_Bytes ("abc")), "Equal abc");
      Assert (not Equal (To_Bytes ("abc"), To_Bytes ("abd")), "not Equal");
      Assert (not Equal (To_Bytes ("abc"), To_Bytes ("ab")), "length");
      Assert (Compare (To_Bytes ("abc"), To_Bytes ("abd")) = -1, "a<b");
      Assert (Compare (To_Bytes ("abd"), To_Bytes ("abc")) = 1, "a>b");
      Assert (Compare (To_Bytes ("ab"), To_Bytes ("abc")) = -1, "prefix");
      Assert (Compare (To_Bytes ("abc"), To_Bytes ("abc")) = 0, "equal");
   end Test_Equal_Compare;

   procedure Test_Index_Contains (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Index (To_Bytes ("chicken"), To_Bytes ("ken")) = 4, "0-based");
      Assert (Index (To_Bytes ("chicken"), To_Bytes ("xyz")) = -1, "-1");
      Assert (Index (To_Bytes ("abc"), To_Bytes ("")) = 0, "empty sub = 0");
      Assert (Contains (To_Bytes ("seafood"), To_Bytes ("foo")), "Contains");
      Assert (not Contains (To_Bytes ("seafood"), To_Bytes ("bar")),
              "not Contains");
      Assert (Contains (To_Bytes ("abc"), To_Bytes ("")), "Contains empty");
   end Test_Index_Contains;

   procedure Test_Prefix_Suffix (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Has_Prefix (To_Bytes ("foobar"), To_Bytes ("foo")), "prefix");
      Assert (not Has_Prefix (To_Bytes ("foobar"), To_Bytes ("bar")),
              "not prefix");
      Assert (Has_Prefix (To_Bytes ("x"), To_Bytes ("")), "empty prefix");
      Assert (Has_Suffix (To_Bytes ("foobar"), To_Bytes ("bar")), "suffix");
      Assert (not Has_Suffix (To_Bytes ("foobar"), To_Bytes ("foo")),
              "not suffix");
      Assert (Has_Suffix (To_Bytes ("x"), To_Bytes ("")), "empty suffix");
      Assert (not Has_Prefix (To_Bytes ("x"), To_Bytes ("xx")),
              "prefix longer than s");
   end Test_Prefix_Suffix;

   procedure Test_Split_Join (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Parts : constant Byte_Slice_List :=
        Split (To_Bytes ("a,b,c"), To_Bytes (","));
   begin
      Assert (Integer (Byte_Slice_Vectors.Length (Parts)) = 3, "3 parts");
      Assert (To_String (Byte_Slice_Vectors.Element (Parts, 1)) = "a",
              "part 1");
      Assert (To_String (Byte_Slice_Vectors.Element (Parts, 3)) = "c",
              "part 3");
      Assert (Integer (Byte_Slice_Vectors.Length
                (Split (To_Bytes (""), To_Bytes (",")))) = 1,
              "empty s gives one empty part");
      Assert (Integer (Byte_Slice_Vectors.Length
                (Split (To_Bytes ("abc"), To_Bytes ("")))) = 3,
              "empty sep splits per byte");
      Assert (To_String (Join (Parts, To_Bytes ("-"))) = "a-b-c",
              "Join with dash");
      Assert (To_String (Join (Split (To_Bytes (""), To_Bytes (",")),
                               To_Bytes ("-"))) = "",
              "Join of one empty part");
   end Test_Split_Join;

   procedure Test_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      B   : Buffer;
      Buf : String (1 .. 8);
      N   : Natural;
   begin
      Assert (Len (B) = 0, "fresh buffer empty");
      Write_String (B, "hello");
      Write_Byte (B, ' ');
      Write (B, To_Bytes ("world"));
      Assert (Len (B) = 11, "Len after writes");
      Assert (To_String (B) = "hello world", "To_String (b.String())");
      Assert (To_String (Bytes (B)) = "hello world", "Bytes");
      Read (B, Buf, N);
      Assert (N = 8 and Buf = "hello wo", "Read fills buffer");
      Assert (Len (B) = 3, "Len after read");
      Assert (To_String (B) = "rld", "unread portion");
      Read (B, Buf, N);
      Assert (N = 3 and Buf (1 .. 3) = "rld", "Read remainder");
      Read (B, Buf, N);
      Assert (N = 0, "Read at end gives N = 0 (EOF)");
      Reset (B);
      Assert (Len (B) = 0 and To_String (B) = "", "Reset");
   end Test_Buffer;

   procedure Test_Reader (T : in out AUnit.Test_Cases.Test_Case'Class) is
      R   : Reader := New_Reader (To_Bytes ("data"));
      Buf : String (1 .. 2);
      N   : Natural;
      C   : Character;
      Ok  : Boolean;
   begin
      Assert (Len (R) = 4, "fresh reader Len");
      Read (R, Buf, N);
      Assert (N = 2 and Buf = "da", "Read 2");
      Read_Byte (R, C, Ok);
      Assert (Ok and C = 't', "Read_Byte t");
      Assert (Len (R) = 1, "Len after reads");
      Read_Byte (R, C, Ok);
      Assert (Ok and C = 'a', "Read_Byte a");
      Read_Byte (R, C, Ok);
      Assert (not Ok, "Read_Byte at end fails");
      Reset (R);
      Assert (Len (R) = 4, "Reset restores");
   end Test_Reader;

   procedure Test_Edges (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Compare (To_Bytes ("b"), To_Bytes ("a")) = 1, "Compare gt");
      Assert (Compare (To_Bytes ("a"), To_Bytes ("a")) = 0, "Compare eq");
      Assert (not Contains (To_Bytes ("abc"), To_Bytes ("z")),
              "Contains missing");
      Assert (Index (To_Bytes ("abc"), To_Bytes ("z")) = -1, "Index -1");
      Assert (Compare (To_Bytes ("abc"), To_Bytes ("ab")) = 1,
              "Compare longer = 1");
      Assert (not Has_Suffix (To_Bytes ("ab"), To_Bytes ("abc")),
              "HasSuffix suffix longer than s = False");
   end Test_Edges;

end Bytes_Suite;
