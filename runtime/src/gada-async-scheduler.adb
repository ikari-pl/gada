--  Gada.Async.Scheduler body — M:N over a fixed pool of Ada tasks.
--
--  Sub-items 3a + 3b of Phase 3. Ships the multi-worker shape: a pool
--  of Worker Ada tasks sized by System.Multiprocessors.Number_Of_CPUs
--  (overridable via Init (Workers => N)), each draining a shared FIFO
--  queue of fresh spawns plus a *private* yielded-goroutines queue.
--
--  Subsequent sub-items extend this body without breaking the public
--  spec: (c) replaces the per-worker Local list with a Chase-Lev
--  deque + work-stealing across siblings, (d) adds Park/Unpark, (e)
--  adds the syscall-handoff API.
--
--  ## State-machine contract (the load-bearing invariant)
--
--  A goroutine yields control to its worker via cooperative Switch_To.
--  libco's co_switch is opaque — there is no in-band signal that says
--  "I yielded vs I'm done". So both sides write to the goroutine's
--  State enum *before* switching, and the worker reads it *after*
--  Switch_To returns:
--
--    READY    — Spawn'd, in queue, never run
--    RUNNING  — worker switched in, currently on the libco stack
--    YIELDED  — Yield wrote this then Switch_To'd back to the worker
--    DONE     — Trampoline-tail wrote this when the body returned
--               naturally (see Gada.Async.Context's tail-stub from
--               sub-item 2f); next worker step reaps the goroutine.
--
--  Without the State write the worker would have no way to tell
--  "park me, I want to run again" from "free my stack, I'm done".
--
--  ## Goroutine pinning (sub-item 3b)
--
--  libco's per-arch context save/restore is per-OS-thread (per
--  ADR-0007 §4 and the vendored README): once a cothread has been
--  switched into on OS thread T, it cannot be resumed on any other
--  thread without UB. The earlier multi-worker attempt (incident
--  retro 2026-05-03-scheduler-3b-multi-worker-race) re-pushed yielded
--  goroutines onto the shared queue and surfaced flakes from this
--  exact UB.
--
--  This sub-item pins yielded goroutines to the worker that first
--  popped them: each Worker_Task owns a *private* Doubly_Linked_Lists
--  Local queue, and the YIELDED arm of the worker loop pushes onto
--  Local rather than Re_Push'ing onto the shared queue. The worker
--  loop checks Local before going back to the shared Run_Queue's Pop
--  entry, so a goroutine that yields a million times runs all million
--  iterations on the same OS thread — exactly what libco requires.
--
--  Sub-item (c) replaces this with a Chase-Lev deque + work-stealing
--  across siblings — but stealing-from-sibling is fundamentally a
--  cothread-migration concern that the deque alone cannot solve;
--  (c) will need to track which goroutines are libco-bound to which
--  worker and only steal *unbound* (never-yet-run) ones.
--
--  ## TLS for Current_Goroutine (sub-item 3b Prereq B)
--
--  The earlier sub-item 3a body used Ada.Task_Attributes for the
--  per-worker "currently running goroutine" pointer. That facility's
--  thread-safety contract under concurrent Set_Value from N tasks is
--  weaker than it looks: RM C.7.2 doesn't require it to be task-safe,
--  and GNAT FSF's implementation uses a global-hash-keyed-on-Task_Id
--  that races on its internal table when N workers concurrently
--  Set_Value their own task-attribute. The race manifests downstream
--  as either a Constraint_Error in Gada.Async.Context.Lookup_Exit
--  (worker A's `Self` not in the Exits map because the recorded
--  Task_Id was misidentified) or a hang in Drain (a goroutine reads
--  Current_Goroutine = null on its own stack and the worker waits
--  forever for a Switch_To that never comes).
--
--  pragma Thread_Local_Storage is the GNAT-specific facility that
--  compiles to an OS-level TLS slot (pthread_key on Linux/macOS) per
--  thread — no global hash, no concurrent-write race, no Task_Id
--  lookup. Each Ada task on hosted GNAT is its own OS thread, so
--  each worker reads/writes its own private slot. Trampolined
--  goroutine code reads this slot on the goroutine's libco stack:
--  per the pinning invariant above, the goroutine runs on the same
--  OS thread as the worker that switched in, so the slot the
--  goroutine sees is exactly the one the worker just wrote.
--
--  The full investigation: docs/incidents/2026-05-03-scheduler-3b-
--  multi-worker-race.md.
--
--  ## Layering
--
--  This body imports Gada.Async.Context (its peer in Gada.Async,
--  permitted by ADR-0002's runtime layering), System.Multiprocessors
--  for CPU count introspection, and Ada.Containers for the queue. It
--  does NOT import Ada.Task_Attributes (see Prereq B above), nor
--  Gada.Async.Channels / Gada.Async.Select / Gada.Async.Std — they
--  don't exist yet, and the dependency direction in the layer graph
--  forbids them anyway.

with Ada.Containers.Doubly_Linked_Lists;
with Ada.Unchecked_Deallocation;
with System.Multiprocessors;

with Gada.Async.Context;

package body Gada.Async.Scheduler is

   --  ## Goroutine_Record
   --
   --  Heap-allocated, owned by the scheduler. Lifetime: from Spawn to
   --  the worker reaping it (after the body returned and State => DONE).
   --
   --  Multi-worker means N OS threads can read/write State for goroutines
   --  being handed off through Park/Unpark, work-stealing, and syscall
   --  handoff (sub-items 3c-3e). The protected `Run_Queue` mediates
   --  *queue* membership for fresh spawns, but the field itself is touched
   --  directly between goroutine-side writes (Yield → YIELDED, Trampoline-
   --  tail → DONE) and worker-side reads (post-Switch_To classification)
   --  — the protected object is no longer in the chain.
   --
   --  `pragma Atomic` is the right size of fence here:
   --    - Goroutine_State is 4 values → 1 byte → trivially atomic on
   --      every supported arch (aarch64 / x86_64);
   --    - the pragma upgrades the access to *sequentially consistent*
   --      load/store, which is what the worker's "see the latest
   --      State the goroutine wrote" needs;
   --    - it is one line at the field declaration vs. a manual fence
   --      at every read/write site — the per-call cost is the same
   --      single LDARB / STLRB on aarch64, but the source-level
   --      bookkeeping is `pragma`-local.
   --
   --  Worker_Ctx and Body_Proc do *not* need this treatment:
   --    - Body_Proc is written once at Spawn and read inside the
   --      Trampoline; both sides cross the protected `Run_Queue.Inject`
   --      / `Run_Queue.Pop` barrier, which orders the write before
   --      the read.
   --    - Worker_Ctx is overwritten by the picking worker on every
   --      iteration *before* Switch_To-into the goroutine, and the
   --      Switch_To call goes through Gada.Async.Context's own
   --      protected `State` (Record_Exit_If_Absent / Lookup_Exit) —
   --      that protected call provides the same write-then-fence-
   --      then-Switch_To shape as the State write would, so by the
   --      time the goroutine resumes inside Yield and reads
   --      Worker_Ctx, the worker's write is visible.
   --
   --  See docs/incidents/2026-05-03-scheduler-3a-concurrency-bugs.md
   --  hazard #6 for the full reasoning.

   type Goroutine_State is (READY, RUNNING, YIELDED, DONE);

   type Goroutine_Record is record
      Ctx        : Gada.Async.Context.Context :=
                     Gada.Async.Context.Null_Context;
      Body_Proc  : Goroutine_Body := null;
      State      : Goroutine_State := READY;
      pragma Atomic (State);
      Worker_Ctx : Gada.Async.Context.Context :=
                     Gada.Async.Context.Null_Context;
      --  Worker_Ctx is the address of the worker's own libco context.
      --  Yield reads it to know who to Switch_To back to. Recorded by
      --  the worker right before each Switch_To-into the goroutine —
      --  pinning the *most recent* worker that ran us. Under the
      --  pinning rule (above), once a goroutine has yielded once, it
      --  always resumes on the same worker and Worker_Ctx is stable.
   end record;

   procedure Free_Goroutine is
     new Ada.Unchecked_Deallocation
       (Object => Goroutine_Record, Name => Goroutine_Access);

   --  Per-OS-thread "currently running goroutine" pointer. See the file
   --  header's "TLS for Current_Goroutine" section for why this is a
   --  pragma Thread_Local_Storage variable rather than the obvious
   --  Ada.Task_Attributes shape.
   --
   --  Initialised to null so a non-worker task that calls Yield (e.g.
   --  the main task before any goroutine runs) reads null and the
   --  Yield no-op kicks in.
   Current_Goroutine : Goroutine_Access := null;
   pragma Thread_Local_Storage (Current_Goroutine);

   --  ## Run queue
   --
   --  Shared FIFO across all workers, used for fresh spawns and as the
   --  Drain barrier. Yielded goroutines do NOT come back here (see the
   --  pinning section in the file header). Sub-item (c) replaces the
   --  global queue with per-worker Chase-Lev deques + a small global
   --  injection queue for cross-worker spawns. Doubly_Linked_Lists is
   --  cheap to push at the tail and pop at the head; we never iterate.

   package Goroutine_Lists is new Ada.Containers.Doubly_Linked_Lists
     (Element_Type => Goroutine_Access);

   protected Run_Queue is
      --  Inject is the public-facing Spawn path; bumps In_Flight.
      procedure Inject (G : Goroutine_Access);

      --  Reap notes a goroutine finished (State => DONE, worker
      --  Free'd it). Decrements In_Flight; may unblock Drain.
      procedure Reap;

      --  Pop blocks until either work is available OR the queue is
      --  shutting down with no remaining in-flight work. Stop = True
      --  signals the worker to exit its task body cleanly. (Named
      --  Stop rather than Done to avoid clashing with Goroutine_State
      --  literal DONE — Ada is case-insensitive on identifiers.)
      entry Pop (G : out Goroutine_Access; Stop : out Boolean);

      --  Mark_Shutdown is called by Shutdown; subsequent Inject calls
      --  are still legal (a goroutine may spawn a child as part of its
      --  shutdown work) but the worker exits when In_Flight = 0.
      procedure Mark_Shutdown;

      --  Workers_Started / Workers_Stopped track live worker tasks so
      --  Shutdown can reliably wait for the last one to finish its
      --  Reap before returning.
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
      procedure Reset_Lifecycle;

   private
      Items          : Goroutine_Lists.List;
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

      procedure Reap is
      begin
         In_Flight := In_Flight - 1;
      end Reap;

      entry Pop (G : out Goroutine_Access; Stop : out Boolean)
        when not Items.Is_Empty
          or else (Shutting_Down and then In_Flight = 0)
      is
      begin
         if Items.Is_Empty then
            G := null;
            Stop := True;
         else
            G := Items.First_Element;
            Items.Delete_First;
            Stop := False;
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
         --  Items should already be empty post-Shutdown but be defensive.
         while not Items.Is_Empty loop
            Items.Delete_First;
         end loop;
      end Reset_Lifecycle;

   end Run_Queue;

   --  ## Trampoline body for goroutines
   --
   --  Runs on the goroutine's libco stack. The Spawn'd Body_Proc is
   --  dispatched here; on its natural return we set State => DONE before
   --  letting the Gada.Async.Context tail-stub bounce back to the worker.
   --  The State write is the *only* signal the worker has to distinguish
   --  "yielded" (re-enqueue) from "done" (reap).
   --
   --  Reads Current_Goroutine via TLS. Per the pinning invariant the
   --  goroutine runs on the same OS thread as the worker that just
   --  Switch_To'd into it, so the slot we read here is exactly the one
   --  the worker wrote a few instructions ago.

   procedure Goroutine_Trampoline;

   procedure Goroutine_Trampoline is
      G : constant Goroutine_Access := Current_Goroutine;
   begin
      if G /= null and then G.Body_Proc /= null then
         G.Body_Proc.all;
         G.State := DONE;
      end if;
      --  Falling out here triggers Gada.Async.Context's Trampoline
      --  tail-stub (sub-item 2f), which Co_Switches back to the worker
      --  via the Exits map. The worker reads G.State = DONE and reaps.
   end Goroutine_Trampoline;

   --  ## Worker task
   --
   --  The execution loop: prefer-local-pop, else shared-pop, switch in,
   --  classify on return, repeat. Local is a private Doubly_Linked_Lists
   --  list on the worker's stack — no protection needed because only
   --  this worker accesses it (yielded goroutines are pinned here per
   --  the libco-cothread-cannot-migrate invariant).

   task type Worker_Task;

   task body Worker_Task is
      G     : Goroutine_Access;
      Stop  : Boolean;
      Local : Goroutine_Lists.List;
   begin
      --  Note: Worker_Started is called by Init *before* this task is
      --  allocated, not here. The reason is a tiny but real race: if
      --  Init returned before the freshly-allocated task got CPU time
      --  to call Worker_Started, the very next Shutdown's Drain (whose
      --  guard is Workers_Active = 0) would fire immediately and
      --  Shutdown would return with the worker still asleep behind it.
      --  Bumping Workers_Active synchronously in Init fixes that.
      loop
         --  Prefer this worker's pinned-yielded queue before going to
         --  the shared FIFO. A goroutine that just yielded must come
         --  back to *this* OS thread (libco invariant) — taking it
         --  from Local guarantees that without serialising on the
         --  shared protected.
         if not Local.Is_Empty then
            G := Local.First_Element;
            Local.Delete_First;
            Stop := False;
         else
            Run_Queue.Pop (G, Stop);
            exit when Stop;
         end if;

         --  Stage the per-worker context for Yield's lookup. Done
         --  every iteration because a goroutine's *first* run binds
         --  it to this OS thread but the Worker_Ctx field at that
         --  point is whatever the spawning context recorded (or
         --  Null_Context); we overwrite it here with our own
         --  Active context so the yield-back path goes to us.
         G.Worker_Ctx := Gada.Async.Context.Active;
         Current_Goroutine := G;

         --  First switch into a freshly-Spawn'd goroutine bootstraps
         --  Goroutine_Trampoline (which runs Body_Proc); subsequent
         --  switches resume the goroutine wherever it Yield'd from.
         G.State := RUNNING;
         Gada.Async.Context.Switch_To (G.Ctx);

         --  Goroutine handed control back. Either Yield (re-enqueue
         --  to Local for next-iteration pickup on this same worker)
         --  or natural return (reap). State is the source of truth.
         Current_Goroutine := null;

         case G.State is
            when YIELDED =>
               G.State := READY;
               Local.Append (G);
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
   type Worker_Array is array (Positive range <>) of Worker_Access;
   type Worker_Array_Access is access Worker_Array;

   --  Worker pool. Sized at Init, torn down at Shutdown. Setting to
   --  null at Shutdown lets Boehm's GC reclaim the array storage; the
   --  individual Worker_Task objects are similarly handled by the GC
   --  once the runtime declares them terminated (see the Shutdown
   --  body for the rationale on not Unchecked_Deallocate-ing them).
   The_Workers : Worker_Array_Access := null;

   --  ## Public-API implementations

   procedure Init (Workers : Natural := 0) is
      Effective_Workers : constant Positive :=
        (if Workers = 0
         then Positive (System.Multiprocessors.Number_Of_CPUs)
         else Workers);
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
      --  Without this, the next Init would see Initialised => True
      --  and raise "called twice", and a Shutdown would Drain forever
      --  waiting for a worker that was never spawned.
      --  (PR #3 review feedback, gemini-code-assist; lifted to the
      --  multi-worker shape in 3b.)
      begin
         for I in 1 .. Effective_Workers loop
            Run_Queue.Worker_Started;
            The_Workers (I) := new Worker_Task;
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
      --  before re-raising; the Boehm GC would eventually reclaim it,
      --  but a deterministic free narrows the failure-mode surface for
      --  scheduler stress tests. (PR #3 review feedback, gemini-code-
      --  assist.) G is mutable so Free_Goroutine can null it.
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
         --  Spawn, or a non-worker task post-Init). Documented no-op
         --  so generated code can call Yield unconditionally.
         return;
      end if;
      G.State := YIELDED;
      Gada.Async.Context.Switch_To (G.Worker_Ctx);
      --  Resumed: a worker switched back into us. State will be set
      --  to RUNNING by the worker just before its Switch_To, so we
      --  don't touch it here.
   end Yield;

   procedure Shutdown is
   begin
      if not Run_Queue.Is_Initialised then
         return;  --  idempotent half-init / half-teardown
      end if;
      Run_Queue.Mark_Shutdown;
      Run_Queue.Drain;
      Run_Queue.Set_Initialised (False);
      The_Workers := null;
      --  We deliberately do NOT call Unchecked_Deallocation on
      --  The_Workers' elements: by the time Drain returns each worker
      --  task has already executed Worker_Stopped + the protected
      --  entry's body, but it may still be unwinding its own task
      --  frame. Setting the access to null lets Boehm's GC reclaim
      --  the array and the task objects once the runtime declares
      --  them terminated.
   end Shutdown;

end Gada.Async.Scheduler;
