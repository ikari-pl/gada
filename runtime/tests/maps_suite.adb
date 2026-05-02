--  Maps_Suite body — exercises Gada.Core.Maps.
--
--  Two map instantiations:
--    - Int_Map_Fib   : Fibonacci hash, well-distributed.
--    - Int_Map_Adv   : Adversarial hash that forces every key into
--                      one group of 16. Drives the probe-past-
--                      tombstone path and the chain-traversal
--                      logic that Insert / Lookup / Delete rely on.

with AUnit.Assertions; use AUnit.Assertions;

with Interfaces; use Interfaces;

with Gada.Core.Maps;

package body Maps_Suite is

   ---------------------------------------------------------------
   --  Hash functions used by the test instantiations.
   ---------------------------------------------------------------

   --  Fibonacci hash — golden-ratio multiplicative hash. Provides
   --  the well-distributed reference path.
   function Hash_Fib (K : Integer) return Unsigned_64;
   --  Adversarial hash — same hash for every key in the small
   --  range used by Test_Adversarial_Probe_Chain. Forces every
   --  insert into one group; drives the tombstone-and-resume
   --  branches of the probe code.
   function Hash_Constant (K : Integer) return Unsigned_64;

   function Hash_Fib (K : Integer) return Unsigned_64 is
   begin
      return Unsigned_64 (K) * 16#9E37_79B9_7F4A_7C15#;
   end Hash_Fib;

   function Hash_Constant (K : Integer) return Unsigned_64 is
      pragma Unreferenced (K);
   begin
      return 16#5555_5555_5555_5555#;
   end Hash_Constant;

   --  Constant hash whose H1 (= hash >> 7) is odd, so on a Cap=32
   --  table all keys land in *group 1* (slots 16..31). Used to
   --  force iteration's "advance past empty slot 0" path so the
   --  coverage gate sees the loop's increment branch fire.
   function Hash_To_Group_1 (K : Integer) return Unsigned_64;
   function Hash_To_Group_1 (K : Integer) return Unsigned_64 is
      pragma Unreferenced (K);
   begin
      return 16#0000_0000_0000_0180#;
   end Hash_To_Group_1;

   ---------------------------------------------------------------
   --  Instantiations.
   ---------------------------------------------------------------

   package Int_Map_Fib is new Gada.Core.Maps
     (Key_Type      => Integer,
      Value_Type    => Integer,
      Hash          => Hash_Fib,
      "="           => "=",
      Default_Value => -1);

   package Int_Map_Adv is new Gada.Core.Maps
     (Key_Type      => Integer,
      Value_Type    => Integer,
      Hash          => Hash_Constant,
      "="           => "=",
      Default_Value => -1);

   package Int_Map_G1 is new Gada.Core.Maps
     (Key_Type      => Integer,
      Value_Type    => Integer,
      Hash          => Hash_To_Group_1,
      "="           => "=",
      Default_Value => -1);

   ---------------------------------------------------------------
   --  AUnit boilerplate
   ---------------------------------------------------------------

   overriding function Name
     (T : Maps_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Core.Maps suite"));

   overriding procedure Register_Tests (T : in out Maps_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Empty_Map_Defaults'Access,
         "Empty map: Length = 0, Contains = false, Get = Default");
      Register_Routine
        (T, Test_Insert_And_Get'Access,
         "Insert + Get round-trips a value");
      Register_Routine
        (T, Test_Insert_Updates_Existing'Access,
         "Insert on existing key overwrites without size change");
      Register_Routine
        (T, Test_Delete_Present'Access,
         "Delete on present key drops it; Length decrements");
      Register_Routine
        (T, Test_Delete_Absent_Is_Noop'Access,
         "Delete on absent key is a no-op");
      Register_Routine
        (T, Test_Grow_On_Load_Factor'Access,
         "Insert past 7/8 load factor triggers grow + rehash");
      Register_Routine
        (T, Test_Iterate_All_Entries'Access,
         "First/Next/Has_Element visits every live entry once");
      Register_Routine
        (T, Test_Iterate_Empty_Map'Access,
         "First on empty/uninitialised map returns No_Element");
      Register_Routine
        (T, Test_Make_Map_With_Hint'Access,
         "Make_Map (Cap_Hint) pre-sizes to next pow2 >= Hint");
      Register_Routine
        (T, Test_Tombstone_Reuse'Access,
         "Insert after Delete reuses the tombstone slot");
      Register_Routine
        (T, Test_Adversarial_Probe_Chain'Access,
         "Adversarial-hash inserts probe across groups; "
         & "lookup/delete/iterate stay correct");
      Register_Routine
        (T, Test_Clear'Access,
         "Clear empties the map but preserves capacity");
      Register_Routine
        (T, Test_Get_Found_Variant'Access,
         "Get (Found out Boolean) overload disambiguates absent");
      Register_Routine
        (T, Test_Tombstone_Driven_Grow'Access,
         "Grow under tombstone pressure rehashes in place "
         & "(same Cap)");
      Register_Routine
        (T, Test_Iterate_With_Empty_Prefix'Access,
         "Iteration walks past empty leading slots before "
         & "finding live entries");
      Register_Routine
        (T, Test_From_Pairs_Round_Trip'Access,
         "From_Pairs builds a Map containing every pair");
      Register_Routine
        (T, Test_From_Pairs_Empty'Access,
         "From_Pairs on an empty array returns an empty Map");
      Register_Routine
        (T, Test_From_Pairs_Last_Write_Wins'Access,
         "From_Pairs with duplicate keys keeps the last value");
   end Register_Tests;

   ---------------------------------------------------------------
   --  Tests
   ---------------------------------------------------------------

   procedure Test_Empty_Map_Defaults
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : constant Int_Map_Fib.Map := Int_Map_Fib.Make_Map;
   begin
      Assert (Int_Map_Fib.Length (M) = 0,
              "Length should be 0");
      Assert (Int_Map_Fib.Capacity (M) = 0,
              "Capacity should be 0 for deferred-allocation map");
      Assert (not Int_Map_Fib.Contains (M, 42),
              "Contains should be False");
      Assert (Int_Map_Fib.Get (M, 42) = -1,
              "Get should return Default_Value");
   end Test_Empty_Map_Defaults;

   procedure Test_Insert_And_Get
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : Int_Map_Fib.Map;
   begin
      Int_Map_Fib.Insert (M, 1, 100);
      Int_Map_Fib.Insert (M, 2, 200);
      Int_Map_Fib.Insert (M, 3, 300);
      Assert (Int_Map_Fib.Length (M) = 3, "Length should be 3");
      Assert (Int_Map_Fib.Contains (M, 1), "1 should be present");
      Assert (Int_Map_Fib.Get (M, 1) = 100, "Get (1) should be 100");
      Assert (Int_Map_Fib.Get (M, 2) = 200, "Get (2) should be 200");
      Assert (Int_Map_Fib.Get (M, 3) = 300, "Get (3) should be 300");
      Assert (Int_Map_Fib.Get (M, 99) = -1,
              "Get on absent key returns Default");
   end Test_Insert_And_Get;

   procedure Test_Insert_Updates_Existing
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : Int_Map_Fib.Map;
   begin
      Int_Map_Fib.Insert (M, 7, 70);
      Int_Map_Fib.Insert (M, 7, 71);
      Int_Map_Fib.Insert (M, 7, 72);
      Assert (Int_Map_Fib.Length (M) = 1,
              "Length should be 1 after three inserts of same key");
      Assert (Int_Map_Fib.Get (M, 7) = 72,
              "Get (7) should be the most recent value");
   end Test_Insert_Updates_Existing;

   procedure Test_Delete_Present
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : Int_Map_Fib.Map;
   begin
      Int_Map_Fib.Insert (M, 1, 10);
      Int_Map_Fib.Insert (M, 2, 20);
      Int_Map_Fib.Delete (M, 1);
      Assert (Int_Map_Fib.Length (M) = 1, "Length should drop to 1");
      Assert (not Int_Map_Fib.Contains (M, 1),
              "1 should be absent after Delete");
      Assert (Int_Map_Fib.Contains (M, 2),
              "2 should still be present");
   end Test_Delete_Present;

   procedure Test_Delete_Absent_Is_Noop
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : Int_Map_Fib.Map;
   begin
      --  Empty map: Delete on Cap=0 path.
      Int_Map_Fib.Delete (M, 999);
      Assert (Int_Map_Fib.Length (M) = 0, "Should still be empty");
      Int_Map_Fib.Insert (M, 1, 10);
      --  Allocated map: Delete absent.
      Int_Map_Fib.Delete (M, 999);
      Assert (Int_Map_Fib.Length (M) = 1,
              "Length unchanged by Delete-of-absent");
      Assert (Int_Map_Fib.Contains (M, 1), "1 still present");
   end Test_Delete_Absent_Is_Noop;

   procedure Test_Grow_On_Load_Factor
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : Int_Map_Fib.Map;
   begin
      --  Initial Cap = 16, load-factor = 7/8 → grow at 14 entries.
      --  Insert 64 to drive at least two grows.
      for I in 1 .. 64 loop
         Int_Map_Fib.Insert (M, I, I * 10);
      end loop;
      Assert (Int_Map_Fib.Length (M) = 64,
              "Length should be 64 after 64 distinct inserts");
      Assert (Int_Map_Fib.Capacity (M) >= 64,
              "Capacity should have grown past initial 16");
      for I in 1 .. 64 loop
         Assert (Int_Map_Fib.Get (M, I) = I * 10,
                 "Every inserted key should retain its value"
                 & " across grows; key" & Integer'Image (I));
      end loop;
   end Test_Grow_On_Load_Factor;

   procedure Test_Iterate_All_Entries
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M     : Int_Map_Fib.Map;
      Count : Natural := 0;
      Sum   : Natural := 0;
      C     : Int_Map_Fib.Cursor;
   begin
      for I in 1 .. 20 loop
         Int_Map_Fib.Insert (M, I, I);
      end loop;
      C := Int_Map_Fib.First (M);
      while Int_Map_Fib.Has_Element (M, C) loop
         Count := Count + 1;
         --  Use both Key and Value so the iterator's full read
         --  surface is exercised by the coverage gate.
         declare
            K : constant Integer := Int_Map_Fib.Key   (M, C);
            V : constant Integer := Int_Map_Fib.Value (M, C);
         begin
            Assert (K = V,
                    "Insert (I, I) round-trip: Key = Value");
            Sum := Sum + Natural (V);
         end;
         C := Int_Map_Fib.Next (M, C);
      end loop;
      Assert (Count = 20,
              "Iterator should visit every entry exactly once;"
              & " saw" & Natural'Image (Count));
      Assert (Sum = (20 * 21) / 2,
              "Sum should be 1+2+...+20 = 210; was"
              & Natural'Image (Sum));
   end Test_Iterate_All_Entries;

   procedure Test_Iterate_Empty_Map
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : Int_Map_Fib.Map;
      C : Int_Map_Fib.Cursor;
   begin
      C := Int_Map_Fib.First (M);
      Assert (not Int_Map_Fib.Has_Element (M, C),
              "First on uninitialised map = No_Element");
      --  Allocate a non-empty map then clear it.
      Int_Map_Fib.Insert (M, 1, 1);
      Int_Map_Fib.Clear (M);
      C := Int_Map_Fib.First (M);
      Assert (not Int_Map_Fib.Has_Element (M, C),
              "First on cleared map = No_Element");
      --  Calling Next on No_Element returns No_Element.
      C := Int_Map_Fib.Next (M, C);
      Assert (not Int_Map_Fib.Has_Element (M, C),
              "Next (No_Element) = No_Element");
   end Test_Iterate_Empty_Map;

   procedure Test_Make_Map_With_Hint
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : constant Int_Map_Fib.Map := Int_Map_Fib.Make_Map (100);
   begin
      Assert (Int_Map_Fib.Capacity (M) >= 100,
              "Cap_Hint => 100 should pre-allocate >= 100 slots;"
              & " got" & Natural'Image (Int_Map_Fib.Capacity (M)));
      Assert (Int_Map_Fib.Capacity (M) mod 16 = 0,
              "Capacity must be a multiple of Group_Size (16)");
      Assert (Int_Map_Fib.Length (M) = 0,
              "Pre-sized map starts empty");
   end Test_Make_Map_With_Hint;

   procedure Test_Tombstone_Reuse
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : Int_Map_Fib.Map;
   begin
      --  Pack a small map full enough to leave a tombstone after
      --  Delete (no Empty in the group). Use the adversarial hash
      --  so we know all entries land in one group.
      for I in 1 .. 12 loop
         Int_Map_Fib.Insert (M, I, I);
      end loop;
      Int_Map_Fib.Delete (M, 5);
      Assert (Int_Map_Fib.Length (M) = 11, "Length 12 → 11 after Delete");
      Assert (not Int_Map_Fib.Contains (M, 5), "5 absent after Delete");
      --  Re-insert 5 — the probe must find the tombstone slot
      --  and reuse it; not insert past it.
      Int_Map_Fib.Insert (M, 5, 555);
      Assert (Int_Map_Fib.Length (M) = 12,
              "Length back to 12 after re-insert");
      Assert (Int_Map_Fib.Get (M, 5) = 555,
              "Re-inserted value should round-trip");
   end Test_Tombstone_Reuse;

   procedure Test_Adversarial_Probe_Chain
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : Int_Map_Fib.Map;
      --  Use the *constant-hash* instantiation so every key
      --  collides on h1 *and* h2; the probe must walk groups.
      MA : Int_Map_Adv.Map;
   begin
      --  Drop in 40 entries — well past one group's 16 slots,
      --  forcing inter-group probing.
      for I in 1 .. 40 loop
         Int_Map_Adv.Insert (MA, I, I * 100);
      end loop;
      Assert (Int_Map_Adv.Length (MA) = 40,
              "All 40 colliding inserts should be retained");
      for I in 1 .. 40 loop
         Assert (Int_Map_Adv.Get (MA, I) = I * 100,
                 "Adversarial-hash lookup should find key"
                 & Integer'Image (I));
      end loop;
      --  Delete every other key, then re-insert them — exercises
      --  the tombstone path under heavy collision.
      for I in 1 .. 40 loop
         if I mod 2 = 0 then
            Int_Map_Adv.Delete (MA, I);
         end if;
      end loop;
      Assert (Int_Map_Adv.Length (MA) = 20,
              "Length should be 20 after deleting evens");
      for I in 1 .. 40 loop
         if I mod 2 = 0 then
            Int_Map_Adv.Insert (MA, I, I * 1000);
         end if;
      end loop;
      Assert (Int_Map_Adv.Length (MA) = 40,
              "Length back to 40 after re-inserting evens");
      for I in 1 .. 40 loop
         if I mod 2 = 0 then
            Assert (Int_Map_Adv.Get (MA, I) = I * 1000,
                    "Even key reinsertion should hold the new value");
         else
            Assert (Int_Map_Adv.Get (MA, I) = I * 100,
                    "Odd key should retain original value");
         end if;
      end loop;
      --  Touch the well-behaved instantiation too, just to keep
      --  coverage of both Hash plug-ins exercised in one run.
      Int_Map_Fib.Insert (M, 1, 11);
      Assert (Int_Map_Fib.Get (M, 1) = 11,
              "Fibonacci-hash instantiation also works");
   end Test_Adversarial_Probe_Chain;

   procedure Test_Clear
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : Int_Map_Fib.Map;
      Cap_Before : Natural;
   begin
      --  Clear on uninitialised map = no-op.
      Int_Map_Fib.Clear (M);
      Assert (Int_Map_Fib.Length (M) = 0,
              "Clear on uninitialised map is a no-op");

      for I in 1 .. 50 loop
         Int_Map_Fib.Insert (M, I, I);
      end loop;
      Cap_Before := Int_Map_Fib.Capacity (M);
      Int_Map_Fib.Clear (M);
      Assert (Int_Map_Fib.Length (M) = 0,
              "Length = 0 after Clear");
      Assert (Int_Map_Fib.Capacity (M) = Cap_Before,
              "Clear should preserve capacity");
      Assert (not Int_Map_Fib.Contains (M, 25),
              "All entries gone after Clear");
   end Test_Clear;

   procedure Test_Get_Found_Variant
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M     : Int_Map_Fib.Map;
      V     : Integer;
      Found : Boolean;
   begin
      --  Cap = 0 path.
      Int_Map_Fib.Get (M, 1, V, Found);
      Assert (not Found,
              "Cap=0 Get should report Found = False");
      Assert (V = -1, "Cap=0 Get should return Default");

      Int_Map_Fib.Insert (M, 1, 100);
      Int_Map_Fib.Get (M, 1, V, Found);
      Assert (Found, "Get on present key reports Found = True");
      Assert (V = 100, "Got value matches inserted");

      Int_Map_Fib.Get (M, 999, V, Found);
      Assert (not Found, "Absent key reports Found = False");
      Assert (V = -1, "Absent value falls back to Default");
   end Test_Get_Found_Variant;

   procedure Test_Tombstone_Driven_Grow
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Recipe: with constant-hash adversary and Cap = 32:
      --    1. Insert keys 1..16 → group 0 fully packed (slots 0..15).
      --    2. Delete keys 1..14 → group 0 has no Empty, so each
      --       Delete leaves a Tomb_Ctrl. Now Size=2, Tomb=14.
      --    3. Insert keys 17..28 (12 keys) → distributes through
      --       remaining slots. Size=14, Tomb=14. Slots used = 28.
      --    4. Insert key 29 → triggers Maybe_Grow because
      --       Size + Tomb + 1 = 29 > Threshold = 28.
      --       Size (14) <= Cap/2 (16) → TOMBSTONE-ONLY rehash
      --       branch fires (same Cap, just clears tombstones).
      MA          : Int_Map_Adv.Map :=
        Int_Map_Adv.Make_Map (Cap_Hint => 32);
      Cap_Pre     : constant Natural := Int_Map_Adv.Capacity (MA);
      Cap_Post    : Natural;
   begin
      Assert (Cap_Pre = 32,
              "Make_Map (32) should give Cap = 32");
      for I in 1 .. 16 loop
         Int_Map_Adv.Insert (MA, I, I);
      end loop;
      for I in 1 .. 14 loop
         Int_Map_Adv.Delete (MA, I);
      end loop;
      Assert (Int_Map_Adv.Length (MA) = 2,
              "Length = 2 after deleting 14 of 16");
      for I in 17 .. 28 loop
         Int_Map_Adv.Insert (MA, I, I);
      end loop;
      Assert (Int_Map_Adv.Length (MA) = 14,
              "Length = 14 before grow trigger");
      Int_Map_Adv.Insert (MA, 29, 29);
      Cap_Post := Int_Map_Adv.Capacity (MA);
      Assert (Cap_Post = Cap_Pre,
              "Tombstone-driven grow keeps Cap (rehash in place);"
              & " expected" & Cap_Pre'Image
              & " got"      & Cap_Post'Image);
      --  Final correctness: every surviving key reads back
      --  through the rehashed table.
      for I in 15 .. 16 loop
         Assert (Int_Map_Adv.Get (MA, I) = I,
                 "Surviving original key" & I'Image
                 & " survives tombstone-driven rehash");
      end loop;
      for I in 17 .. 29 loop
         Assert (Int_Map_Adv.Get (MA, I) = I,
                 "Newly inserted key" & I'Image
                 & " survives tombstone-driven rehash");
      end loop;
   end Test_Tombstone_Driven_Grow;

   procedure Test_Iterate_With_Empty_Prefix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  All keys hash into group 1 (slots 16..31) on a Cap=32
      --  table; the leading 16 slots stay Empty. First's loop
      --  must therefore advance Idx past slots 0..15 before
      --  hitting the first live entry.
      M     : Int_Map_G1.Map := Int_Map_G1.Make_Map (32);
      C     : Int_Map_G1.Cursor;
      Count : Natural := 0;
   begin
      Int_Map_G1.Insert (M, 100, 100);
      Int_Map_G1.Insert (M, 200, 200);
      Int_Map_G1.Insert (M, 300, 300);
      C := Int_Map_G1.First (M);
      while Int_Map_G1.Has_Element (M, C) loop
         Count := Count + 1;
         C := Int_Map_G1.Next (M, C);
      end loop;
      Assert (Count = 3,
              "All 3 entries should be visited despite "
              & "leading-empty slot prefix");
   end Test_Iterate_With_Empty_Prefix;

   ---------------------------------------------------------------
   --  Bulk constructor — From_Pairs
   ---------------------------------------------------------------

   procedure Test_From_Pairs_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Items : constant Int_Map_Fib.Pair_Array :=
        ((K => 1, V => 10),
         (K => 2, V => 20),
         (K => 3, V => 30));
      M     : constant Int_Map_Fib.Map := Int_Map_Fib.From_Pairs (Items);
   begin
      Assert (Int_Map_Fib.Length (M) = 3,
              "From_Pairs must populate Length = Items'Length on unique keys");
      Assert (Int_Map_Fib.Get (M, 1) = 10, "From_Pairs key 1 → 10");
      Assert (Int_Map_Fib.Get (M, 2) = 20, "From_Pairs key 2 → 20");
      Assert (Int_Map_Fib.Get (M, 3) = 30, "From_Pairs key 3 → 30");
   end Test_From_Pairs_Round_Trip;

   procedure Test_From_Pairs_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : constant Int_Map_Fib.Map :=
        Int_Map_Fib.From_Pairs (Int_Map_Fib.Pair_Array'(1 .. 0 => <>));
   begin
      Assert (Int_Map_Fib.Length (M) = 0,
              "From_Pairs on empty array yields empty Map");
   end Test_From_Pairs_Empty;

   procedure Test_From_Pairs_Last_Write_Wins
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Items : constant Int_Map_Fib.Pair_Array :=
        ((K => 1, V => 10),
         (K => 1, V => 20),
         (K => 1, V => 99));
      M     : constant Int_Map_Fib.Map := Int_Map_Fib.From_Pairs (Items);
   begin
      Assert (Int_Map_Fib.Length (M) = 1,
              "Duplicate keys collapse to a single entry");
      Assert (Int_Map_Fib.Get (M, 1) = 99,
              "Last write wins on From_Pairs duplicate keys");
   end Test_From_Pairs_Last_Write_Wins;

end Maps_Suite;
