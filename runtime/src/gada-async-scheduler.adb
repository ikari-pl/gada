--  Gada.Async.Scheduler body — M:N over a fixed pool of Ada tasks.
--
--  Sub-items 3a + 3b + 3d of Phase 3. Ships:
--    * pool of Worker Ada tasks sized by System.Multiprocessors.Number_Of_CPUs
--      (overridable via Init (Workers => N)),
--    * shared FIFO run queue for fresh spawns,
--    * per-worker Inbox queue for yielded + Unparked goroutines (the
--      libco-pinning constraint forces yielded goroutines to stay on
--      the worker that first popped them; sub-item 3d's Unpark routes
--      via the same Inbox to preserve the same invariant),
--    * Spawn / Yield / Init / Shutdown / Park / Unpark.
--
--  Subsequent sub-items extend this body without breaking the public
--  spec: (c) replaces the per-worker protected Inbox with a Chase-Lev
--  deque (lockless) + work-stealing across siblings (steal-only-fresh-
--  spawns; bound goroutines stay pinned), (e) adds the syscall-handoff
--  API.
--
--  ## State-machine contract (the load-bearing invariant)
--
--  A goroutine yields control to its worker via cooperative Switch_To.
--  libco's co_switch is opaque — there is no in-band signal that says
--  "I yielded vs I'm done vs I parked". So both sides write to the
--  goroutine's State enum *before* switching, and the worker reads it
--  *after* Switch_To returns:
--
--    READY    — Spawn'd or just-Unpark'd, in queue, waiting to run
--    RUNNING  — worker switched in, currently on the libco stack
--    YIELDED  — Yield wrote this then Switch_To'd back to the worker;
--               worker re-enqueues to its own Inbox
--    PARKED   — Park wrote this then Switch_To'd back; worker leaves
--               G in limbo (no queue) until external Unpark re-enqueues
--    DONE     — Trampoline-tail wrote this when the body returned
--               naturally (see Gada.Async.Context's tail-stub from
--               sub-item 2f); next worker step reaps the goroutine.
--
--  Without the State write the worker would have no way to tell
--  yielded-resume from finished-reap from parked-suspend.
--
--  ## Goroutine pinning (sub-item 3b foundation, 3d Unpark routing)
--
--  libco's per-arch context save/restore is per-OS-thread (per
--  ADR-0007 §4 and the vendored README): once a cothread has been
--  switched into on OS thread T, it cannot be resumed on any other
--  thread without UB. Sub-item 3b made this a structural property
--  of the scheduler: yielded goroutines stay on the worker that
--  first popped them, via a per-worker queue.
--
--  Sub-item 3d extends the same invariant to Park/Unpark. A goroutine's
--  Bound_Worker field is set when a worker first pops it from the
--  shared Run_Queue; subsequent re-injections (YIELDED → Inbox,
--  PARKED → Unpark → Inbox) go to *that* worker's Inbox, never
--  another's. Unpark on a never-run goroutine raises Program_Error
--  rather than guess a worker — there's no correct guess.
--
--  See docs/incidents/2026-05-03-scheduler-3b-multi-worker-race.md
--  for the full rationale, including the C-side -DLIBCO_MP fix that
--  was the actual root cause behind the earlier flake pattern.
--
--  ## TLS for Current_Goroutine
--
--  pragma Thread_Local_Storage on a package-level pointer (vs the
--  earlier Ada.Task_Attributes shape that had RM C.7.2 issues under
--  concurrent Set_Value from N worker tasks). Each Ada task on hosted
--  GNAT is its own OS thread, so each worker reads/writes its own
--  private slot.
--
--  ## Layering
--
--  This body imports Gada.Async.Context (its peer in Gada.Async,
--  permitted by ADR-0002's runtime layering), System.Multiprocessors
--  for CPU count introspection, and Ada.Containers for the queues.

with Ada.Containers.Doubly_Linked_Lists;
with Ada.Unchecked_Deallocation;
with System.Multiprocessors;

with Gada.Async.Context;

package body Gada.Async.Scheduler is

   --  ## Worker indexing
   --
   --  Workers are numbered 1..Number_Of_CPUs (or whatever Init
   --  receives). Max_Workers is a static upper bound — no realistic
   --  hosted target has 256 cores and Phase 3's scheduler doesn't
   --  oversubscribe (1 worker per CPU). The bound is needed because
   --  the Run_Queue protected uses an entry family `Pop
   --  (Active_Worker_Index)` whose range must be statically known
   --  (entry families can't be discriminated on a runtime value).
   --
   --  Worker_Index 0 is the "Unbound" sentinel — a goroutine that
   --  has never run on any worker yet. The worker that first pops
   --  it from the shared Run_Queue stamps Bound_Worker := Idx, and
   --  thereafter all queue routing goes to that worker's Inbox.
   --  Active_Worker_Index excludes 0 so the Inbox array index and
   --  Worker_Task discriminant are statically valid.

   Max_Workers : constant := 256;
   type Worker_Index is new Natural range 0 .. Max_Workers;
   subtype Active_Worker_Index is Worker_Index range 1 .. Max_Workers;
   Unbound : constant Worker_Index := 0;

   --  ## Goroutine_Record — see file header for the State-machine
   --  contract and the pinning invariant. pragma Atomic on State is
   --  the seq-cst fence between goroutine-side writes (Yield/Park
   --  → YIELDED/PARKED, Trampoline-tail → DONE) and worker-side
   --  reads (post-Switch_To classification). Worker_Ctx and
   --  Body_Proc go through Run_Queue's protected barriers and don't
   --  need the same treatment.

   type Goroutine_State is (READY, RUNNING, YIELDED, PARKED, DONE);

   type Goroutine_Record is record
      Ctx          : Gada.Async.Context.Context :=
                       Gada.Async.Context.Null_Context;
      Body_Proc    : Goroutine_Body := null;
      State        : Goroutine_State := READY;
      pragma Atomic (State);
      Worker_Ctx   : Gada.Async.Context.Context :=
                       Gada.Async.Context.Null_Context;
      --  Worker_Ctx — the address of the worker's own libco context.
      --  Yield/Park reads it to know who to Switch_To back to.
      --  Recorded by the worker right before each Switch_To-into.
      Bound_Worker : Worker_Index := Unbound;
      --  Bound_Worker — the OS thread (= Worker_Task) this goroutine
      --  is libco-bound to. Set on first pop from shared Run_Queue;
      --  read by Unpark to route the goroutine back to the correct
      --  worker's Inbox.
   end record;

   procedure Free_Goroutine is
     new Ada.Unchecked_Deallocation
       (Object => Goroutine_Record, Name => Goroutine_Access);

   --  Per-OS-thread "currently running goroutine" pointer. See file
   --  header.
   Current_Goroutine : Goroutine_Access := null;
   pragma Thread_Local_Storage (Current_Goroutine);

   --  ## Run queue
   --
   --  Single static protected with two layers of state:
   --    1. Items — shared FIFO of fresh spawns (any worker may pop).
   --    2. Inboxes — per-worker FIFO of bound goroutines (only the
   --       owning worker pops, but any task may inject — Yield from
   --       the worker itself, Unpark from anywhere).
   --
   --  The Pop entry is a *family* indexed by Active_Worker_Index:
   --  worker N calls Pop(N), and its barrier is "this worker's Inbox
   --  has work, OR the shared Items queue has work, OR the scheduler
   --  is shutting down with no in-flight goroutines". When new work
   --  arrives in Inboxes(5), only Pop(5)'s barrier becomes true and
   --  only worker 5 wakes; when work arrives in Items, all workers'
   --  barriers become true and the runtime serves one (Ada FIFO).
   --
   --  Sub-item 3c replaces the per-worker Inbox with a Chase-Lev
   --  deque (lockless) for cache-locality on the per-worker push/pop
   --  hot path. Until then, the protected serialisation is sufficient
   --  (lock held microseconds per call).

   package Goroutine_Lists is new Ada.Containers.Doubly_Linked_Lists
     (Element_Type => Goroutine_Access);

   type Inbox_Array is array (Active_Worker_Index) of Goroutine_Lists.List;

   protected Run_Queue is
      --  Inject is the public-facing Spawn path; bumps In_Flight and
      --  appends to the shared FIFO Items. Any worker may pop.
      procedure Inject (G : Goroutine_Access);

      --  Inject_Local routes G to a specific worker's Inbox. Used by:
      --    * Worker's own YIELDED case-arm (re-enqueue self-yielded G);
      --    * Unpark from any task (re-enqueue an externally-suspended G).
      --  Does NOT touch In_Flight — the goroutine is still alive,
      --  just changing queues.
      procedure Inject_Local (Idx : Active_Worker_Index;
                              G   : Goroutine_Access);

      --  Reap notes a goroutine finished (State => DONE, worker
      --  Free'd it). Decrements In_Flight; may unblock Drain.
      procedure Reap;

      --  Pop is an entry family — each worker calls Pop(its_Idx).
      --  Body prefers the worker's own Inbox, falls through to the
      --  shared FIFO, finally reports Stop=True under shutdown.
      entry Pop (Active_Worker_Index)
        (G : out Goroutine_Access; Stop : out Boolean);

      --  Mark_Shutdown is called by Shutdown; subsequent Inject calls
      --  are still legal (a goroutine may spawn a child as part of its
      --  shutdown work) but the worker exits when In_Flight = 0 and
      --  every queue (shared + own Inbox) is empty.
      procedure Mark_Shutdown;

      --  Workers_Started / Workers_Stopped track live worker tasks so
      --  Shutdown can reliably wait for the last one to finish before
      --  returning.
      procedure Worker_Started;
      procedure Worker_Stopped;

      --  Drain blocks until every worker has exited. The combination
      --  Mark_Shutdown + Drain is the join the public Shutdown
      --  procedure exposes.
      entry Drain;

      function Is_Initialised return Boolean;
      procedure Set_Initialised (V : Boolean);

      --  Reset lifecycle state at Init time. Without this, Shutting_Down
      --  carries across Init/Shutdown cycles and the very next worker
      --  pops Stop=True from an empty-but-shutting-down queue, exiting
      --  before processing the goroutines a fresh Spawn would inject.
      --  Also clears all per-worker Inboxes (paranoid; they should be
      --  empty post-Shutdown but a goroutine that ended in PARKED with
      --  no Unpark would leak otherwise).
      procedure Reset_Lifecycle;

   private
      Items          : Goroutine_Lists.List;
      Inboxes        : Inbox_Array;
      In_Flight      : Natural := 0;
      Shutting_Down  : Boolean := False;
      Workers_Active : Natural := 0;
      Initialised    : Boolean := False;
   end Run_Queue;

   protected body Run_Queue is

      procedure Inject (G : Goroutine_Access) is
      begin
         In_Flight := In_Flight + 1;
         Items.Append (G);
      end Inject;

      procedure Inject_Local (Idx : Active_Worker_Index;
                              G   : Goroutine_Access) is
      begin
         Inboxes (Idx).Append (G);
      end Inject_Local;

      procedure Reap is
      begin
         In_Flight := In_Flight - 1;
      end Reap;

      entry Pop (for Idx in Active_Worker_Index)
        (G : out Goroutine_Access; Stop : out Boolean)
        when not Inboxes (Idx).Is_Empty
          or else not Items.Is_Empty
          or else (Shutting_Down and then In_Flight = 0)
      is
      begin
         if not Inboxes (Idx).Is_Empty then
            G := Inboxes (Idx).First_Element;
            Inboxes (Idx).Delete_First;
            Stop := False;
         elsif not Items.Is_Empty then
            G := Items.First_Element;
            Items.Delete_First;
            Stop := False;
         else
            G := null;
            Stop := True;
         end if;
      end Pop;

      procedure Mark_Shutdown is
      begin
         Shutting_Down := True;
      end Mark_Shutdown;

      procedure Worker_Started is
      begin
         Workers_Active := Workers_Active + 1;
      end Worker_Started;

      procedure Worker_Stopped is
      begin
         Workers_Active := Workers_Active - 1;
      end Worker_Stopped;

      entry Drain when Workers_Active = 0 is
      begin
         null;
         --  No state to mutate; the entry guard *is* the wait.
      end Drain;

      function Is_Initialised return Boolean is (Initialised);

      procedure Set_Initialised (V : Boolean) is
      begin
         Initialised := V;
      end Set_Initialised;

      procedure Reset_Lifecycle is
      begin
         Shutting_Down := False;
         In_Flight := 0;
         while not Items.Is_Empty loop
            Items.Delete_First;
         end loop;
         for Idx in Active_Worker_Index loop
            while not Inboxes (Idx).Is_Empty loop
               Inboxes (Idx).Delete_First;
            end loop;
         end loop;
      end Reset_Lifecycle;

   end Run_Queue;

   --  ## Trampoline body for goroutines
   --
   --  Runs on the goroutine's libco stack. The Spawn'd Body_Proc is
   --  dispatched here; on its natural return we set State => DONE before
   --  letting the Gada.Async.Context tail-stub bounce back to the worker.
   --  Reads Current_Goroutine via TLS — per the pinning invariant the
   --  goroutine runs on the same OS thread as the worker that just
   --  Switch_To'd into it.

   procedure Goroutine_Trampoline;

   procedure Goroutine_Trampoline is
      G : constant Goroutine_Access := Current_Goroutine;
   begin
      if G /= null and then G.Body_Proc /= null then
         G.Body_Proc.all;
         G.State := DONE;
      end if;
   end Goroutine_Trampoline;

   --  ## Worker task
   --
   --  Each Worker_Task carries its Idx as a discriminant so it can call
   --  Run_Queue.Pop (Idx) on the right entry family instance and
   --  Inject_Local (Idx, G) on the right inbox.

   task type Worker_Task (Idx : Active_Worker_Index);

   task body Worker_Task is
      G    : Goroutine_Access;
      Stop : Boolean;
   begin
      loop
         Run_Queue.Pop (Idx) (G, Stop);
         exit when Stop;

         --  First pop binds the goroutine to this worker. Subsequent
         --  re-enqueues (YIELDED → own Inbox, PARKED → external
         --  Unpark → own Inbox) preserve this binding so libco
         --  cothreads stay on the OS thread that allocated their
         --  saved register state.
         if G.Bound_Worker = Unbound then
            G.Bound_Worker := Idx;
         end if;

         G.Worker_Ctx := Gada.Async.Context.Active;
         Current_Goroutine := G;

         G.State := RUNNING;
         Gada.Async.Context.Switch_To (G.Ctx);

         Current_Goroutine := null;

         case G.State is
            when YIELDED =>
               G.State := READY;
               Run_Queue.Inject_Local (Idx, G);
            when PARKED =>
               --  G is held by whoever owns its Goroutine_Id; Unpark
               --  will Inject_Local (Idx, G) when ready. Worker just
               --  picks up the next item without re-enqueueing.
               null;
            when DONE =>
               Gada.Async.Context.Free (G.Ctx);
               Free_Goroutine (G);
               Run_Queue.Reap;
            when others =>
               --  RUNNING / READY here would mean libco returned
               --  without any of our writes firing — impossible under
               --  the cooperative protocol.
               raise Program_Error
                 with "Gada.Async.Scheduler: goroutine returned in"
                      & " unexpected state " & G.State'Image;
         end case;
      end loop;
      Run_Queue.Worker_Stopped;
   end Worker_Task;

   type Worker_Access is access Worker_Task;
   type Worker_Array is array (Active_Worker_Index range <>)
     of Worker_Access;
   type Worker_Array_Access is access Worker_Array;

   --  Worker pool. Sized at Init, torn down at Shutdown. Setting to
   --  null at Shutdown lets Boehm's GC reclaim the array storage; the
   --  individual Worker_Task objects are similarly handled by the GC
   --  once the runtime declares them terminated.
   The_Workers : Worker_Array_Access := null;

   --  ## Public-API implementations

   procedure Init (Workers : Natural := 0) is
      Effective_Workers : constant Active_Worker_Index :=
        (if Workers = 0
         then Active_Worker_Index
                (System.Multiprocessors.Number_Of_CPUs)
         else Active_Worker_Index (Workers));
   begin
      if Run_Queue.Is_Initialised then
         raise Program_Error
           with "Gada.Async.Scheduler.Init called twice without Shutdown";
      end if;
      Run_Queue.Reset_Lifecycle;
      Run_Queue.Set_Initialised (True);
      The_Workers := new Worker_Array (1 .. Effective_Workers);

      --  Bump Workers_Active *before* allocating each task so a Shutdown
      --  that fires before that task gets CPU time still waits — the
      --  Drain entry guard is Workers_Active = 0, and a worker that
      --  hasn't started yet (so Worker_Started hasn't run) would have
      --  let the guard fire prematurely. Worker_Stopped runs at the
      --  tail of Worker_Task and balances each bump.
      --
      --  Roll back the lifecycle counters if a task allocation
      --  itself raises (Storage_Error on a tight task-storage budget,
      --  Tasking_Error on policy mismatch). The just-bumped-but-not-
      --  allocated counter is undone with Worker_Stopped; any
      --  successfully-allocated workers are sent the Mark_Shutdown +
      --  Drain shutdown sequence so they exit their loops cleanly.
      begin
         for I in 1 .. Effective_Workers loop
            Run_Queue.Worker_Started;
            The_Workers (I) := new Worker_Task (Idx => I);
         end loop;
      exception
         when others =>
            Run_Queue.Worker_Stopped;
            Run_Queue.Mark_Shutdown;
            Run_Queue.Drain;
            The_Workers := null;
            Run_Queue.Set_Initialised (False);
            raise;
      end;
   end Init;

   function Spawn (Body_Proc : Goroutine_Body) return Goroutine_Id is
      G : Goroutine_Access := new Goroutine_Record;
   begin
      --  Both failure paths below — Init not called, or libco's
      --  co_create raising Storage_Error inside Make — would otherwise
      --  leak the just-allocated Goroutine_Record. Free it explicitly
      --  before re-raising.
      if not Run_Queue.Is_Initialised then
         Free_Goroutine (G);
         raise Program_Error
           with "Gada.Async.Scheduler.Spawn called before Init";
      end if;
      G.Body_Proc := Body_Proc;
      G.State := READY;
      begin
         Gada.Async.Context.Make
           (G.Ctx, Goroutine_Trampoline'Access);
      exception
         when others =>
            Free_Goroutine (G);
            raise;
      end;
      Run_Queue.Inject (G);
      return (Ref => G);
   end Spawn;

   procedure Yield is
      G : constant Goroutine_Access := Current_Goroutine;
   begin
      if G = null then
         --  Called from a non-goroutine context (main task before
         --  Spawn, or a non-worker task post-Init). Documented no-op.
         return;
      end if;
      G.State := YIELDED;
      Gada.Async.Context.Switch_To (G.Worker_Ctx);
   end Yield;

   procedure Park is
      G : constant Goroutine_Access := Current_Goroutine;
   begin
      if G = null then
         --  Called from a non-goroutine context. Documented no-op so
         --  generated code can call Park unconditionally.
         return;
      end if;
      G.State := PARKED;
      Gada.Async.Context.Switch_To (G.Worker_Ctx);
      --  Resumed: an external Unpark Inject_Local'd us back to our
      --  bound worker's Inbox; that worker's Pop returned us; the
      --  worker stamped State => RUNNING and Switch_To'd into us.
      --  Body continues from this point.
   end Park;

   procedure Unpark (G : Goroutine_Id) is
   begin
      if G.Ref = null then
         --  No_Goroutine handle; documented no-op.
         return;
      end if;
      if G.Ref.Bound_Worker = Unbound then
         --  Goroutine has never run on any worker, so we don't know
         --  which Inbox to route to. The corresponding Park can only
         --  have been called from inside the goroutine body, which
         --  means the goroutine has run at least once and its
         --  Bound_Worker is set. An Unpark of an unbound goroutine
         --  is a contract violation by the caller.
         raise Program_Error
           with "Gada.Async.Scheduler.Unpark: goroutine has not yet run "
                & "on any worker; Unpark may only be called after the "
                & "goroutine has called Park (or otherwise yielded)";
      end if;
      G.Ref.State := READY;
      Run_Queue.Inject_Local (G.Ref.Bound_Worker, G.Ref);
   end Unpark;

   procedure Shutdown is
   begin
      if not Run_Queue.Is_Initialised then
         return;  --  idempotent half-init / half-teardown
      end if;
      Run_Queue.Mark_Shutdown;
      Run_Queue.Drain;
      Run_Queue.Set_Initialised (False);
      The_Workers := null;
   end Shutdown;

end Gada.Async.Scheduler;
