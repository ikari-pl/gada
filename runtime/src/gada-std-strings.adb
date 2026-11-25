--  Body of Gada.Std.Strings — see spec for the Go-semantics contract.
--
--  All functions are byte-wise over Ada String (v1 limitation: no
--  UTF-8 rune decoding — see docs/imperfections.md). Results are built
--  with Unbounded_String and returned as String via To_String; the
--  caller owns the (GC-managed) heap block.

with Ada.Characters.Handling;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Gada.Std.Strings is

   use Ada.Characters.Handling;

   --  Go's unicode.IsSpace for ASCII: space, HT, LF, VT, FF, CR.
   function Is_Go_Space (C : Character) return Boolean is
     (C = ' ' or else C = ASCII.HT or else C = ASCII.LF
      or else C = ASCII.VT or else C = ASCII.FF or else C = ASCII.CR);

   function In_Set (C : Character; Set_S : String) return Boolean is
   begin
      for I in Set_S'Range loop
         if Set_S (I) = C then
            return True;
         end if;
      end loop;
      return False;
   end In_Set;

   ---------------------------------------------------------------
   --  Predicates
   ---------------------------------------------------------------

   function Contains (S, Substr : String) return Boolean is
     (Index (S, Substr) >= 0);

   function Contains_Any (S, Chars : String) return Boolean is
     (Index_Any (S, Chars) >= 0);

   function Contains_Rune (S : String; R : Character) return Boolean is
     (Index_Byte (S, R) >= 0);

   function Count (S, Substr : String) return Natural is
   begin
      if Substr'Length = 0 then
         --  Go: Count with empty substr = rune count + 1; v1: byte
         --  count + 1.
         return S'Length + 1;
      end if;
      declare
         N     : Natural := 0;
         Start : Integer := S'First;
      begin
         while Start <= S'Last - Substr'Length + 1 loop
            if S (Start .. Start + Substr'Length - 1) = Substr then
               N := N + 1;
               Start := Start + Substr'Length;  --  non-overlapping
            else
               Start := Start + 1;
            end if;
         end loop;
         return N;
      end;
   end Count;

   function Equal_Fold (A, B : String) return Boolean is
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for I in 0 .. A'Length - 1 loop
         if To_Lower (A (A'First + I)) /= To_Lower (B (B'First + I)) then
            return False;
         end if;
      end loop;
      return True;
   end Equal_Fold;

   function Has_Prefix (S, Prefix : String) return Boolean is
     (Prefix'Length <= S'Length
      and then S (S'First .. S'First + Prefix'Length - 1) = Prefix);

   function Has_Suffix (S, Suffix : String) return Boolean is
     (Suffix'Length <= S'Length
      and then S (S'Last - Suffix'Length + 1 .. S'Last) = Suffix);

   ---------------------------------------------------------------
   --  Indexing (0-based, -1 = not found)
   ---------------------------------------------------------------

   function Index (S, Substr : String) return Integer is
   begin
      if Substr'Length = 0 then
         return 0;
      end if;
      if Substr'Length > S'Length then
         return -1;
      end if;
      for I in S'First .. S'Last - Substr'Length + 1 loop
         if S (I .. I + Substr'Length - 1) = Substr then
            return I - S'First;
         end if;
      end loop;
      return -1;
   end Index;

   function Index_Any (S, Chars : String) return Integer is
   begin
      for I in S'Range loop
         if In_Set (S (I), Chars) then
            return I - S'First;
         end if;
      end loop;
      return -1;
   end Index_Any;

   function Index_Byte (S : String; C : Character) return Integer is
   begin
      for I in S'Range loop
         if S (I) = C then
            return I - S'First;
         end if;
      end loop;
      return -1;
   end Index_Byte;

   function Index_Rune (S : String; R : Character) return Integer is
     (Index_Byte (S, R));

   function Last_Index (S, Substr : String) return Integer is
   begin
      if Substr'Length = 0 then
         return S'Length;
      end if;
      if Substr'Length > S'Length then
         return -1;
      end if;
      for I in reverse S'First .. S'Last - Substr'Length + 1 loop
         if S (I .. I + Substr'Length - 1) = Substr then
            return I - S'First;
         end if;
      end loop;
      return -1;
   end Last_Index;

   function Last_Index_Any (S, Chars : String) return Integer is
   begin
      for I in reverse S'Range loop
         if In_Set (S (I), Chars) then
            return I - S'First;
         end if;
      end loop;
      return -1;
   end Last_Index_Any;

   function Last_Index_Byte (S : String; C : Character) return Integer is
   begin
      for I in reverse S'Range loop
         if S (I) = C then
            return I - S'First;
         end if;
      end loop;
      return -1;
   end Last_Index_Byte;

   ---------------------------------------------------------------
   --  Split / Join / Fields
   ---------------------------------------------------------------

   --  Split core: appends each field to Acc. Empty Sep splits into
   --  single bytes (v1: bytes, not runes).
   procedure Split_Into
     (Acc : in out String_Slice; S, Sep : String; After : Boolean) is
      use String_Slices;
   begin
      if S'Length = 0 then
         --  Go: Split("", sep) = [""] — one empty field, not empty.
         Acc := Append (Acc, "");
         return;
      end if;
      if Sep'Length = 0 then
         for I in S'Range loop
            Acc := Append (Acc, S (I .. I));
         end loop;
         return;
      end if;
      declare
         Start : Integer := S'First;
         I     : Integer;
      begin
         while Start <= S'Last loop
            I := Index (S (Start .. S'Last), Sep);
            if I < 0 then
               Acc := Append (Acc, S (Start .. S'Last));
               return;
            end if;
            --  I is relative to S(Start..); absolute position:
            declare
               Pos : constant Integer := Start + I;
            begin
               if After then
                  Acc := Append (Acc, S (Start .. Pos + Sep'Length - 1));
               else
                  Acc := Append (Acc, S (Start .. Pos - 1));
               end if;
               Start := Pos + Sep'Length;
            end;
         end loop;
      end;
   end Split_Into;

   function Split (S, Sep : String) return String_Slice is
      Acc : String_Slice := String_Slices.Empty;
   begin
      Split_Into (Acc, S, Sep, After => False);
      return Acc;
   end Split;

   function Split_After (S, Sep : String) return String_Slice is
      Acc : String_Slice := String_Slices.Empty;
   begin
      Split_Into (Acc, S, Sep, After => True);
      return Acc;
   end Split_After;

   function Split_N (S, Sep : String; N : Integer) return String_Slice is
      use String_Slices;
      Acc : String_Slice := Empty;
   begin
      if N = 0 then
         return Acc;
      end if;
      if Sep'Length = 0 then
         --  per-byte split, capped at N fields (last holds the rest)
         for I in S'Range loop
            if N > 0 and then Len (Acc) = N - 1 then
               Acc := Append (Acc, S (I .. S'Last));
               return Acc;
            end if;
            Acc := Append (Acc, S (I .. I));
         end loop;
         return Acc;
      end if;
      if S'Length = 0 then
         Acc := Append (Acc, "");
         return Acc;
      end if;
      declare
         Start : Integer := S'First;
      begin
         while Start <= S'Last and then (N < 0 or else Len (Acc) < N - 1) loop
            declare
               I   : constant Integer := Index (S (Start .. S'Last), Sep);
               Pos : constant Integer := Start + I;
            begin
               if I < 0 then
                  Acc := Append (Acc, S (Start .. S'Last));
                  return Acc;
               end if;
               Acc := Append (Acc, S (Start .. Pos - 1));
               Start := Pos + Sep'Length;
            end;
         end loop;
         if Start <= S'Last then
            Acc := Append (Acc, S (Start .. S'Last));
         end if;
         return Acc;
      end;
   end Split_N;

   function Join (Elems : String_Slice; Sep : String) return String is
      use String_Slices;
      B : Unbounded_String;
   begin
      for I in 1 .. Len (Elems) loop
         if I > 1 then
            Append (B, Sep);
         end if;
         Append (B, Element (Elems, I));
      end loop;
      return To_String (B);
   end Join;

   function Fields_Func (S : String; F : Char_Predicate) return String_Slice is
      use String_Slices;
      Acc   : String_Slice := Empty;
      Start : Integer := S'First;
      I     : Integer := S'First;
   begin
      while I <= S'Last + 1 loop
         if I > S'Last or else F (S (I)) then
            if I > Start then
               Acc := Append (Acc, S (Start .. I - 1));
            end if;
            Start := I + 1;
         end if;
         I := I + 1;
      end loop;
      return Acc;
   end Fields_Func;

   function Fields (S : String) return String_Slice is
     (Fields_Func (S, Is_Go_Space'Access));

   ---------------------------------------------------------------
   --  Trim
   ---------------------------------------------------------------

   function Trim_Left (S, Cutset : String) return String is
      I : Integer := S'First;
   begin
      while I <= S'Last and then In_Set (S (I), Cutset) loop
         I := I + 1;
      end loop;
      return S (I .. S'Last);
   end Trim_Left;

   function Trim_Right (S, Cutset : String) return String is
      I : Integer := S'Last;
   begin
      while I >= S'First and then In_Set (S (I), Cutset) loop
         I := I - 1;
      end loop;
      return S (S'First .. I);
   end Trim_Right;

   function Trim (S, Cutset : String) return String is
     (Trim_Right (Trim_Left (S, Cutset), Cutset));

   function Trim_Space (S : String) return String is
     (Trim_Func (S, Is_Go_Space'Access));

   function Trim_Prefix (S, Prefix : String) return String is
     (if Has_Prefix (S, Prefix)
      then S (S'First + Prefix'Length .. S'Last)
      else S);

   function Trim_Suffix (S, Suffix : String) return String is
     (if Has_Suffix (S, Suffix)
      then S (S'First .. S'Last - Suffix'Length)
      else S);

   function Trim_Func (S : String; F : Char_Predicate) return String is
      L : Integer := S'First;
      R : Integer := S'Last;
   begin
      while L <= R and then F (S (L)) loop
         L := L + 1;
      end loop;
      while R >= L and then F (S (R)) loop
         R := R - 1;
      end loop;
      return S (L .. R);
   end Trim_Func;

   ---------------------------------------------------------------
   --  Case / mapping
   ---------------------------------------------------------------

   function To_Upper (S : String) return String is
      R : String (S'Range);
   begin
      for I in S'Range loop
         R (I) := To_Upper (S (I));
      end loop;
      return R;
   end To_Upper;

   function To_Lower (S : String) return String is
      R : String (S'Range);
   begin
      for I in S'Range loop
         R (I) := To_Lower (S (I));
      end loop;
      return R;
   end To_Lower;

   function Map (Mapping : Char_Mapping; S : String) return String is
      R : String (S'Range);
   begin
      for I in S'Range loop
         R (I) := Mapping (S (I));
      end loop;
      return R;
   end Map;

   ---------------------------------------------------------------
   --  Repeat / Replace / Replacer
   ---------------------------------------------------------------

   function Repeat (S : String; Count : Integer) return String is
   begin
      if Count < 0 then
         raise Constraint_Error with "strings.Repeat: negative count";
      end if;
      if Count = 0 or else S'Length = 0 then
         return "";
      end if;
      declare
         B : Unbounded_String;
      begin
         for I in 1 .. Count loop
            Append (B, S);
         end loop;
         return To_String (B);
      end;
   end Repeat;

   function Replace (S, Old, New : String; N : Integer) return String is
      B     : Unbounded_String;
      Start : Integer := S'First;
   begin
      if Old'Length = 0 then
         --  Go: empty old inserts New before every byte and at the end,
         --  up to N times (N < 0 = all).
         declare
            Done : Integer := 0;
         begin
            for I in S'Range loop
               exit when N >= 0 and then Done = N;
               Append (B, New);
               Done := Done + 1;
               Append (B, S (I .. I));
            end loop;
            if N < 0 or else Done < N then
               Append (B, New);
            end if;
            return To_String (B);
         end;
      end if;
      loop
         exit when N = 0;
         declare
            I   : constant Integer := Index (S (Start .. S'Last), Old);
            Pos : constant Integer := Start + I;
         begin
            if I < 0 then
               Append (B, S (Start .. S'Last));
               return To_String (B);
            end if;
            Append (B, S (Start .. Pos - 1));
            Append (B, New);
            Start := Pos + Old'Length;
            if N > 0 then
               N := N - 1;
            end if;
         end;
      end loop;
   end Replace;

   function Replace_All (S, Old, New : String) return String is
     (Replace (S, Old, New, -1));

   function New_Replacer (Oldnew : String_Slice) return Replacer is
      use String_Slices;
   begin
      if Len (Oldnew) mod 2 /= 0 then
         raise Constraint_Error
           with "strings.New_Replacer: odd number of strings";
      end if;
      declare
         N     : constant Positive := Len (Oldnew) / 2;
         Pairs : constant Pair_Array (1 .. N) :=
           (for I in 1 .. N =>
              Pair'(Old => To_Unbounded_String (Element (Oldnew, 2 * I - 1)),
                    New => To_Unbounded_String (Element (Oldnew, 2 * I))));
      begin
         return Replacer'(Pairs => new Pair_Array'(Pairs));
      end;
   end New_Replacer;

   function Replace (R : Replacer; S : String) return String is
      B     : Unbounded_String;
      Start : Integer := S'First;
   begin
      if R.Pairs = null then
         return S;
      end if;
      while Start <= S'Last loop
         --  Leftmost match; on ties the earlier pair in the list wins
         --  (Go's priority rule).
         declare
            Best_Pos : Integer := -1;
            Best_I   : Positive := 1;
         begin
            for I in R.Pairs'Range loop
               declare
                  Old : constant String := To_String (R.Pairs (I).Old);
               begin
                  --  First-listed pair wins at a position (Go's
                  --  priority rule); Best_Pos stays < 0 until the
                  --  first match at this Start.
                  if Best_Pos < 0
                    and then Old'Length > 0
                    and then Start + Old'Length - 1 <= S'Last
                    and then S (Start .. Start + Old'Length - 1) = Old
                  then
                     Best_Pos := Start;
                     Best_I := I;
                  end if;
               end;
            end loop;
            if Best_Pos < 0 then
               Append (B, S (Start .. S'Last));
               return To_String (B);
            end if;
            declare
               Old : constant String := To_String (R.Pairs (Best_I).Old);
            begin
               Append (B, S (Start .. Best_Pos - 1));
               Append (B, To_String (R.Pairs (Best_I).New));
               Start := Best_Pos + Old'Length;
            end;
         end;
      end loop;
      return To_String (B);
   end Replace;

end Gada.Std.Strings;
