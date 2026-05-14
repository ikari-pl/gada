--  Gada.Core.Maps body — Swiss-table generic hash map.
--
--  Layout in memory (Cap = 4 × Group_Size shown):
--
--     Control [0 .. Cap-1]   :  c c c c c c c c c c c c c c c c   <- group 0
--                               c c c c c c c c c c c c c c c c   <- group 1
--                               c c c c c c c c c c c c c c c c   <- group 2
--                               c c c c c c c c c c c c c c c c   <- group 3
--
--     Slots   [0 .. Cap-1]   :  (Key, Value, Full_Hash) per slot
--
--  Control byte values:
--    16#80#  = empty (top bit set, all others zero)
--    16#FE#  = tombstone (deleted, but probe must continue past)
--    16#00#..16#7F# = live; low 7 bits of hash (call it h2)
--
--  Probing: triangular numbers across groups. Probe i visits
--  group (h1 + i*(i+1)/2) mod groups. Visits every group exactly
--  once when groups is a power of two — the standard abseil
--  Swiss-table reservation.
--
--  Lookup proceeds group-at-a-time:
--    1. For each control byte == h2 in the group: check
--       Slots [slot].Full_Hash == hash *and* Key match.
--    2. If any control byte == empty in the group: key absent.
--    3. Otherwise: probe next group.
--
--  Insert proceeds the same way but additionally remembers the
--  first tombstone-or-empty slot it sees. If the key isn't found
--  by step 2, we insert into that remembered slot.
--
--  Delete: finds the slot via lookup probe. If the group contains
--  any empty slot, mark Empty (probe past the deleted slot would
--  have terminated at the empty, so a fresh empty here is safe).
--  Otherwise mark Tombstone (subsequent probes must continue).
--  This keeps tombstone density bounded for steady-state churn.
--
--  Grow: when (Size + Tombstones) exceeds Cap × 7/8, double Cap
--  and rehash. Tombstones are dropped (not copied to the new
--  table); their cost is paid at grow time, not at lookup time.

with Gada.Core.Memory;
with System.Storage_Elements;

package body Gada.Core.Maps is

   use Interfaces;
   use type System.Address;

   ---------------------------------------------------------------
   --  Constants
   ---------------------------------------------------------------

   Group_Size      : constant Natural    := 16;
   Min_Cap         : constant Natural    := Group_Size;
   --  Power of 2 ≥ Group_Size. Initial cap when Make_Map is given
   --  no hint (or hint = 0).
   Initial_Cap     : constant Natural    := 16;

   Empty_Ctrl      : constant Unsigned_8 := 16#80#;
   Tomb_Ctrl       : constant Unsigned_8 := 16#FE#;
   --  Live mask: any value 0x00..0x7F (top bit clear).

   ---------------------------------------------------------------
   --  Storage typing — control bytes and slot record arrays
   --  overlaid on libgc-allocated buffers via Address aspect.
   ---------------------------------------------------------------

   type Control_Array is array (Natural range <>) of Unsigned_8
     with Component_Size => 8;

   type Slot_Array is array (Natural range <>) of Slot;

   ---------------------------------------------------------------
   --  Forward declarations of internal helpers (-gnatys requires
   --  every body to follow a visible spec).
   ---------------------------------------------------------------

   function H1 (Hash : Unsigned_64) return Unsigned_64;
   function H2 (Hash : Unsigned_64) return Unsigned_8;
   function Is_Live (Ctrl : Unsigned_8) return Boolean;
   function Round_Up_Pow2 (N : Natural) return Natural;

   procedure Allocate_Backing
     (M : in out Map; New_Cap : Natural);

   procedure Rehash_Into
     (Old_Slots_Buf   : System.Address;
      Old_Control_Buf : System.Address;
      Old_Cap         : Natural;
      Target          : in out Map);

   procedure Maybe_Grow (M : in out Map; Wanted : Natural);

   --  Tombstone-driven grow keeps Cap; load-driven doubles.
   function Pick_New_Cap (M : Map) return Natural;

   --  Find / insert helpers — return slot indexes (0 .. Cap-1)
   --  or -1 for absent. Operate on a Map whose Cap > 0.
   function Probe_For_Lookup (M : Map; K : Key_Type) return Integer;

   procedure Probe_For_Insert
     (M           : Map;
      K           : Key_Type;
      H_Full      : Unsigned_64;
      Slot_Idx    : out Natural;
      Was_Present : out Boolean);

   ---------------------------------------------------------------
   --  Hash helpers
   ---------------------------------------------------------------

   function H1 (Hash : Unsigned_64) return Unsigned_64 is
     (Shift_Right (Hash, 7));

   function H2 (Hash : Unsigned_64) return Unsigned_8 is
     (Unsigned_8 (Hash and 16#7F#));

   function Is_Live (Ctrl : Unsigned_8) return Boolean is
     ((Ctrl and 16#80#) = 0);

   ---------------------------------------------------------------
   --  Power-of-2 rounding
   ---------------------------------------------------------------

   function Round_Up_Pow2 (N : Natural) return Natural is
      Result : Natural := Min_Cap;
   begin
      while Result < N loop
         Result := Result * 2;
      end loop;
      return Result;
   end Round_Up_Pow2;

   ---------------------------------------------------------------
   --  Allocation
   ---------------------------------------------------------------

   procedure Allocate_Backing
     (M : in out Map; New_Cap : Natural)
   is
      use System.Storage_Elements;
      Control_Bytes : constant Storage_Count :=
        Storage_Count (New_Cap);
      Slot_Bytes    : constant Storage_Count :=
        Storage_Count (New_Cap)
        * Storage_Count (Slot'Object_Size / 8);
   begin
      M.Control_Buf := Gada.Core.Memory.Allocate (Control_Bytes);
      --  Slots have Key/Value which may contain pointers — must
      --  be traced (not Allocate_Atomic).
      M.Slots_Buf   := Gada.Core.Memory.Allocate (Slot_Bytes);
      M.Cap         := New_Cap;
      --  Initialise every control byte to Empty.
      declare
         Ctrl : Control_Array (0 .. New_Cap - 1)
           with Address => M.Control_Buf, Import => True;
      begin
         Ctrl := [others => Empty_Ctrl];
      end;
      --  Slot contents need not be initialised — only live slots
      --  (those whose control byte != Empty/Tomb) are read.
   end Allocate_Backing;

   ---------------------------------------------------------------
   --  Make_Map
   ---------------------------------------------------------------

   function Make_Map (Cap_Hint : Natural := 0) return Map is
      M       : Map;
      Wanted  : Natural;
   begin
      if Cap_Hint = 0 then
         return M;  -- deferred allocation
      end if;
      Wanted := Round_Up_Pow2
        (Natural'Max (Cap_Hint, Min_Cap));
      Allocate_Backing (M, Wanted);
      return M;
   end Make_Map;

   ---------------------------------------------------------------
   --  Inspection
   ---------------------------------------------------------------

   function Length   (M : Map) return Natural is (M.Size);
   function Capacity (M : Map) return Natural is (M.Cap);

   ---------------------------------------------------------------
   --  Lookup probe — returns slot index or -1.
   ---------------------------------------------------------------

   function Probe_For_Lookup
     (M : Map; K : Key_Type) return Integer
   is
      H_Full      : constant Unsigned_64 := Hash (K);
      H_Top       : constant Unsigned_8  := H2 (H_Full);
      Groups      : constant Natural     := M.Cap / Group_Size;
      Mask        : constant Unsigned_64 := Unsigned_64 (Groups - 1);
      Probe_Step  : Unsigned_64 := 0;
      Group_Idx   : Unsigned_64 := H1 (H_Full) and Mask;

      Ctrl  : Control_Array (0 .. M.Cap - 1)
        with Address => M.Control_Buf, Import => True;
      Slots : Slot_Array (0 .. M.Cap - 1)
        with Address => M.Slots_Buf, Import => True;

   begin
      --  Unconditional loop — same termination argument as
      --  Probe_For_Insert: the 7/8 load-factor invariant
      --  guarantees an Empty in every probe chain.
      loop
         declare
            Group_Start : constant Natural := Natural (Group_Idx) * Group_Size;
            Saw_Empty   : Boolean := False;
         begin
            for I in 0 .. Group_Size - 1 loop
               declare
                  Idx : constant Natural := Group_Start + I;
                  C   : constant Unsigned_8 := Ctrl (Idx);
               begin
                  if C = H_Top
                    and then Slots (Idx).Full_Hash = H_Full
                    and then Slots (Idx).Key = K
                  then
                     return Idx;
                  end if;
                  if C = Empty_Ctrl then
                     Saw_Empty := True;
                  end if;
               end;
            end loop;
            if Saw_Empty then
               return -1;
            end if;
         end;
         Probe_Step := @ + 1;
         Group_Idx  := (@ + Probe_Step) and Mask;
      end loop;
   end Probe_For_Lookup;

   ---------------------------------------------------------------
   --  Insert probe — finds an existing slot to overwrite, OR the
   --  first empty/tombstone slot to claim. Sets Was_Present.
   ---------------------------------------------------------------

   procedure Probe_For_Insert
     (M           : Map;
      K           : Key_Type;
      H_Full      : Unsigned_64;
      Slot_Idx    : out Natural;
      Was_Present : out Boolean)
   is
      H_Top       : constant Unsigned_8  := H2 (H_Full);
      Groups      : constant Natural     := M.Cap / Group_Size;
      Mask        : constant Unsigned_64 := Unsigned_64 (Groups - 1);
      Probe_Step  : Unsigned_64 := 0;
      Group_Idx   : Unsigned_64 := H1 (H_Full) and Mask;
      First_Free  : Integer := -1;

      Ctrl  : Control_Array (0 .. M.Cap - 1)
        with Address => M.Control_Buf, Import => True;
      Slots : Slot_Array (0 .. M.Cap - 1)
        with Address => M.Slots_Buf, Import => True;
   begin
      --  Unconditional loop: the load-factor invariant
      --  (enforced by Maybe_Grow before every Insert) guarantees
      --  that at least one slot in every probe chain is empty or
      --  tombstone, so a return inside the loop body always
      --  fires within at most Groups iterations. No post-loop
      --  fallthrough — keeps the coverage gate honest.
      loop
         declare
            Group_Start : constant Natural := Natural (Group_Idx) * Group_Size;
            Saw_Empty   : Boolean := False;
         begin
            for I in 0 .. Group_Size - 1 loop
               declare
                  Idx : constant Natural := Group_Start + I;
                  C   : constant Unsigned_8 := Ctrl (Idx);
               begin
                  if C = H_Top
                    and then Slots (Idx).Full_Hash = H_Full
                    and then Slots (Idx).Key = K
                  then
                     Slot_Idx    := Idx;
                     Was_Present := True;
                     return;
                  end if;
                  if not Is_Live (C) and First_Free = -1 then
                     First_Free := Idx;
                  end if;
                  if C = Empty_Ctrl then
                     Saw_Empty := True;
                  end if;
               end;
            end loop;
            if Saw_Empty then
               --  Key not present; claim First_Free.
               Slot_Idx    := Natural (First_Free);
               Was_Present := False;
               return;
            end if;
         end;
         Probe_Step := @ + 1;
         Group_Idx  := (@ + Probe_Step) and Mask;
      end loop;
   end Probe_For_Insert;

   ---------------------------------------------------------------
   --  Insert
   ---------------------------------------------------------------

   function Pick_New_Cap (M : Map) return Natural is
     (if M.Size <= M.Cap / 2 then M.Cap else M.Cap * 2);

   procedure Maybe_Grow (M : in out Map; Wanted : Natural) is
      --  Grow when Size + Tombstones would exceed 7/8 of Cap on
      --  next insert (Wanted typically = Size + 1).
      Threshold : Natural;
   begin
      if M.Cap = 0 then
         Allocate_Backing (M, Initial_Cap);
         return;
      end if;
      Threshold := (M.Cap * 7) / 8;
      if M.Size + M.Tombstones + Wanted - M.Size <= Threshold then
         return;
      end if;
      declare
         Old_Cap         : constant Natural := M.Cap;
         Old_Control_Buf : constant System.Address := M.Control_Buf;
         Old_Slots_Buf   : constant System.Address := M.Slots_Buf;
         --  Tombstone-driven grow keeps Cap (same-size rehash
         --  that drops tombstones); load-driven grow doubles.
         New_Cap : constant Natural := Pick_New_Cap (M);
      begin
         M.Size       := 0;
         M.Tombstones := 0;
         M.Cap        := 0;
         Allocate_Backing (M, New_Cap);
         Rehash_Into
           (Old_Slots_Buf, Old_Control_Buf, Old_Cap, M);
         --  Old buffers go to libgc; no explicit free.
      end;
   end Maybe_Grow;

   procedure Rehash_Into
     (Old_Slots_Buf   : System.Address;
      Old_Control_Buf : System.Address;
      Old_Cap         : Natural;
      Target          : in out Map)
   is
      Old_Ctrl  : Control_Array (0 .. Old_Cap - 1)
        with Address => Old_Control_Buf, Import => True;
      Old_Slots : Slot_Array (0 .. Old_Cap - 1)
        with Address => Old_Slots_Buf, Import => True;
   begin
      --  Ada 2022 iterator filter — `when Is_Live (…)` skips
      --  tombstones and empty slots without a nested `if` in the body.
      for I in 0 .. Old_Cap - 1 when Is_Live (Old_Ctrl (I)) loop
         Insert (Target, Old_Slots (I).Key, Old_Slots (I).Val);
      end loop;
   end Rehash_Into;

   procedure Insert
     (M : in out Map; K : Key_Type; V : Value_Type)
   is
      H_Full      : Unsigned_64;
      Slot_Idx    : Natural;
      Was_Present : Boolean;
   begin
      Maybe_Grow (M, M.Size + 1);
      H_Full := Hash (K);
      Probe_For_Insert (M, K, H_Full, Slot_Idx, Was_Present);
      declare
         Ctrl  : Control_Array (0 .. M.Cap - 1)
           with Address => M.Control_Buf, Import => True;
         Slots : Slot_Array (0 .. M.Cap - 1)
           with Address => M.Slots_Buf, Import => True;
         Was_Tomb : constant Boolean :=
           Ctrl (Slot_Idx) = Tomb_Ctrl;
      begin
         Slots (Slot_Idx) := (Key => K, Val => V, Full_Hash => H_Full);
         Ctrl (Slot_Idx)  := H2 (H_Full);
         if not Was_Present then
            M.Size := @ + 1;
            if Was_Tomb then
               M.Tombstones := @ - 1;
            end if;
         end if;
      end;
   end Insert;

   ---------------------------------------------------------------
   --  Bulk constructor — From_Pairs
   ---------------------------------------------------------------

   --  Pre-sizing to `Items'Length` rather than to the post-dedup
   --  unique-key count is intentional: it costs at most one extra
   --  doubling on heavy-duplicate input, and the alternative
   --  (counting uniques first) requires a separate hash pass that
   --  buys nothing on the common no-duplicate case.
   function From_Pairs (Items : Pair_Array) return Map is
   begin
      return M : Map := Make_Map (Items'Length) do
         for P of Items loop
            Insert (M, P.K, P.V);
         end loop;
      end return;
   end From_Pairs;

   ---------------------------------------------------------------
   --  Lookup
   ---------------------------------------------------------------

   function Contains (M : Map; K : Key_Type) return Boolean is
   begin
      if M.Cap = 0 then
         return False;
      end if;
      return Probe_For_Lookup (M, K) >= 0;
   end Contains;

   function Get (M : Map; K : Key_Type) return Value_Type is
      Idx   : Integer;
      Slots : Slot_Array (0 .. M.Cap - 1)
        with Address => M.Slots_Buf, Import => True;
   begin
      if M.Cap = 0 then
         return Default_Value;
      end if;
      Idx := Probe_For_Lookup (M, K);
      if Idx < 0 then
         return Default_Value;
      end if;
      return Slots (Natural (Idx)).Val;
   end Get;

   procedure Get
     (M     : Map;
      K     : Key_Type;
      Value : out Value_Type;
      Found : out Boolean)
   is
      Idx : Integer;
   begin
      if M.Cap = 0 then
         Value := Default_Value;
         Found := False;
         return;
      end if;
      Idx := Probe_For_Lookup (M, K);
      if Idx < 0 then
         Value := Default_Value;
         Found := False;
         return;
      end if;
      declare
         Slots : Slot_Array (0 .. M.Cap - 1)
           with Address => M.Slots_Buf, Import => True;
      begin
         Value := Slots (Natural (Idx)).Val;
         Found := True;
      end;
   end Get;

   ---------------------------------------------------------------
   --  Delete
   ---------------------------------------------------------------

   procedure Delete (M : in out Map; K : Key_Type) is
      Idx : Integer;
   begin
      if M.Cap = 0 then
         return;
      end if;
      Idx := Probe_For_Lookup (M, K);
      if Idx < 0 then
         return;
      end if;
      declare
         Ctrl : Control_Array (0 .. M.Cap - 1)
           with Address => M.Control_Buf, Import => True;
         --  Inspect the rest of the slot's group: if any control
         --  byte is empty, marking this slot empty is safe (no
         --  probe sequence relies on it being a tombstone). If
         --  not, we must leave a tombstone to keep probe chains
         --  intact.
         Group_Start : constant Natural :=
           (Idx / Group_Size) * Group_Size;
         --  Ada 2022 existential quantifier — replaces a five-line
         --  for-loop-with-exit by an expression that reads as the
         --  predicate it actually evaluates.
         Saw_Empty   : constant Boolean :=
           (for some I in 0 .. Group_Size - 1 =>
              Ctrl (Group_Start + I) = Empty_Ctrl);
      begin
         if Saw_Empty then
            Ctrl (Idx) := Empty_Ctrl;
         else
            Ctrl (Idx)   := Tomb_Ctrl;
            M.Tombstones := @ + 1;
         end if;
      end;
      M.Size := @ - 1;
   end Delete;

   ---------------------------------------------------------------
   --  Clear — keep capacity, drop entries.
   ---------------------------------------------------------------

   procedure Clear (M : in out Map) is
   begin
      if M.Cap = 0 then
         return;
      end if;
      declare
         Ctrl : Control_Array (0 .. M.Cap - 1)
           with Address => M.Control_Buf, Import => True;
      begin
         Ctrl := [others => Empty_Ctrl];
      end;
      M.Size       := 0;
      M.Tombstones := 0;
   end Clear;

   ---------------------------------------------------------------
   --  Iteration
   ---------------------------------------------------------------

   --  First and Next share one walk strategy: pick a starting
   --  index from Iter_Seed mod Cap, then walk Cap positions
   --  forward modulo Cap. The randomised start gives Go's
   --  unstable-iteration-order semantics; the modular walk
   --  visits every slot exactly once.
   --
   --  We accumulate into a local Result and keep a single exit
   --  rather than returning early from inside the loop. Same
   --  observable semantics, simpler control flow, no
   --  unreachable-fallthrough lines for the coverage gate to
   --  flag.

   --  V1 iteration walks slot 0 forward — deterministic order.
   --  Go's spec mandates non-deterministic order to prevent
   --  programs from depending on it; we satisfy the spirit with a
   --  startup-time seed once Phase 3's scheduler lands (one
   --  randomisation source per program applied as a constant
   --  offset). For v1 "any single observable order is
   --  unspecified" — deterministic-per-test is a stronger
   --  guarantee that doesn't break Go's invariant. Tracked in
   --  docs/imperfections.md.

   function First (M : Map) return Cursor is
   begin
      if M.Cap = 0 or else M.Size = 0 then
         return No_Element;
      end if;
      declare
         Ctrl : Control_Array (0 .. M.Cap - 1)
           with Address => M.Control_Buf, Import => True;
         Idx  : Natural := 0;
      begin
         loop
            if Is_Live (Ctrl (Idx)) then
               return (Index => Idx);
            end if;
            Idx := @ + 1;
         end loop;
      end;
   end First;

   function Next (M : Map; C : Cursor) return Cursor is
   begin
      if M.Cap = 0 or else C.Index < 0 then
         return No_Element;
      end if;
      declare
         Ctrl : Control_Array (0 .. M.Cap - 1)
           with Address => M.Control_Buf, Import => True;
         Idx  : Natural := C.Index + 1;
      begin
         while Idx < M.Cap loop
            if Is_Live (Ctrl (Idx)) then
               return (Index => Idx);
            end if;
            Idx := @ + 1;
         end loop;
         return No_Element;
      end;
   end Next;

   function Has_Element (M : Map; C : Cursor) return Boolean is
      pragma Unreferenced (M);
   begin
      return C.Index >= 0;
   end Has_Element;

   function Key (M : Map; C : Cursor) return Key_Type is
      Slots : Slot_Array (0 .. M.Cap - 1)
        with Address => M.Slots_Buf, Import => True;
   begin
      return Slots (C.Index).Key;
   end Key;

   function Value (M : Map; C : Cursor) return Value_Type is
      Slots : Slot_Array (0 .. M.Cap - 1)
        with Address => M.Slots_Buf, Import => True;
   begin
      return Slots (C.Index).Val;
   end Value;

end Gada.Core.Maps;
