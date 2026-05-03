--  Gada.Async.Scheduler body — minimal single-worker scheduler.
--
--  Sub-item 3a of Phase 3. Ships the smallest viable shape that lets
--  the rest of Phase 3 build (channels, select, `go`-statement emit)
--  on a real, testable primitive: one Worker Ada task draining a
--  shared FIFO queue, libco-backed goroutines yielding cooperatively.
--
--  Sub-items (b)-(e) extend this body without breaking the public
--  spec: (b) bumps the worker count to GOMAXPROCS, (c) replaces the
--  shared queue with per-worker deques + work-stealing, (d) adds
--  Park/Unpark, (e) adds the syscall-handoff API.
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
--  ## Layering
--
--  This body imports Gada.Async.Context (its peer in Gada.Async,
--  permitted by ADR-0002's runtime layering), System.Multiprocessors
--  for CPU count introspection, and Ada.Containers / Ada.Task_Attributes
--  for the queue and per-worker "current goroutine" pointer. It does
--  NOT import Gada.Async.Channels / Gada.Async.Select / Gada.Async.Std
--  — they don't exist yet, and the dependency direction in the layer
--  graph forbids them anyway.

with Ada.Containers.Doubly_Linked_Lists;
with Ada.Task_Attributes;
with Ada.Unchecked_Deallocation;
with System.Multiprocessors;

with Gada.Async.Context;

package body Gada.Async.Scheduler is

   --  ## Goroutine_Record
   --
   --  Heap-allocated, owned by the scheduler. Lifetime: from Spawn to
   --  the worker reaping it (after the body returned and State => DONE).
   --  Multi-worker (3b+) means N OS threads can read/write State for
   --  goroutines being handed off through Park/Unpark, work-stealing,
   --  and syscall handoff. The protected `Run_Queue` mediates *queue*
   --  membership, but the field itself is touched directly between
   --  goroutine-side writes (Yield → YIELDED, Trampoline-tail → DONE)
   --  and worker-side reads (post-Switch_To classification) — the
   --  protected object is no longer in the chain.
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
      --  pinning the *most recent* worker that ran us, which under
      --  one-worker (a) is always the same task but under multi-worker
      --  (b)+ can change between yields.
   end record;

   procedure Free_Goroutine is
     new Ada.Unchecked_Deallocation
       (Object => Goroutine_Record, Name => Goroutine_Access);

   --  Per-task pointer to "the goroutine I am currently running" so
   --  Yield can find it without a parameter. Ada.Task_Attributes is the
   --  Ada-standard task-local-storage facility; on hosted targets where
   --  Ada tasks map 1:1 to OS threads, this is effectively pthread_key
   --  -based TLS. Initialised to null so a non-worker task that calls
   --  Yield (e.g. the main task before any goroutine runs) reads null
   --  and the Yield no-op kicks in.
   package Current_Goroutine_Attr is new Ada.Task_Attributes
     (Attribute     => Goroutine_Access,
      Initial_Value => null);

   --  ## Run queue
   --
   --  Shared FIFO across all workers (single one in (a); item (c)
   --  replaces the global queue with per-worker deques + a small global
   --  injection queue for cross-worker spawns). Doubly_Linked_Lists is
   --  cheap to push at the tail and pop at the head; we never iterate.

   package Goroutine_Lists is new Ada.Containers.Doubly_Linked_Lists
     (Element_Type => Goroutine_Access);

   protected Run_Queue is
      --  Inject is the public-facing Spawn path; bumps In_Flight.
      procedure Inject (G : Goroutine_Access);

      --  Re_Push is the internal worker path for re-scheduling a
      --  yielded goroutine; In_Flight unchanged because the goroutine
      --  is still alive.
      procedure Re_Push (G : Goroutine_Access);

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

      procedure Re_Push (G : Goroutine_Access) is
      begin
         Items.Append (G);
      end Re_Push;

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
   --  Runs on the goroutine's libco stack. The Spawn'd Body_Proc
   --  is dispatched here; on its natural return we set State => DONE
   --  before letting the Gada.Async.Context tail-stub bounce back to
   --  the worker. The State write is the *only* signal the worker has
   --  to distinguish "yielded" (re-enqueue) from "done" (reap).

   procedure Goroutine_Trampoline;

   procedure Goroutine_Trampoline is
      G : constant Goroutine_Access := Current_Goroutine_Attr.Value;
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
   --  The execution loop: pop, switch in, classify on return, repeat.
   --  Sub-item 3b will turn this single instance into an array; the
   --  body of the loop is unchanged.

   task type Worker_Task;

   task body Worker_Task is
      G    : Goroutine_Access;
      Stop : Boolean;
   begin
      --  Note: Worker_Started is called by Init *before* this task is
      --  allocated, not here. The reason is a tiny but real race: if
      --  Init returned before the freshly-allocated task got CPU time
      --  to call Worker_Started, the very next Shutdown's Drain (whose
      --  guard is Workers_Active = 0) would fire immediately and
      --  Shutdown would return with the worker still asleep behind it.
      --  Bumping Workers_Active synchronously in Init fixes that.
      loop
         Run_Queue.Pop (G, Stop);
         exit when Stop;

         --  Stage the per-worker context for Yield's lookup. Done
         --  every iteration because under multi-worker (3b+) the
         --  goroutine may have last run on a *different* worker and
         --  the Worker_Ctx field would point at its stack.
         G.Worker_Ctx := Gada.Async.Context.Active;
         Current_Goroutine_Attr.Set_Value (G);

         --  First switch into a freshly-Spawn'd goroutine bootstraps
         --  Goroutine_Trampoline (which runs Body_Proc); subsequent
         --  switches resume the goroutine wherever it Yield'd from.
         G.State := RUNNING;
         Gada.Async.Context.Switch_To (G.Ctx);

         --  Goroutine handed control back. Either Yield (re-enqueue)
         --  or natural return (reap). State is the source of truth.
         Current_Goroutine_Attr.Set_Value (null);

         case G.State is
            when YIELDED =>
               G.State := READY;
               Run_Queue.Re_Push (G);
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

   --  Single worker for sub-item (a). Item (b) replaces this with an
   --  array sized by Number_Of_CPUs. Kept as an access so the storage
   --  can be allocated in Init and the task itself runs as long as it
   --  needs to (potentially past the elaboration scope).
   The_Worker : Worker_Access := null;

   --  ## Public-API implementations

   procedure Init (Workers : Natural := 0) is
      pragma Unreferenced (Workers);
      --  Sub-item (a) clamps to one worker — the parameter is
      --  retained in the spec so (b) doesn't need a signature change.
      Cpu_Count : constant Positive :=
        Positive (System.Multiprocessors.Number_Of_CPUs);
      pragma Unreferenced (Cpu_Count);
      --  Reserved for sub-item (b); reading it now keeps Multiprocessors
      --  in scope so that change is purely additive.
   begin
      if Run_Queue.Is_Initialised then
         raise Program_Error
           with "Gada.Async.Scheduler.Init called twice without Shutdown";
      end if;
      Run_Queue.Reset_Lifecycle;
      Run_Queue.Set_Initialised (True);
      --  Bump Workers_Active *before* allocating the task so a Shutdown
      --  that fires before the task gets CPU time still waits — the
      --  Drain entry guard is Workers_Active = 0, and a worker that
      --  hasn't started yet (so Worker_Started hasn't run) would have
      --  let the guard fire prematurely. Worker_Stopped runs at the
      --  tail of Worker_Task and balances this bump.
      Run_Queue.Worker_Started;
      --  Roll back the lifecycle counters if the task allocation
      --  itself raises (Storage_Error on a tight task-storage budget,
      --  Tasking_Error on policy mismatch). Without this, the next
      --  Init would see Initialised => True and raise "called twice",
      --  and a Shutdown would Drain forever waiting for a worker that
      --  was never spawned. (PR #3 review feedback, gemini-code-assist.)
      begin
         The_Worker := new Worker_Task;
      exception
         when others =>
            Run_Queue.Worker_Stopped;
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
      G : constant Goroutine_Access := Current_Goroutine_Attr.Value;
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
      The_Worker := null;
      --  We deliberately do NOT call Unchecked_Deallocation on
      --  The_Worker: by the time Drain returns the worker task has
      --  already executed Worker_Stopped + the protected entry's
      --  body, but it may still be unwinding its own task frame.
      --  Setting the access to null lets Boehm's GC reclaim the
      --  task object once the runtime declares it terminated.
   end Shutdown;

end Gada.Async.Scheduler;
