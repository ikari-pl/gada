--  Body of Strings_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded;
with Gada.Std.Strings; use Gada.Std.Strings;

package body Strings_Suite is

   HT : constant Character := Character'Val (9);   --  tab
   LF : constant Character := Character'Val (10);  --  line feed

   --  Named unconstrained array type (anonymous array parameter types
   --  are not legal Ada); the element is Unbounded_String because plain
   --  String is unconstrained and cannot be an array element type.
   type String_Array is array (Positive range <>)
     of Ada.Strings.Unbounded.Unbounded_String;

   function Shout (C : Character) return Character is
     (if C in 'a' .. 'z'
      then Character'Val (Character'Pos (C) - 32)
      else C);

   function Is_Upper (C : Character) return Boolean is
     (C in 'A' .. 'Z');

   procedure Check_Slice
     (T    : in out AUnit.Test_Cases.Test_Case'Class;
      Got  : String_Slice;
      Want : String_Array)
   is
      use String_Vectors;
   begin
      Assert (Integer (Length (Got)) = Want'Length,
              "slice length: got"
              & Integer'Image (Integer (Length (Got)))
              & ", want" & Integer'Image (Want'Length));
      for I in 1 .. Integer (Length (Got)) loop
         Assert (Ada.Strings.Unbounded.To_String (Element (Got, I))
                 = Ada.Strings.Unbounded.To_String
                     (Want (Want'First + I - 1)),
                 "element" & Integer'Image (I) & ": got '"
                 & Ada.Strings.Unbounded.To_String (Element (Got, I))
                 & "', want '"
                 & Ada.Strings.Unbounded.To_String
                     (Want (Want'First + I - 1)) & "'");
      end loop;
   end Check_Slice;

   overriding function Name
     (T : Strings_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Strings suite"));

   overriding procedure Register_Tests (T : in out Strings_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Contains'Access, "Contains/ContainsAny/ContainsRune");
      Register_Routine
        (T, Test_Count_Non_Overlapping'Access, "Count non-overlapping");
      Register_Routine
        (T, Test_Equal_Fold'Access, "EqualFold ASCII");
      Register_Routine
        (T, Test_Prefix_Suffix'Access, "HasPrefix/HasSuffix");
      Register_Routine
        (T, Test_Index_Family'Access, "Index family 0-based/-1");
      Register_Routine
        (T, Test_Last_Index_Family'Access, "LastIndex family");
      Register_Routine (T, Test_Split'Access, "Split");
      Register_Routine (T, Test_Split_N'Access, "SplitN caps");
      Register_Routine
        (T, Test_Split_After_And_Empty_Sep'Access, "SplitAfter + empty sep");
      Register_Routine (T, Test_Join'Access, "Join");
      Register_Routine (T, Test_Fields'Access, "Fields/FieldsFunc");
      Register_Routine
        (T, Test_Trim_Family'Access, "Trim/TrimLeft/TrimRight");
      Register_Routine
        (T, Test_Trim_Space_Prefix_Suffix'Access,
         "TrimSpace/TrimPrefix/TrimSuffix");
      Register_Routine
        (T, Test_Case_And_Map'Access, "ToUpper/ToLower/Map");
      Register_Routine (T, Test_Repeat'Access, "Repeat incl. count 0");
      Register_Routine
        (T, Test_Replace'Access, "Replace/ReplaceAll incl. N");
      Register_Routine
        (T, Test_Replacer'Access, "Replacer priority order");
      Register_Routine (T, Test_Edges'Access, "Repeat/NewReplacer/old empty");
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
      --  Regression (PR #45 review #5): Latin-1 folding mapped the
      --  UTF-8 lead byte 16#C0# onto 16#E0#, so distinct multi-byte
      --  sequences compared equal. Only ASCII folds now.
      Assert (not Equal_Fold ((1 => Character'Val (16#C0#)),
                              (1 => Character'Val (16#E0#))),
              "bytes >= 16#80# are not case-folded");
      Assert (Equal_Fold ("Caf" & Character'Val (16#C3#)
                            & Character'Val (16#A9#),
                          "CAF" & Character'Val (16#C3#)
                            & Character'Val (16#A9#)),
              "ASCII folds around an intact UTF-8 rune");
   end Test_Equal_Fold;

   procedure Test_Prefix_Suffix (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Has_Prefix ("foobar", "foo"), "prefix");
      Assert (not Has_Prefix ("foobar", "bar"), "not prefix");
      Assert (Has_Suffix ("foobar", "bar"), "suffix");
      Assert (not Has_Suffix ("foobar", "foo"), "not suffix");
      Assert (Has_Prefix ("x", ""), "empty prefix is true");
      Assert (Has_Suffix ("x", ""), "empty suffix is true");
   end Test_Prefix_Suffix;

   procedure Test_Index_Family (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Index ("chicken", "ken") = 4, "Index ken = 4 (0-based)");
      Assert (Index ("chicken", "xyz") = -1, "Index missing = -1");
      Assert (Index ("", "") = 0, "Index empty/empty = 0");
      Assert (Index_Any ("chicken", "aeiou") = 2, "IndexAny vowel = 2");
      Assert (Index_Any ("xyz", "aeiou") = -1, "IndexAny none = -1");
      Assert (Index_Byte ("chicken", 'k') = 4, "IndexByte");
      Assert (Index_Rune ("chicken", 'n') = 6, "IndexRune");
      Assert (Index ("ab", "abc") = -1, "Index sub longer than s = -1");
   end Test_Index_Family;

   procedure Test_Last_Index_Family (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Last_Index ("chicken", "ken") = 4, "LastIndex");
      Assert (Last_Index ("go go go", "go") = 6, "LastIndex repeated");
      Assert (Last_Index_Any ("chicken", "aeiou") = 5, "LastIndexAny");
      Assert (Last_Index_Byte ("chicken", 'c') = 3, "LastIndexByte");
      Assert (Last_Index ("abc", "xyz") = -1, "LastIndex missing = -1");
      Assert (Last_Index ("abc", "") = 3, "LastIndex empty sub = len");
      Assert (Last_Index ("ab", "abc") = -1, "LastIndex sub longer = -1");
      Assert (Last_Index_Any ("abc", "xyz") = -1, "LastIndexAny none = -1");
      Assert (Last_Index_Byte ("abc", 'z') = -1, "LastIndexByte none = -1");
   end Test_Last_Index_Family;

   procedure Test_Split (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Check_Slice (T, Split ("a,b,c", ","),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a"),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String ("b"),
                    3 => Ada.Strings.Unbounded.To_Unbounded_String ("c")));
      Check_Slice
        (T, Split ("abc", ","),
         (1 => Ada.Strings.Unbounded.To_Unbounded_String ("abc")));
      Check_Slice
        (T, Split ("", ","),
         (1 => Ada.Strings.Unbounded.To_Unbounded_String ("")));
      --  Go's genSplit appends the final field unconditionally: a
      --  trailing separator yields a final EMPTY field.
      Check_Slice (T, Split ("a,", ","),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a"),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String ("")));
      Check_Slice (T, Split (",", ","),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String (""),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String ("")));
      Check_Slice (T, Split ("a,,b", ","),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a"),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String (""),
                    3 => Ada.Strings.Unbounded.To_Unbounded_String ("b")));
   end Test_Split;

   procedure Test_Split_N (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Check_Slice (T, Split_N ("a,b,c,d", ",", 2),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a"),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String ("b,c,d")));
      Check_Slice (T, Split_N ("a,b,c", ",", -1),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a"),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String ("b"),
                    3 => Ada.Strings.Unbounded.To_Unbounded_String ("c")));
      Check_Slice (T, Split_N ("a,b,c", ",", 0),
                   (1 .. 0 => Ada.Strings.Unbounded.To_Unbounded_String ("")));
      --  Empty separator splits per byte, capped at N fields.
      Check_Slice (T, Split_N ("abcd", "", 2),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a"),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String ("bcd")));
      Check_Slice (T, Split_N ("a,", ",", -1),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a"),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String ("")));
      Check_Slice (T, Split_N ("", ",", -1),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("")));
   end Test_Split_N;

   procedure Test_Split_After_And_Empty_Sep (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Check_Slice (T, Split_After ("a,b", ","),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a,"),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String ("b")));
      Check_Slice (T, Split ("abc", ""),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a"),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String ("b"),
                    3 => Ada.Strings.Unbounded.To_Unbounded_String ("c")));
      --  Go: if s and sep are both empty, Split returns an empty slice.
      Check_Slice (T, Split ("", ""),
                   (1 .. 0 =>
                      Ada.Strings.Unbounded.To_Unbounded_String ("")));
      Check_Slice (T, Split_After ("a,", ","),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a,"),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String ("")));
   end Test_Split_After_And_Empty_Sep;

   procedure Test_Join (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Parts : constant String_Slice := Split ("a,b,c", ",");
   begin
      Assert (Join (Parts, "-") = "a-b-c", "Join with dash");
      Assert (Join (Split ("", ","), "-") = "", "Join empty");
   end Test_Join;

   procedure Test_Fields (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Check_Slice (T, Fields ("  a b" & HT & "c" & LF),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a"),
                    2 => Ada.Strings.Unbounded.To_Unbounded_String ("b"),
                    3 => Ada.Strings.Unbounded.To_Unbounded_String ("c")));
      Check_Slice
        (T, Fields (""),
         (1 .. 0 => Ada.Strings.Unbounded.To_Unbounded_String ("")));
      Check_Slice (T, Fields_Func ("a1b2c", Is_Upper'Access),
                   (1 => Ada.Strings.Unbounded.To_Unbounded_String ("a1b2c")));
   end Test_Fields;

   procedure Test_Trim_Family (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Trim ("xxhixx", "x") = "hi", "Trim cutset");
      Assert (Trim_Left ("xxhixx", "x") = "hixx", "TrimLeft");
      Assert (Trim_Right ("xxhixx", "x") = "xxhi", "TrimRight");
      Assert (Trim ("", "x") = "", "Trim empty");
   end Test_Trim_Family;

   procedure Test_Trim_Space_Prefix_Suffix (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Trim_Space ("  hi" & HT & LF) = "hi", "TrimSpace");
      Assert (Trim_Prefix ("foobar", "foo") = "bar", "TrimPrefix");
      Assert (Trim_Prefix ("foobar", "xxx") = "foobar", "TrimPrefix no-op");
      Assert (Trim_Suffix ("foobar", "bar") = "foo", "TrimSuffix");
      Assert (Trim_Suffix ("foobar", "xxx") = "foobar",
              "TrimSuffix no-op");
   end Test_Trim_Space_Prefix_Suffix;

   procedure Test_Case_And_Map (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (To_Upper ("go") = "GO", "ToUpper");
      Assert (To_Lower ("GO") = "go", "ToLower");
      --  Regression (PR #45 review #5): UTF-8 must survive case mapping
      --  (Go: ToLower("Café") = "café", ToUpper("€uro") = "€URO").
      declare
         E_Acute : constant String :=
           (Character'Val (16#C3#), Character'Val (16#A9#));
         Euro    : constant String :=
           (Character'Val (16#E2#), Character'Val (16#82#),
            Character'Val (16#AC#));
      begin
         Assert (To_Lower ("Caf" & E_Acute) = "caf" & E_Acute,
                 "ToLower keeps UTF-8 bytes");
         Assert (To_Upper (Euro & "uro") = Euro & "URO",
                 "ToUpper keeps UTF-8 bytes");
         Assert (To_Upper ("Caf" & E_Acute) = "CAF" & E_Acute,
                 "ToUpper leaves non-ASCII letters unmapped (v1)");
      end;
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
      --  Empty old: insert New before each byte and at the end, up to
      --  N times; N = 0 returns S unchanged (Go-verified).
      Assert (Replace ("abc", "", "X", 2) = "XaXbc", "empty old N=2");
      Assert (Replace ("abc", "", "X", 0) = "abc", "empty old N=0");
      Assert (Replace ("abc", "", "X", -1) = "XaXbXcX", "empty old all");
      Assert (Replace ("", "", "X", -1) = "X", "empty old empty s");
      Assert (Replace ("ab", "", "X", 1) = "Xab", "empty old N=1");
   end Test_Replace;

   procedure Test_Replacer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      R : constant Replacer :=
        New_Replacer (Split ("cat,dog,bird,cat", ","));
   begin
      --  pairs: cat→dog, bird→cat
      Assert (Replace (R, "cat cat bird") = "dog dog cat",
              "Replacer replaces all");
      Assert (Replace (New_Replacer (Split ("aa,a", ",")), "aaa") = "aa",
              "first-listed wins at a position");
      --  Go: NewReplacer() with no pairs is a valid no-op replacer.
      --  Split ("", "") is the empty slice, so this builds zero pairs.
      Assert (Replace (New_Replacer (Split ("", "")), "abc") = "abc",
              "empty pair list is a no-op");
      --  Regression (PR #45 review #11): Go accepts an empty old string
      --  (only an odd argument count panics); it matches at every
      --  position and at the end, once per position. Go-verified.
      Assert (Replace (New_Replacer (Split (",X", ",")), "ab") = "XaXbX",
              "empty old matches between every byte and at the end");
      Assert (Replace (New_Replacer (Split (",X", ",")), "") = "X",
              "empty old on empty input");
      Assert (Replace (New_Replacer (Split (",X,a,A", ",")), "ab")
                = "XAXbX", "empty old first, then a at the same spot");
      Assert (Replace (New_Replacer (Split ("a,A,,X", ",")), "ab")
                = "AXbX", "a wins over a later empty old");
      Assert (Replace (New_Replacer (Split ("a,1,,-,bc,2", ",")), "abcd")
                = "1-2-d-", "mixed empty and non-empty olds");
   end Test_Replacer;

   procedure Test_Edges (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      --  Repeat with a negative count raises (Go panics).
      begin
         declare
            S : constant String := Repeat ("a", -1);
         begin
            Assert (S'Length = 0, "Repeat(-1) must raise");
         end;
      exception
         when Constraint_Error =>
            null;  --  expected
      end;
      --  New_Replacer with an odd pair count raises (Go panics).
      begin
         declare
            R : constant Replacer :=
              New_Replacer (Split ("a,b,c", ","));
            pragma Unreferenced (R);
         begin
            Assert (False, "New_Replacer(odd) must raise");
         end;
      exception
         when Constraint_Error =>
            null;  --  expected
      end;
      --  Empty old string inserts between every byte and at the end.
      Assert (Replace ("abc", "", "-", -1) = "-a-b-c-",
              "Replace empty old");
      --  A default Replacer (no pairs) is the identity.
      declare
         R : Replacer;
      begin
         Assert (Replace (R, "unchanged") = "unchanged",
                 "empty Replacer is identity");
      end;
   end Test_Edges;

end Strings_Suite;
