--  Gada.Async.Context body — registry + trampoline pattern.
--
--  libco's `co_create` takes a parameterless C function pointer as the
--  entry. It does not give us a way to pass per-cothread state to that
--  entry, so the standard pattern (used by libco consumers including
--  Lua coroutines, mednafen, etc.) is:
--
--    1. Maintain a side table mapping cothread → user-supplied entry.
--    2. Install a static C-convention trampoline as the libco entry.
--    3. The trampoline calls co_active() to identify itself, looks up
--       its entry in the side table, and dispatches.
--
--  The table is one-shot per cothread: the trampoline removes its
--  entry on first run so a stack-recycled cothread address can't pick
--  up a stale procedure. (libco does not recycle cothread addresses
--  during a single OS thread's lifetime today, but the one-shot
--  behaviour is cheap insurance against a future libco that does.)
--
--  Concurrency: per Gada.Async.Context.Libco's caveat, libco itself is
--  single-thread-context — cothreads cannot be switched between OS
--  threads. The registry mirrors that constraint: it is a plain
--  thread-local-shaped global (one OS thread per Ada task in the
--  current runtime). The Phase 3 scheduler will replace this with a
--  per-worker structure once cross-thread routing is needed.

with Ada.Containers.Hashed_Maps;
with Ada.Unchecked_Conversion;
with Interfaces.C;
with System.Storage_Elements;

with Gada.Async.Context.Libco;

package body Gada.Async.Context is

   --  Hash an Address by treating it as an unsigned integer. libco's
   --  cothread allocations are page-aligned; using the raw bits is
   --  fine for the load factors we care about (entry-table size <=
   --  number of live goroutines, which is bounded by the scheduler).
   function Hash_Address
     (A : System.Address) return Ada.Containers.Hash_Type;

   function Hash_Address
     (A : System.Address) return Ada.Containers.Hash_Type
   is
      function To_Int is new Ada.Unchecked_Conversion
        (Source => System.Address,
         Target => System.Storage_Elements.Integer_Address);
   begin
      --  Hash_Type is a modular type ('Mod is the modular-reduction
      --  attribute), so 'Mod does the right thing across the
      --  truncation from a wider unsigned integer.
      return Ada.Containers.Hash_Type'Mod (To_Int (A));
   end Hash_Address;

   --  Note: Address equality is "=" by default, which compares bit
   --  patterns — exactly what we want here.
   package Entry_Maps is new Ada.Containers.Hashed_Maps
     (Key_Type        => System.Address,
      Element_Type    => Entry_Procedure,
      Hash            => Hash_Address,
      Equivalent_Keys => System."=");

   Entries : Entry_Maps.Map;

   --  C-convention trampoline. libco invokes this with no arguments;
   --  we rediscover ourselves via co_active() and dispatch to the
   --  user's entry.
   procedure Trampoline with Convention => C;

   procedure Trampoline is
      Self : constant System.Address := Libco.Co_Active;
      Ep   : Entry_Procedure := null;
   begin
      if Entries.Contains (Self) then
         Ep := Entries.Element (Self);
         Entries.Delete (Self);
      end if;
      if Ep /= null then
         Ep.all;
      end if;
      --  When Ep returns, the cothread's stack frame for Trampoline
      --  unwinds and libco hits "fell off the end of a cothread"
      --  territory. Behaviour is undefined per libco's contract;
      --  the public Make spec documents the same. The Phase 3
      --  scheduler will install a "yield to scheduler" stub at the
      --  tail to make this safe.
   end Trampoline;

   procedure Make
     (C           : out Context;
      Entry_Point : Entry_Procedure;
      Stack_Size  : Positive := 64 * 1024)
   is
      use type Libco.Cothread;
      New_Co : constant Libco.Cothread :=
        Libco.Co_Create
          (Stack_Size  => Interfaces.C.unsigned (Stack_Size),
           Entry_Point => Trampoline'Access);
   begin
      if New_Co = Libco.Null_Cothread then
         --  libco returns NULL on allocation failure (out of address
         --  space for the stack mapping, primarily). Surface as a
         --  Storage_Error so callers can choose to recover; the
         --  Phase 3 scheduler will catch this and report goroutine-
         --  spawn failure rather than crash.
         raise Storage_Error
           with "Gada.Async.Context.Make: co_create returned NULL";
      end if;
      Entries.Insert (Key => New_Co, New_Item => Entry_Point);
      C := Context (New_Co);
   end Make;

   function Active return Context is
   begin
      return Context (Libco.Co_Active);
   end Active;

   procedure Switch_To (Target : Context) is
   begin
      Libco.Co_Switch (System.Address (Target));
   end Switch_To;

   procedure Free (C : in out Context) is
   begin
      if C = Null_Context then
         return;
      end if;
      --  Drop any pending entry for this cothread (cothread freed
      --  before its first switch — uncommon but legal). Idempotent
      --  if the entry was already consumed by Trampoline.
      if Entries.Contains (System.Address (C)) then
         Entries.Delete (System.Address (C));
      end if;
      Libco.Co_Delete (System.Address (C));
      C := Null_Context;
   end Free;

end Gada.Async.Context;
