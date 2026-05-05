--  Gada.Async.Channels.Bounded — Go's `make (chan T, N)` for N > 0.
--
--  Buffered channel with a fixed-capacity ring buffer. Send blocks
--  when the buffer is full; Receive blocks when the buffer is empty.
--  Both blocking forms park the calling goroutine via
--  Gada.Async.Scheduler.Park, so siblings keep running while a
--  goroutine is waiting on a channel.
--
--  Semantics are pinned to Go's spec (golang.org/ref/spec#Channel_types
--  and #Send_statements / #Receive_operator):
--
--    * Send (c, v) on an open channel with a free buffer slot
--      stores v and returns immediately. With the buffer full, the
--      sender parks until a Receive consumes a slot.
--
--    * Receive on a non-empty buffer returns (head_value, OK => True)
--      and frees the slot (potentially Unparking the oldest parked
--      sender). Receive on an empty *open* buffer parks until a Send
--      provides a value. Receive on an empty *closed* buffer returns
--      (default Element_Type, OK => False) — Go's "comma-ok" zero-
--      value-with-ok-false semantics.
--
--    * Close marks the channel closed. All parked Receives wake with
--      OK => False. All parked Sends wake by raising Channel_Closed.
--      Subsequent Send raises Channel_Closed (Go panics; we raise an
--      Ada exception that Phase 4's Go-runtime mapper translates into
--      a recover-able Go panic). Subsequent Close also raises
--      Channel_Closed (Go panics on double-close; same shape).
--
--  Ordering: each channel preserves FIFO across Send/Receive pairs —
--  a value enqueued at Send N is dequeued at Receive N, regardless
--  of which goroutines drove either side. Internal queues of parked
--  senders and parked receivers are also FIFO so head-of-line
--  scheduling matches the obvious mental model.
--
--  Layering: this generic depends on Gada.Async.Scheduler for
--  Park / Unpark / Goroutine_Id. It does NOT depend on
--  Gada.Async.Context — the scheduler is the one place co_switch
--  appears at the runtime level, per ADR-0002 §"layered".

--  Note: Gada.Async.Scheduler is `with`'d only from the body — the
--  spec exposes no Scheduler-typed entities, so a spec-side `with`
--  trips GNAT 15's `unit not referenced in spec` warning under the
--  -gnatwu policy this crate enables. The body's reliance on
--  Scheduler.Park / Unpark / Current is what makes the layering
--  real (per ADR-0002 §"layered"); the comment above is the
--  spec-side breadcrumb.

generic
   type Element_Type is private;
package Gada.Async.Channels.Bounded is

   --  Opaque handle. The underlying Channel_Record lives on the heap
   --  (libgc-managed, like Goroutine_Record); the handle is a thin
   --  wrapper so closures over a channel value see the same object
   --  the original Make returned.
   type Channel is private;

   No_Channel : constant Channel;

   --  Construct a bounded channel with the given capacity. Capacity
   --  must be >= 1; Constraint_Error is the natural raise — Capacity
   --  is Positive. Go's unbuffered (synchronous rendezvous,
   --  `make (chan T)` with no capacity arg) does not currently have a
   --  dedicated runtime mapping — Channels.Unbounded provides
   --  send-never-blocks linked-list semantics, which is structurally
   --  different (one party is never blocked vs. both parties block
   --  until rendezvous). Phase 4 compiler emit will lower
   --  `make (chan T)` to either Bounded.Make (1) as a behavioral
   --  approximation or to a future Channels.Synchronous package; the
   --  decision rides on Phase 4's select-statement implementation
   --  experience.
   function Make (Capacity : Positive) return Channel
     with Post => Make'Result /= No_Channel;

   --  Send V on C. Buffer-has-slot fast path: store + return. Buffer-
   --  full slow path: park the calling goroutine until a Receive
   --  frees a slot or until Close fires Channel_Closed (in which case
   --  the parked Send wakes by raising). Sending on an already-closed
   --  channel raises Channel_Closed before any parking.
   --
   --  Send is callable from inside any goroutine. Calling from a non-
   --  goroutine context (the main task before any Spawn, a non-worker
   --  task) is supported as long as the buffer has space — the Park
   --  fast-path is a no-op outside a goroutine, so a buffer-full Send
   --  from the main task would otherwise stall. Callers driving Send
   --  from a non-goroutine context are responsible for ensuring the
   --  buffer is not full at call time.
   procedure Send (C : Channel; V : Element_Type);

   --  Receive from C. Returns (head_of_buffer, OK => True) on success;
   --  blocks (parks) on empty-open; returns (V unspecified,
   --  OK => False) on empty-closed. The OK out parameter mirrors Go's
   --  `v, ok := <-c` comma-ok form so callers can distinguish a real
   --  zero-value send from a closed-channel signal.
   --
   --  Note on V's value when OK is False: Ada cannot synthesise a
   --  portable "zero" for an arbitrary private generic Element_Type,
   --  so on the closed-empty arm V is *not* written. Phase 4's
   --  compiler-emit lowers Go's `v, ok := <-c` to a fresh declaration
   --  of v (which Go zeroes by spec); current callers in tests
   --  initialise V at the call site or treat it as undefined when
   --  OK = False, matching the Gada.Async.Channels.Unbounded.Receive
   --  contract.
   --
   --  As with Send, the blocking path is only meaningful inside a
   --  goroutine. A non-goroutine Receive on an empty open channel
   --  would hang; callers driving Receive from non-goroutine context
   --  are responsible for ensuring the buffer is non-empty or the
   --  channel is closed at call time.
   procedure Receive
     (C  : Channel;
      V  : out Element_Type;
      OK : out Boolean);

   --  Close marks C as closed. Wakes every parked Receive (each one
   --  resumes with OK => False) and every parked Send (each one
   --  resumes by raising Channel_Closed). After Close returns, no new
   --  Send may proceed; further Receives drain the buffer in FIFO
   --  order, then keep returning OK => False.
   --
   --  Close on No_Channel raises Constraint_Error. Close on an
   --  already-closed channel raises Channel_Closed (matches Go's
   --  panic-on-double-close).
   procedure Close (C : Channel);

   --  Non-blocking Send. Returns Sent => True if V was stored
   --  (buffered or handed off to a parked receiver) and the channel
   --  is open. Returns Sent => False if the buffer is full (no
   --  parking — caller decides whether to retry, drop, or escalate).
   --  On a closed channel, raises Channel_Closed (matches Send's
   --  shape; Go's `select { case c <- v: ...; default: ... }` panics
   --  if c is closed, which is the same observable behaviour).
   --
   --  Used by Gada.Async.Selector to test a Send case without
   --  committing to the parking path; "fits the slot" cases under
   --  select must succeed atomically and unsuccessful ones must
   --  return immediately so siblings can be tried.
   procedure Try_Send
     (C    : Channel;
      V    : Element_Type;
      Sent : out Boolean);

   --  Non-blocking Receive. Returns Got => True with V at the
   --  drained head and OK => True if the buffer was non-empty.
   --  Returns Got => True with V at default and OK => False if the
   --  channel is closed-and-empty (Go's zero-value-with-ok-false on
   --  closed-drained channels). Returns Got => False if the buffer
   --  was empty and the channel still open (no parking — caller
   --  decides whether to retry or move on).
   --
   --  V's shape is the same in-out caveat as the closed-empty arm
   --  of Channels.Unbounded: Ada cannot synthesise a portable zero
   --  for an opaque generic Element_Type, so on the Got=>True with
   --  OK=>False arm V is left at the call-site value (caller is
   --  responsible for zero-initialisation in that branch).
   procedure Try_Receive
     (C  : Channel;
      V  : in out Element_Type;
      OK : out Boolean;
      Got : out Boolean);

   --  Diagnostics — not part of the Go-source-mapping surface but
   --  useful for tests and observability. Length is the buffered-
   --  count snapshot at the call instant; it can change before the
   --  caller acts on it. Capacity is set at Make and never changes.
   --  Senders_Waiting / Receivers_Waiting expose the parked-queue
   --  depths so a deterministic test can poll "has my goroutine
   --  actually parked yet?" without racy `delay`-based barriers.
   function Length (C : Channel) return Natural;
   function Capacity (C : Channel) return Positive;
   function Is_Closed (C : Channel) return Boolean;
   function Senders_Waiting   (C : Channel) return Natural;
   function Receivers_Waiting (C : Channel) return Natural;

   --  Raised by Send on a closed channel and by Close on a channel
   --  that is already closed. Maps to Go's runtime panic for
   --  send-after-close / close-after-close in Phase 4's panic
   --  marshalling.
   Channel_Closed : exception;

private

   --  Channel_Record is the heap object. Holds the ring buffer, the
   --  closed flag, and FIFO queues of parked senders / receivers.
   --  All mutation goes through the inner protected so a concurrent
   --  Send + Receive + Close cannot tear the state.
   type Channel_Record;
   type Channel_Access is access all Channel_Record;

   type Channel is record
      Ref : Channel_Access := null;
   end record;

   No_Channel : constant Channel := (Ref => null);

end Gada.Async.Channels.Bounded;
