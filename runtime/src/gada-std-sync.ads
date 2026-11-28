--  Gada.Std.Sync — the Go `sync` package, ported (Phase 6 wave 2).
--
--  Each Go primitive is a tagged limited record (so Go's method calls
--  lower to Ada prefixed calls: `mu.Lock()` -> `Mu.Lock;`) wrapping a
--  protected core that holds the state plus a list of parked waiters.
--
--  Blocking is goroutine-aware. A goroutine (Scheduler.Current /=
--  No_Goroutine) that must wait registers itself on the core's waiter
--  list inside one protected action and then Scheduler.Park's — its
--  worker OS thread stays free to run other goroutines, exactly like
--  a channel receive (the Wait_Slot pattern in Gada.Async.Channels).
--  The releasing operation takes the waiter(s) off the list inside its
--  protected action and Unpark's them after it; a woken goroutine
--  re-checks (another caller may have barged in) and re-parks if
--  needed. Only a non-goroutine caller (the main task, a plain Ada
--  task) blocks on a protected entry, since it has no cothread to park.
--  No user code ever runs inside a protected action (Once.Do runs f
--  outside its core).
--
--  Mapping notes:
--    * Unlock of an unlocked mutex, RUnlock with no readers, and
--      WaitGroup counter underflow raise Constraint_Error — Go panics
--      on all three.
--    * Mutex is not fair (as in Go's normal mode): a woken waiter can
--      lose the lock to a newcomer and parks again.
--    * v1 RWMutex has no writer preference: a continuous reader
--      stream can starve a pending writer (Go blocks new readers
--      once a writer waits).
--    * Cond is built from a Mutex_Access (Go's L) plus an unbounded
--      channel and a protected waiter counter. v1 note: the token
--      channel can leave a stale token if a Signal lands in the
--      window between a woken waiter's Receive and its counter Dec —
--      i.e. Wait may return spuriously. As in Go, callers MUST loop
--      (`while not cond loop Wait (C); end loop;`). Wait requires the
--      caller to hold L (Go's contract) and releases it while parked.

with Ada.Containers.Doubly_Linked_Lists;
with Gada.Async.Channels.Unbounded;
with Gada.Async.Scheduler;

package Gada.Std.Sync is

   ---------------------------------------------------------------
   --  Mutex — Go's sync.Mutex
   ---------------------------------------------------------------

   type Mutex is tagged limited private;
   type Mutex_Access is access all Mutex;

   --  Go: func (m *Mutex) Lock() — waits until free (a goroutine
   --  parks; a non-goroutine caller blocks its task).
   procedure Lock (M : in out Mutex);
   --  Go: func (m *Mutex) Unlock() — panics if already unlocked.
   procedure Unlock (M : in out Mutex);
   --  Go: func (m *Mutex) TryLock() bool (Go 1.18) — never waits.
   function Try_Lock (M : in out Mutex) return Boolean;
   function Is_Locked (M : Mutex) return Boolean;

   ---------------------------------------------------------------
   --  RWMutex — Go's sync.RWMutex
   ---------------------------------------------------------------

   type RW_Mutex is tagged limited private;
   type RW_Mutex_Access is access all RW_Mutex;

   --  Write lock: waits while a writer holds it or any reader is
   --  active. Go: Lock().
   procedure Lock (M : in out RW_Mutex);
   --  Read lock: waits only while a writer holds it. Go: RLock().
   procedure R_Lock (M : in out RW_Mutex);
   --  Go: Unlock() — panics if no write lock held.
   procedure Unlock (M : in out RW_Mutex);
   --  Go: RUnlock() — panics if no read lock held.
   procedure R_Unlock (M : in out RW_Mutex);
   --  Go: TryLock() / TryRLock() bool — never wait.
   function Try_Lock (M : in out RW_Mutex) return Boolean;
   function Try_R_Lock (M : in out RW_Mutex) return Boolean;

   ---------------------------------------------------------------
   --  WaitGroup — Go's sync.WaitGroup
   ---------------------------------------------------------------

   type Wait_Group is tagged limited private;

   --  Go: Add(delta) — a negative delta may not drive the counter
   --  below zero (Go panics). Reaching zero releases every waiter.
   procedure Add (W : in out Wait_Group; Amount : Integer);
   --  Go: Done() == Add(-1).
   procedure Done (W : in out Wait_Group);
   --  Go: Wait() — waits until the counter is zero.
   procedure Wait (W : in out Wait_Group);
   function Value (W : Wait_Group) return Natural;

   ---------------------------------------------------------------
   --  Once — Go's sync.Once
   ---------------------------------------------------------------

   type Once is tagged limited private;

   --  Go: Do(f) — runs f exactly once across all callers; concurrent
   --  callers wait until that f has returned. f runs outside any
   --  protected action, and Done is set even if f raises (Go marks
   --  done via defer on the panic path too). ("do" is an Ada reserved
   --  word, so the compiler maps Go's Do to Do_K, like New_K / Is_K.)
   --  F is an anonymous access-to-procedure so a nested subprogram's
   --  'Access is accepted.
   procedure Do_K (O : in out Once; F : not null access procedure);

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
   end Waiter_Count;

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

private

   package Scheduler renames Gada.Async.Scheduler;

   package Waiter_Lists is new Ada.Containers.Doubly_Linked_Lists
     (Element_Type => Scheduler.Goroutine_Id,
      "="          => Scheduler."=");

   protected type Mutex_Core is
      --  Non-goroutine path.
      entry Lock_Blocking;
      --  Goroutine path: take the lock, or register G as a waiter.
      procedure Lock_Or_Enqueue (G : Scheduler.Goroutine_Id;
                                 Got : out Boolean);
      --  Release; Wake is the next parked waiter (No_Goroutine if none).
      procedure Unlock (Wake : out Scheduler.Goroutine_Id);
      procedure Try_Lock (Ok : out Boolean);
      function Is_Locked return Boolean;
   private
      Locked  : Boolean := False;
      Waiters : Waiter_Lists.List;
   end Mutex_Core;

   type Mutex is tagged limited record
      Core : Mutex_Core;
   end record;

   protected type RW_Core is
      entry Lock_Blocking;
      entry R_Lock_Blocking;
      procedure Lock_Or_Enqueue (G : Scheduler.Goroutine_Id;
                                 Got : out Boolean);
      procedure R_Lock_Or_Enqueue (G : Scheduler.Goroutine_Id;
                                   Got : out Boolean);
      --  Releases hand back every parked waiter (readers and writers
      --  re-check; whoever loses parks again).
      procedure Unlock (Wake : out Waiter_Lists.List);
      procedure R_Unlock (Wake : out Waiter_Lists.List);
      procedure Try_Lock (Ok : out Boolean);
      procedure Try_R_Lock (Ok : out Boolean);
   private
      Writer  : Boolean := False;
      Readers : Natural := 0;
      Waiters : Waiter_Lists.List;
   end RW_Core;

   type RW_Mutex is tagged limited record
      Core : RW_Core;
   end record;

   protected type WG_Core is
      procedure Add (Amount : Integer; Wake : out Waiter_Lists.List);
      entry Wait_Blocking;
      procedure Wait_Or_Enqueue (G : Scheduler.Goroutine_Id;
                                 Zero : out Boolean);
      function Value return Natural;
   private
      N       : Natural := 0;
      Waiters : Waiter_Lists.List;
   end WG_Core;

   type Wait_Group is tagged limited record
      Core : WG_Core;
   end record;

   type Once_State is (Idle, Running, Done);

   --  Outcome of a Claim: Run — the caller owns the one f call;
   --  Finished — f already completed; Wait — f is running elsewhere
   --  (a goroutine caller has been registered as a waiter).
   type Claim_Result is (Run, Finished, Wait);

   protected type Once_Core is
      procedure Claim (G : Scheduler.Goroutine_Id;
                       Result : out Claim_Result);
      procedure Finish (Wake : out Waiter_Lists.List);
      entry Await_Blocking;
   private
      State   : Once_State := Idle;
      Waiters : Waiter_Lists.List;
   end Once_Core;

   type Once is tagged limited record
      Core : Once_Core;
   end record;

end Gada.Std.Sync;
