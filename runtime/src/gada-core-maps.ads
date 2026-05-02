--  Gada.Core.Maps — Swiss-table generic hash map.
--
--  Layout per Google's abseil-cpp `flat_hash_map` reference design:
--  a parallel control-byte array + slot array, scanned 16 bytes at
--  a time (a "group"). Linear probing across groups; cache-line-
--  aligned slot allocations for predictable probe behaviour.
--
--  Per docs/adr/0006-runtime-performance-bar.md:
--
--    - Open addressing with 1-byte control-per-slot. Empty slots
--      carry sentinel 16#80#; tombstones (deleted) carry 16#FE#;
--      live slots carry the low 7 bits of the key's hash (h2).
--    - Group of 16 control bytes scanned in parallel by a portable
--      byte loop. At `-O2` GNAT vectorises the 16-byte equality
--      scan to a single 128-bit compare on aarch64 (NEON) and
--      x86_64 (SSE2) — close enough to hand-rolled intrinsics for
--      v1, with zero portability risk.
--    - Load factor 7/8 (87.5%). Triggers grow when Size + Tombstones
--      exceeds Cap * 7/8; grow doubles capacity and rehashes,
--      clearing tombstones in the process.
--    - Cache-line-aligned slot allocation via libgc's natural
--      alignment.
--
--  Generic over (Key_Type, Value_Type, Hash, "="). The compiler-
--  emit layer (Phase 2 item 7) instantiates this generic once per
--  Go map type the program uses, plugging in:
--    - `Hash` per key type. For string keys this becomes
--      Gada.Hash.SipHash_1_3 (Phase 4 land); for int keys it's
--      Fibonacci (golden-ratio multiplicative); for typed-ID keys
--      it's the user's choice.
--    - `"="` per key type. Defaults to predefined `=` so primitive
--      keys "just work".
--
--  Iteration is index-based via a Cursor type, with a randomised
--  starting offset so iteration order matches Go's map-iteration
--  semantics (non-deterministic, exposed-for-fuzzing).

with Interfaces;
with System;

generic
   type Key_Type   is private;
   type Value_Type is private;
   with function Hash (K : Key_Type) return Interfaces.Unsigned_64;
   with function "=" (L, R : Key_Type) return Boolean is <>;
   Default_Value : Value_Type;
package Gada.Core.Maps is

   type Map is private;

   ---------------------------------------------------------------
   --  Construction
   ---------------------------------------------------------------

   --  Make_Map (Cap_Hint) — pre-size for ~Cap_Hint entries (rounded
   --  up to the next power of two ≥ 16). Saves rehashes on bulk
   --  insertion. Cap_Hint = 0 yields a deferred-allocation map; the
   --  first insert allocates the initial 16-slot capacity.
   function Make_Map (Cap_Hint : Natural := 0) return Map;

   --  Pair / Pair_Array exist for `From_Pairs` — they let the
   --  compiler-emit layer pass a Go-source `map[K]V{k1: v1, k2: v2}`
   --  literal as a single Ada 2022 array aggregate, side-stepping
   --  the impossibility of inlining N statements into one
   --  expression. The shape mirrors `Element_Array` /
   --  `Slices.From_Array` from `Gada.Core.Slices`.
   type Pair is record
      K : Key_Type;
      V : Value_Type;
   end record;
   type Pair_Array is array (Positive range <>) of Pair;

   --  From_Pairs (Items) — pre-size for `Items'Length` then bulk-
   --  insert. Equivalent to `M := Make_Map (Items'Length); for P of
   --  Items loop Insert (M, P.K, P.V); end loop;` but expression-
   --  position so it composes with `:=` initialisation. Last-write-
   --  wins on duplicate keys.
   function From_Pairs (Items : Pair_Array) return Map;

   ---------------------------------------------------------------
   --  Inspection
   ---------------------------------------------------------------

   function Length (M : Map) return Natural;
   function Capacity (M : Map) return Natural;

   --  True iff K is present and live (not a tombstone).
   function Contains (M : Map; K : Key_Type) return Boolean;

   --  Get (M, K) → returns Default_Value if K is not in M.
   --  Use the (Found) overload to disambiguate "absent" from
   --  "present with Default_Value".
   function Get (M : Map; K : Key_Type) return Value_Type;
   procedure Get
     (M     : Map;
      K     : Key_Type;
      Value : out Value_Type;
      Found : out Boolean);

   ---------------------------------------------------------------
   --  Mutation
   ---------------------------------------------------------------

   --  Insert / overwrite. Triggers grow when load factor > 7/8.
   procedure Insert
     (M : in out Map; K : Key_Type; V : Value_Type);

   --  Delete K from M; no-op if K is absent. Marks the slot as a
   --  tombstone so probe sequences past it remain correct.
   procedure Delete (M : in out Map; K : Key_Type);

   --  Clear M to its empty state without releasing the backing
   --  storage. Keeps capacity for reuse.
   procedure Clear (M : in out Map);

   ---------------------------------------------------------------
   --  Iteration.
   --
   --  Iteration order is non-deterministic between Map instances
   --  and between runs (randomised starting offset), matching
   --  Go's map-iteration contract that programs must not rely on
   --  ordering. Use as:
   --
   --     C := M.First;
   --     while M.Has_Element (C) loop
   --        Process (M.Key (C), M.Value (C));
   --        C := M.Next (C);
   --     end loop;
   ---------------------------------------------------------------

   type Cursor is private;
   No_Element : constant Cursor;

   function First (M : Map) return Cursor;
   function Next  (M : Map; C : Cursor) return Cursor;
   function Has_Element (M : Map; C : Cursor) return Boolean;
   function Key   (M : Map; C : Cursor) return Key_Type
     with Pre => Has_Element (M, C);
   function Value (M : Map; C : Cursor) return Value_Type
     with Pre => Has_Element (M, C);

private

   --  Slot record — pairs Key + Value + the 64-bit hash (cached so
   --  Lookup doesn't re-hash on collisions and Grow doesn't re-hash
   --  every slot).
   type Slot is record
      Key       : Key_Type;
      Val       : Value_Type;
      Full_Hash : Interfaces.Unsigned_64 := 0;
   end record;

   type Map is record
      --  Backing storage. Both arrays are libgc-allocated System
      --  addresses, type-overlaid via Address aspect at access
      --  time.
      Control_Buf : System.Address := System.Null_Address;
      Slots_Buf   : System.Address := System.Null_Address;
      Cap         : Natural        := 0;   -- power of 2 (or 0)
      Size        : Natural        := 0;
      Tombstones  : Natural        := 0;
   end record;

   type Cursor is record
      Index : Integer := -1;
      --  -1 = No_Element (cursor exhausted or empty Map).
      --  0 .. Cap-1 indexes a live slot.
   end record;

   No_Element : constant Cursor := (Index => -1);

end Gada.Core.Maps;
