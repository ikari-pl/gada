--  Gada.Std.Sync — the Go `sync` package, ported (Phase 6 wave 2).
--
--  Go's sync primitives are built on Ada *protected objects*: the
--  protected type's mutual exclusion is exactly Go's mutex semantics,
--  and entry barriers give WaitGroup.Wait / Cond-style blocking for
--  free (an entry call parks the caller and re-evaluates its barrier
--  whenever any protected operation completes).
--
--  Mapping notes:
--    * sync.Mutex / RWMutex are protected types; Go's pointer-receiver
--      methods (func (m *Mutex) Lock) are the entry/procedure calls on
--      an aliased object or a Mutex_Access. Use the _Access forms for
--      anything heap-allocated or stored in a record.
--    * Unlock of an unlocked mutex, RUnlock with no readers, and
--      WaitGroup counter underflow raise Constraint_Error — Go panics
--      on all three.
--    * Cond is built from a Mutex_Access (Go's L) plus an unbounded
--      channel and a protected waiter counter, so Signal never leaves
--      a stale wakeup token. Wait requires the caller to hold L
--      (Go's contract) and releases it while parked.

with Gada.Async.Channels.Unbounded;

package Gada.Std.Sync is

   --  Parameterless procedure handle (Go's func() closures).
   type Procedure_Access is access procedure;

   ---------------------------------------------------------------
   --  Mutex — Go's sync.Mutex
   ---------------------------------------------------------------

   protected type Mutex is
      --  Go: func (m *Mutex) Lock() — blocks until free.
      entry Lock when not Locked;
      --  Go: func (m *Mutex) Unlock() — panics if already unlocked.
      procedure Unlock;
      --  Go: func (m *Mutex) TryLock() (Go 1.18) — never blocks.
      procedure Try_Lock (Ok : out Boolean);
      function Is_Locked return Boolean;
   private
      Locked : Boolean := False;
   end protected;

   type Mutex_Access is access all Mutex;

   ---------------------------------------------------------------
   --  RWMutex — Go's sync.RWMutex
   ---------------------------------------------------------------

   protected type RW_Mutex is
      --  Write lock: blocks while a writer holds it or any reader is
      --  active. Go: Lock().
      entry Lock when not Writer and then Readers = 0;
      --  Read lock: blocks only while a writer holds it. Go: RLock().
      entry R_Lock when not Writer;
      --  Go: Unlock() — panics if no write lock held.
      procedure Unlock;
      --  Go: RUnlock() — panics if no read lock held.
      procedure R_Unlock;
      procedure Try_Lock (Ok : out Boolean);
      procedure Try_R_Lock (Ok : out Boolean);
   private
      Writer  : Boolean := False;
      Readers : Natural := 0;
   end protected;

   type RW_Mutex_Access is access all RW_Mutex;

   ---------------------------------------------------------------
   --  WaitGroup — Go's sync.WaitGroup
   ---------------------------------------------------------------

   protected type Wait_Group is
      --  Go: Add(delta) — a negative delta may not drive the counter
      --  below zero (Go panics).
      procedure Add (Amount : Integer);
      --  Go: Done() == Add(-1).
      procedure Done;
      --  Go: Wait() — blocks until the counter reaches zero.
      entry Wait when N = 0;
      function Value return Natural;
   private
      N : Natural := 0;
   end protected;

   ---------------------------------------------------------------
   --  Once — Go's sync.Once
   ---------------------------------------------------------------

   protected type Once is
      --  Go: Do(f) — runs f exactly once across all callers, even if
      --  f raises (Go marks done via defer on the panic path too).
      --  ("do" is an Ada reserved word, so the compiler maps Go's Do
      --  to Do_K, like New_K / Is_K.)
      procedure Do_K (F : Procedure_Access);
   private
      Done_Flag : Boolean := False;
   end protected;

   ---------------------------------------------------------------
   --  Cond — Go's sync.Cond
   ---------------------------------------------------------------

   --  Waiters tracked so Signal/Broadcast only wake actual waiters
   --  (no stale tokens left in the channel for a later Wait).
   protected type Waiter_Count is
      procedure Inc;
      procedure Dec;
      function Value return Natural;
   private
      N : Natural := 0;
   end protected;

   package Unit_Channels is
      new Gada.Async.Channels.Unbounded (Boolean);

   type Cond is limited record
      L       : Mutex_Access;
      Ch      : Unit_Channels.Channel;
      Waiters : Waiter_Count;
   end record;

   --  Go: NewCond(l Locker) *Cond — heap form, like Go's pointer.
   type Cond_Access is access all Cond;

   function New_Cond (L : Mutex_Access) return Cond_Access;

   --  Go: Wait() — caller must hold C.L; releases it while parked,
   --  reacquires before returning.
   procedure Wait (C : in out Cond);
   --  Go: Signal() — wake one waiter, if any.
   procedure Signal (C : in out Cond);
   --  Go: Broadcast() — wake all current waiters.
   procedure Broadcast (C : in out Cond);

end Gada.Std.Sync;
