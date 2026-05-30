--  Gada.Core.Slices body — see spec for design notes.
--
--  Element access uses an Ada 2022 address-overlay pattern:
--
--     A : Element_Array (1 .. S.Capacity)
--       with Address => S.Buf, Import => True;
--
--  This declares a constrained instance of an unconstrained array
--  type at the slice's backing address with no implicit
--  initialisation. At -O2 GNAT compiles indexing through `A` to a
--  single base+offset load — no per-call allocation, no copy. The
--  bounds-check on `A (Index)` is elided when the caller's Pre
--  contract already proved Index <= S.Length.
--
--  All grow paths copy through libc memmove (pragma Import below):
--  libgc backing is byte-addressable and may be unaligned at the
--  per-element level for non-power-of-two element sizes, so memmove
--  is the safe primitive. memmove is roughly 1.5-2x slower than a
--  hand-rolled SIMD copy; for the v1 runtime that is the right
--  trade — we trade a constant factor for never having to debug a
--  copy bug. ADR-0006 §"Named exceptions" documents the trade.

with System.Storage_Elements;
with Gada.Core.Memory;

package body Gada.Core.Slices is

   use System.Storage_Elements;
   use type System.Address;

   --  Element size in storage units (= bytes on every supported
   --  target). Object_Size is the in-storage size including any
   --  padding for alignment, which is what we want for arrays.
   --  Element_Type'Size is the value size, which would be wrong.
   Element_Bytes : constant Storage_Count :=
     Storage_Count (Element_Type'Object_Size / 8);

   --  libc memmove for grow-path block copies. libgc-allocated
   --  regions are byte-addressable; memmove handles
   --  unaligned/overlapping copies safely.
   procedure Memmove
     (Dst, Src : System.Address; N : Storage_Count);
   pragma Import (C, Memmove, "memmove");

   procedure Allocate_Backing
     (S : in out Slice; Capacity : Natural);
   --  Allocate Capacity * Element_Bytes via Gada.Core.Memory; sets
   --  S.Buf and S.Capacity. S.Length is left untouched. Capacity = 0
   --  yields a null buffer (matching Go's nil-slice behaviour).

   ---------------------------------------------------------------
   --  Internal helpers
   ---------------------------------------------------------------

   procedure Allocate_Backing
     (S : in out Slice; Capacity : Natural)
   is
      Bytes : constant Storage_Count :=
        Storage_Count (Capacity) * Element_Bytes;
   begin
      if Capacity = 0 then
         S.Buf      := System.Null_Address;
         S.Capacity := 0;
         return;
      end if;
      if Element_Is_Atomic then
         S.Buf := Gada.Core.Memory.Allocate_Atomic (Bytes);
      else
         S.Buf := Gada.Core.Memory.Allocate (Bytes);
      end if;
      S.Capacity := Capacity;
   end Allocate_Backing;

   ---------------------------------------------------------------
   --  Construction
   ---------------------------------------------------------------

   function Make_Slice (Length : Natural) return Slice is
      S : Slice;
   begin
      Allocate_Backing (S, Length);
      S.Length := Length;
      return S;
   end Make_Slice;

   function Make_Slice (Length, Capacity : Natural) return Slice is
      S : Slice;
   begin
      Allocate_Backing (S, Capacity);
      S.Length := Length;
      return S;
   end Make_Slice;

   function From_Array (Items : Element_Array) return Slice is
      Result : Slice;
   begin
      Allocate_Backing (Result, Items'Length);
      Result.Length := Items'Length;
      if Items'Length > 0 then
         declare
            A : Element_Array (1 .. Items'Length)
              with Address => Result.Buf, Import => True;
         begin
            A := Items;
         end;
      end if;
      return Result;
   end From_Array;

   ---------------------------------------------------------------
   --  Inspection
   ---------------------------------------------------------------

   function Len (S : Slice) return Natural is (S.Length);
   function Cap (S : Slice) return Natural is (S.Capacity);

   ---------------------------------------------------------------
   --  Element access via address overlay
   ---------------------------------------------------------------

   function Element (S : Slice; Index : Positive) return Element_Type
   is
      A : Element_Array (1 .. S.Capacity)
        with Address => S.Buf, Import => True;
   begin
      return A (Index);
   end Element;

   procedure Set_Element
     (S : Slice; Index : Positive; Value : Element_Type)
   is
      A : Element_Array (1 .. S.Capacity)
        with Address => S.Buf, Import => True;
   begin
      A (Index) := Value;
   end Set_Element;

   ---------------------------------------------------------------
   --  Append — fast path writes in place; slow path grows.
   ---------------------------------------------------------------

   function Append (S : Slice; Value : Element_Type) return Slice is
      Result : Slice := S;
   begin
      if Result.Length < Result.Capacity then
         Set_Element (Result, Result.Length + 1, Value);
         Result.Length := @ + 1;
         return Result;
      end if;
      declare
         New_Cap : constant Natural :=
           Compute_Next_Capacity (Result.Capacity, Result.Length + 1);
         New_S   : Slice;
      begin
         Allocate_Backing (New_S, New_Cap);
         if Result.Length > 0 then
            Memmove
              (Dst => New_S.Buf,
               Src => Result.Buf,
               N   => Storage_Count (Result.Length) * Element_Bytes);
         end if;
         New_S.Length := Result.Length + 1;
         Set_Element (New_S, New_S.Length, Value);
         return New_S;
      end;
   end Append;

   ---------------------------------------------------------------
   --  Slicing — view, no copy.
   ---------------------------------------------------------------

   function Slice_Of
     (S : Slice; Low, High : Positive) return Slice
   is
      Offset : constant Storage_Count :=
        Storage_Count (Low - 1) * Element_Bytes;
      Result : Slice;
   begin
      if S.Buf = System.Null_Address then
         --  Slicing the empty slice yields the empty slice.
         return Empty;
      end if;
      Result.Buf      := S.Buf + Offset;
      Result.Length   := High - Low;
      Result.Capacity := S.Capacity - (Low - 1);
      return Result;
   end Slice_Of;

   ---------------------------------------------------------------
   --  Growth policy — Go runtime/slice.go growslice (Go 1.18+).
   ---------------------------------------------------------------

   function Compute_Next_Capacity
     (Old_Cap, Min_Cap : Natural) return Natural
   is
      New_Cap : Natural;
   begin
      if Min_Cap = 0 then
         return 0;
      end if;
      if Old_Cap = 0 then
         return Min_Cap;
      end if;
      if Old_Cap < 256 then
         --  Doubling phase. If doubling still doesn't reach Min_Cap
         --  (e.g. user appended a large prefilled chunk), bounce
         --  to Min_Cap directly.
         New_Cap := Old_Cap * 2;
         if New_Cap < Min_Cap then
            New_Cap := Min_Cap;
         end if;
         return New_Cap;
      end if;
      --  1.25x phase with smoothing — Go's: newcap += (newcap +
      --  3*256) / 4. Iterates because user could have requested
      --  several doublings in one Append (e.g. via the future
      --  variadic-append path).
      New_Cap := Old_Cap;
      while New_Cap < Min_Cap loop
         New_Cap := New_Cap + (New_Cap + 3 * 256) / 4;
      end loop;
      return New_Cap;
   end Compute_Next_Capacity;

end Gada.Core.Slices;
