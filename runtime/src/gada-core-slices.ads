--  Gada.Core.Slices — generic slice type modelled on Go's slice.
--
--  A Go slice is a 3-word header (data pointer, length, capacity)
--  over a backing array shared by reference. This implementation
--  matches that layout exactly: the Slice record holds (Buf, Length,
--  Capacity), and slicing operations (`Slice_Of`) return a new
--  header viewing the same backing storage. Append grows in place
--  when capacity allows; otherwise it allocates fresh backing via
--  Gada.Core.Memory and `memmove`s the old elements over.
--
--  Per docs/adr/0006-runtime-performance-bar.md:
--
--    - Backing storage is allocated through libgc via the parent
--      Gada.Core.Memory layer. When the formal `Element_Is_Atomic`
--      is True the allocator path is `Allocate_Atomic`, telling
--      libgc the backing contains no pointers worth scanning.
--      Set this for Go's pointer-free element types (int, float64,
--      byte, struct-of-primitives) — it skips the conservative
--      scan and is materially faster for large arrays.
--
--    - Growth policy mirrors Go's runtime/slice.go growslice as of
--      Go 1.18: doubling under 256 elements, then a 1.25x phase
--      with a smoothing term. Amortised append is O(1); the over-
--      allocation tail stays bounded for large slices.
--
--    - 3-word header layout matches Go's reflect.SliceHeader so
--      the Phase 11 cross-comparison harness can count cycles per
--      op apples-to-apples without representational overhead.
--
--  Ada 2022 features in use:
--
--    - Pre/Post contracts on every public subprogram.
--    - Expression functions for Len/Cap.
--    - Address-overlay element access (zero-copy on -O2).
--
--  Ravenscar-safety: the package allocates and uses libgc, so it is
--  not Pure. It is, however, free of tasking and protected types and
--  is safe to use from any task context (libgc itself is multi-
--  threaded).

with System;

generic
   type Element_Type is private;
   --  Set True when Element_Type contains no GC-tracked pointers
   --  (Go int / float64 / byte / struct of primitives). The backing
   --  storage is then allocated atomic and excluded from libgc's
   --  conservative scan. Misuse is a memory-safety bug — a pointer
   --  stored in atomic backing will not keep its referent alive.
   Element_Is_Atomic : Boolean := False;
package Gada.Core.Slices is

   type Slice is private;

   --  Empty slice — Buf = Null_Address, Length = Cap = 0. Equivalent
   --  to Go's `var s []T` (nil slice). Append onto it allocates fresh
   --  backing.
   Empty : constant Slice;

   ---------------------------------------------------------------
   --  Construction
   ---------------------------------------------------------------

   --  Element_Array — public unconstrained array type so users
   --  (chiefly the compiler-emit layer for Phase 2's slice composite
   --  literals, `[]T{e1, e2, ...}`) can pass a literal aggregate
   --  through `From_Array`. Layout-compatible with the same anonymous
   --  array types declared inside Element / Set_Element / Append at
   --  the address-overlay sites.
   type Element_Array is array (Positive range <>) of Element_Type;

   --  Make_Slice (N) — Go's `make([]T, N)`. Length == Capacity == N,
   --  all elements zero-initialised by libgc.
   function Make_Slice (Length : Natural) return Slice
     with Post => Len (Make_Slice'Result) = Length
                  and then Cap (Make_Slice'Result) = Length;

   --  From_Array — the single-call constructor the compiler-emit layer
   --  uses for `[]T{e1, e2, ...}`. Length == Capacity == Items'Length;
   --  the resulting slice owns fresh backing populated by an unchecked
   --  whole-array assignment through the address overlay (memcpy at
   --  -O2 for trivially-copyable element types, element-wise Adjust
   --  for controlled element types). The caller's Items array is not
   --  retained by reference.
   function From_Array (Items : Element_Array) return Slice
     with Post => Len (From_Array'Result) = Items'Length
                  and then Cap (From_Array'Result) = Items'Length;

   --  Make_Slice (N, Cap) — Go's `make([]T, N, Cap)`. Backing of
   --  Cap elements; first N visible.
   function Make_Slice (Length, Capacity : Natural) return Slice
     with Pre  => Length <= Capacity,
          Post => Len (Make_Slice'Result) = Length
                  and then Cap (Make_Slice'Result) = Capacity;

   ---------------------------------------------------------------
   --  Inspection
   ---------------------------------------------------------------

   function Len (S : Slice) return Natural;
   function Cap (S : Slice) return Natural;

   ---------------------------------------------------------------
   --  Element access (1-based; Ada convention).
   --  Go is 0-based externally; the compiler-emit layer (Phase 2
   --  item 6) translates `s[i]` to `Element (s, i + 1)`.
   ---------------------------------------------------------------

   function Element (S : Slice; Index : Positive) return Element_Type
     with Pre => Index <= Len (S);

   procedure Set_Element
     (S : Slice; Index : Positive; Value : Element_Type)
     with Pre => Index <= Len (S);

   ---------------------------------------------------------------
   --  Append.
   --
   --  If Length < Capacity: write in place at index Length+1 and
   --  return a header with Length+1 over the same backing.
   --  Otherwise: allocate new backing of Compute_Next_Capacity (Cap,
   --  Length+1), memmove the old elements over, write the new
   --  element, and return a header pointing at the new backing.
   --
   --  Matches Go's value-semantics for slice headers: the input S
   --  is unchanged on return; the caller rebinds the variable.
   ---------------------------------------------------------------

   function Append (S : Slice; Value : Element_Type) return Slice
     with Post => Len (Append'Result) = Len (S) + 1;

   ---------------------------------------------------------------
   --  Slicing — Go's `s[low:high]`.
   --
   --  Returns a header viewing the same backing from position Low
   --  through High-1. Capacity of the result is original Cap -
   --  (Low - 1), preserving "tail" capacity so further in-place
   --  appends remain possible — same semantics Go uses.
   --
   --  Bounds: Low and High are 1-based; High = Len (S) + 1 is
   --  the legal "one past the end" sentinel (yields an empty
   --  slice if equal to Low).
   ---------------------------------------------------------------

   function Slice_Of
     (S : Slice; Low, High : Positive) return Slice
     with Pre  => Low <= High and then High <= Len (S) + 1,
          Post => Len (Slice_Of'Result) = High - Low;

   ---------------------------------------------------------------
   --  Compute_Next_Capacity — Go's runtime/slice.go growslice
   --  policy, exposed for testability and bench harness use.
   --
   --  Old_Cap = current capacity (0 for empty slice).
   --  Min_Cap = required new capacity (Length + 1 for single-
   --            element append; Length + N for multi-append).
   --  Returns the new capacity to allocate; never less than
   --  Min_Cap, never zero unless Min_Cap is zero.
   --
   --  Rule: if Old_Cap < 256, double. Otherwise repeatedly grow
   --  by 1.25x with a 3/4-step smoothing term until >= Min_Cap.
   ---------------------------------------------------------------

   function Compute_Next_Capacity
     (Old_Cap, Min_Cap : Natural) return Natural;

private

   --  3-word header — same field count and ordering as Go's
   --  reflect.SliceHeader. Representation is GADA-internal and
   --  need only be stable across one runtime build.
   type Slice is record
      Buf      : System.Address := System.Null_Address;
      Length   : Natural        := 0;
      Capacity : Natural        := 0;
   end record;

   Empty : constant Slice :=
     (Buf => System.Null_Address, Length => 0, Capacity => 0);

end Gada.Core.Slices;
