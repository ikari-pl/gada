--  Body of Strings_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded;
with Gada.Std.Strings; use Gada.Std.Strings;

package body Strings_Suite is

   function Is_Upper (C : Character) return Boolean is
     (C in 'A' .. 'Z');

   procedure Check_Slice
     (T    : in out AUnit.Test_Cases.Test_Case'Class;
      Got  : String_Slice;
      Want : array of String)
   is
      use String_Vectors;
   begin
      Assert (Len (Got) = Want'Length,
              "slice length: got" & Integer'Image (Len (Got))
              & ", want" & Integer'Image (Want'Length));
      for I in 1 .. Len (Got) loop
         Assert (Ada.Strings.Unbounded.To_String (Element (Got, I))
              = Want (Want'First + I - 1),
                 "element" & Integer'Image (I) & ": got '"
                 & Ada.Strings.Unbounded.To_String (Element (Got, I))
                 & "', want '" & Want (Want'First + I - 1) & "'");
      end loop;
   end Check_Slice;

   overriding function Name
     (T : Strings_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Strings suite"));

   overriding procedure Register_Tests (T : in out Strings_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Contains'Access,
      "Contains/ContainsAny/ContainsRune");
      Register_Routine (T, Test_Count_Non_Overlapping'Access, "Count is
      non-overlapping");
      Register_Routine (T, Test_Equal_Fold'Access, "EqualFold ASCII");
      Register_Routine (T, Test_Prefix_Suffix'Access, "HasPrefix/HasSuffix");
      Register_Routine (T, Test_Index_Family'Access, "Index family 0-based/-1");
      Register_Routine (T, Test_Last_Index_Family'Access, "LastIndex family");
      Register_Routine (T, Test_Split'Access, "Split");
      Register_Routine (T, Test_Split_N'Access, "SplitN caps");
      Register_Routine (T, Test_Split_After_And_Empty_Sep'Access, "SplitAfter +
      empty sep");
      Register_Routine (T, Test_Join'Access, "Join");
      Register_Routine (T, Test_Fields'Access, "Fields/FieldsFunc");
      Register_Routine (T, Test_Trim_Family'Access, "Trim/TrimLeft/TrimRight");
      Register_Routine (T, Test_Trim_Space_Prefix_Suffix'Access,
      "TrimSpace/TrimPrefix/TrimSuffix");
      Register_Routine (T, Test_Case_And_Map'Access, "ToUpper/ToLower/Map");
      Register_Routine (T, Test_Repeat'Access, "Repeat incl. count 0");
      Register_Routine (T, Test_Replace'Access, "Replace/ReplaceAll incl. N");
      Register_Routine (T, Test_Replacer'Access, "Replacer priority order");
   end Register_Tests;

   procedure Test_Contains (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Contains ("seafood", "foo"), "Contains foo");
      Assert (not Contains ("seafood", "bar"), "not Contains bar");
      Assert (Contains_Any ("seafood", "xfo"), "ContainsAny");
      Assert (not Contains_Any ("seafood", "xyz"), "not ContainsAny");
      Assert (Contains_Rune ("seafood", 'f'), "ContainsRune");
      Assert (not Contains_Rune ("seafood", 'z'), "not ContainsRune");
   end Test_Contains;

   procedure Test_Count_Non_Overlapping (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Count ("aaaa", "aa") = 2, "aaaa/aa counts non-overlapping = 2");
      Assert (Count ("abc", "") = 4, "empty substr = len+1");
      Assert (Count ("abc", "x") = 0, "no match = 0");
   end Test_Count_Non_Overlapping;

   procedure Test_Equal_Fold (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Equal_Fold ("Go", "go"), "EqualFold Go/go");
      Assert (Equal_Fold ("ABC", "abc"), "EqualFold ABC/abc");
      Assert (not Equal_Fold ("Go", "go1"), "length mismatch");
      Assert (not Equal_Fold ("abc", "abd"), "content mismatch");
   end Test_Equal_Fold;

   procedure Test_Prefix_Suffix (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Has_Prefix ("foobar", "foo"), "prefix");
      Assert (not Has_Prefix ("foobar", "bar"), "not prefix");
      Assert (Has_Suffix ("foobar", "bar"), "suffix");
      Assert (not Has_Suffix ("foobar", "foo"), "not suffix");
      Assert (Has_Prefix ("x", ""), "empty prefix is true");
      Assert (Has_Suffix ("x", ""), "empty suffix is true");
   end Test_Prefix_Suffix;

   procedure Test_Index_Family (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Index ("chicken", "ken") = 4, "Index ken = 4 (0-based)");
      Assert (Index ("chicken", "xyz") = -1, "Index missing = -1");
      Assert (Index ("", "") = 0, "Index empty/empty = 0");
      Assert (Index_Any ("chicken", "aeiou") = 2, "IndexAny vowel = 2");
      Assert (Index_Any ("xyz", "aeiou") = -1, "IndexAny none = -1");
      Assert (Index_Byte ("chicken", 'k') = 4, "IndexByte");
      Assert (Index_Rune ("chicken", 'n') = 6, "IndexRune");
   end Test_Index_Family;

   procedure Test_Last_Index_Family (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Last_Index ("chicken", "ken") = 4, "LastIndex");
      Assert (Last_Index ("go go go", "go") = 6, "LastIndex repeated");
      Assert (Last_Index_Any ("chicken", "aeiou") = 6, "LastIndexAny");
      Assert (Last_Index_Byte ("chicken", 'c') = 0, "LastIndexByte");
      Assert (Last_Index ("abc", "xyz") = -1, "LastIndex missing = -1");
   end Test_Last_Index_Family;

   procedure Test_Split (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Check_Slice (T, Split ("a,b,c", ","), (1 => "a", 2 => "b", 3 => "c"));
      Check_Slice (T, Split ("abc", ","), (1 => "abc"));
      Check_Slice (T, Split ("", ","), (1 => ""));
   end Test_Split;

   procedure Test_Split_N (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Check_Slice (T, Split_N ("a,b,c,d", ",", 2), (1 => "a", 2 => "b,c,d"));
      Check_Slice (T, Split_N ("a,b,c", ",", -1), (1 => "a", 2 => "b", 3 =>
      "c"));
      Check_Slice (T, Split_N ("a,b,c", ",", 0), (1 .. 0 => ""));
   end Test_Split_N;

   procedure Test_Split_After_And_Empty_Sep (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Check_Slice (T, Split_After ("a,b", ","), (1 => "a,", 2 => "b"));
      Check_Slice (T, Split ("abc", ""), (1 => "a", 2 => "b", 3 => "c"));
   end Test_Split_After_And_Empty_Sep;

   procedure Test_Join (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Parts : constant String_Slice := Split ("a,b,c", ",");
   begin
      Assert (Join (Parts, "-") = "a-b-c", "Join with dash");
      Assert (Join (Split ("", ","), "-") = "", "Join empty");
   end Test_Join;

   procedure Test_Fields (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Check_Slice (T, Fields ("  a b\tc\n"), (1 => "a", 2 => "b", 3 => "c"));
      Check_Slice (T, Fields (""), (1 .. 0 => ""));
      Check_Slice (T, Fields_Func ("a1b2c", Is_Upper'Access), (1 => "a1b2c"));
   end Test_Fields;

   procedure Test_Trim_Family (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Trim ("xxhixx", "x") = "hi", "Trim cutset");
      Assert (Trim_Left ("xxhixx", "x") = "hixx", "TrimLeft");
      Assert (Trim_Right ("xxhixx", "x") = "xxhi", "TrimRight");
      Assert (Trim ("", "x") = "", "Trim empty");
   end Test_Trim_Family;

   procedure Test_Trim_Space_Prefix_Suffix (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Trim_Space ("  hi\t\n") = "hi", "TrimSpace");
      Assert (Trim_Prefix ("foobar", "foo") = "bar", "TrimPrefix");
      Assert (Trim_Prefix ("foobar", "xxx") = "foobar", "TrimPrefix no-op");
      Assert (Trim_Suffix ("foobar", "bar") = "foo", "TrimSuffix");
   end Test_Trim_Space_Prefix_Suffix;

   procedure Test_Case_And_Map (T : in out AUnit.Test_Cases.Test_Case'Class) is
      function Shout (C : Character) return Character is
        (if C in 'a' .. 'z' then Character'Val (Character'Pos (C) - 32) else C);
   begin
      Assert (To_Upper ("go") = "GO", "ToUpper");
      Assert (To_Lower ("GO") = "go", "ToLower");
      Assert (Map (Shout'Access, "abc1") = "ABC1", "Map");
   end Test_Case_And_Map;

   procedure Test_Repeat (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Repeat ("ab", 3) = "ababab", "Repeat 3");
      Assert (Repeat ("ab", 0) = "", "Repeat 0");
      Assert (Repeat ("", 5) = "", "Repeat empty");
   end Test_Repeat;

   procedure Test_Replace (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Replace ("a-b-c", "-", "+", -1) = "a+b+c", "ReplaceAll");
      Assert (Replace_All ("a-b-c", "-", "+") = "a+b+c", "Replace_All");
      Assert (Replace ("a-b-c", "-", "+", 1) = "a+b-c", "Replace N=1");
      Assert (Replace ("abc", "x", "y", -1) = "abc", "no match unchanged");
   end Test_Replace;

   procedure Test_Replacer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      R : constant Replacer := New_Replacer (Split ("cat,dog,bird,cat", ","));
   begin
      --  pairs: cat→dog, bird→cat; "cat cat" → "dog dog" (priority:
      --  cat before bird doesn't matter here)
      Assert (Replace (R, "cat cat bird") = "dog dog cat", "Replacer replaces
      all");
      Assert (Replace (New_Replacer (Split ("aa,a", ",")), "aaa") = "aa",
      "first-listed wins at a position");
   end Test_Replacer;

end Strings_Suite;
