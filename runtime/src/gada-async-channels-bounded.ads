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

with Gada.Async.Scheduler;

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
   --  must be >= 1; capacity = 0 (Go's unbuffered / synchronous
   --  rendezvous) lives in Gada.Async.Channels.Unbounded (item 5).
   --  Constraint_Error is the natural raise — Capacity is Positive.
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
   --  blocks (parks) on empty-open; returns (default Element_Type,
   --  OK => False) on empty-closed. The OK out parameter mirrors Go's
   --  `v, ok := <-c` comma-ok form so callers can distinguish a real
   --  zero-value send from a closed-channel signal.
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
