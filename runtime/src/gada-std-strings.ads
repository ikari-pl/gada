--  Gada.Std.Strings — the Go `strings` package, ported (Phase 5 wave 1).
--
--  Go strings are byte sequences; v1 of this port treats Ada Strings the
--  same way (byte = Character), so the rune-oriented functions
--  (Contains_Rune, Index_Rune, …) operate per byte. UTF-8-aware rune
--  handling is a documented limitation (docs/imperfections.md).
--
--  Index-returning functions keep Go's 0-based, -1-not-found contract
--  (Integer, not Natural), so transpiled Go comparisons against -1 work
--  unchanged. Split/Fields/Join use the same Slices_Of_String
--  instantiation the compiler emits for Go []string, so values flow
--  between transpiled code and this package without conversion.

with Ada.Strings.Unbounded;
with Gada.Core.Slices;

package Gada.Std.Strings is

   --  One instantiation of the slice generic per element type; the
   --  compiler emits the identical `Slices_Of_String` instantiation for
   --  Go `[]string`, and two instantiations of a generic with the same
   --  actuals are the same type (RM 12.3), so no conversion is needed.
   --  Element type is Unbounded_String (definite — plain String is
   --  unconstrained and cannot be a slice element). The compiler emits
   --  the identical Slices_Of_String instantiation for Go []string.
   package String_Slices is new Gada.Core.Slices
     (Element_Type => Ada.Strings.Unbounded.Unbounded_String);

   subtype String_Slice is String_Slices.Slice;

   --  Character predicate/transform callbacks (Go's func(rune) bool /
   --  func(rune) rune, byte-wise in v1).
   type Char_Predicate is access function (C : Character) return Boolean;
   type Char_Mapping   is access function (C : Character) return Character;

   ---------------------------------------------------------------
   --  Predicates
   ---------------------------------------------------------------

   function Contains (S, Substr : String) return Boolean;
   function Contains_Any (S, Chars : String) return Boolean;
   function Contains_Rune (S : String; R : Character) return Boolean;
   function Count (S, Substr : String) return Natural;
   function Equal_Fold (A, B : String) return Boolean;
   function Has_Prefix (S, Prefix : String) return Boolean;
   function Has_Suffix (S, Suffix : String) return Boolean;

   ---------------------------------------------------------------
   --  Indexing (0-based, -1 = not found — Go's contract)
   ---------------------------------------------------------------

   function Index (S, Substr : String) return Integer;
   function Index_Any (S, Chars : String) return Integer;
   function Index_Byte (S : String; C : Character) return Integer;
   function Index_Rune (S : String; R : Character) return Integer;
   function Last_Index (S, Substr : String) return Integer;
   function Last_Index_Any (S, Chars : String) return Integer;
   function Last_Index_Byte (S : String; C : Character) return Integer;

   ---------------------------------------------------------------
   --  Split / Join / Fields
   ---------------------------------------------------------------

   --  Split on Sep (empty Sep splits into single bytes in v1, matching
   --  Go's per-rune split for ASCII). Split_N with N < 0 = all fields,
   --  N = 0 = empty slice, N > 0 = at most N fields (last holds the
   --  remainder). Split_After keeps the separator on each field.
   function Split (S, Sep : String) return String_Slice;
   function Split_N (S, Sep : String; N : Integer) return String_Slice;
   function Split_After (S, Sep : String) return String_Slice;
   function Join (Elems : String_Slice; Sep : String) return String;
   function Fields (S : String) return String_Slice;
   function Fields_Func (S : String; F : Char_Predicate) return String_Slice;

   ---------------------------------------------------------------
   --  Trim
   ---------------------------------------------------------------

   function Trim (S, Cutset : String) return String;
   function Trim_Left (S, Cutset : String) return String;
   function Trim_Right (S, Cutset : String) return String;
   function Trim_Space (S : String) return String;
   function Trim_Prefix (S, Prefix : String) return String;
   function Trim_Suffix (S, Suffix : String) return String;
   function Trim_Func (S : String; F : Char_Predicate) return String;

   ---------------------------------------------------------------
   --  Case / mapping
   ---------------------------------------------------------------

   function To_Upper (S : String) return String;
   function To_Lower (S : String) return String;
   function Map (Mapping : Char_Mapping; S : String) return String;

   ---------------------------------------------------------------
   --  Repeat / Replace / Replacer
   ---------------------------------------------------------------

   function Repeat (S : String; Count : Integer) return String;
   function Replace (S, Old, New_Text : String; N : Integer) return String;
   function Replace_All (S, Old, New_Text : String) return String;

   type Replacer is private;
   --  New_Replacer takes a flat old,new,old,new,… slice (Go's
   --  variadic oldnew ...string); odd length raises Constraint_Error.
   function New_Replacer (Oldnew : String_Slice) return Replacer;
   function Replace (R : Replacer; S : String) return String;

private

   type Pair is record
      Old, New_Text : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Pair_Array is array (Positive range <>) of Pair;
   type Pair_Array_Access is access Pair_Array;

   type Replacer is record
      Pairs : Pair_Array_Access;
   end record;

end Gada.Std.Strings;
