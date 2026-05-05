--  Gada.Async.Channels.Unbounded — Go-style channel with a buffer
--  that grows on demand. Send always succeeds without blocking
--  (modulo Channel_Closed); Receive blocks when the buffer is empty.
--
--  This is NOT Go's `make (chan T)` form (capacity = 0, synchronous
--  rendezvous). Go's spec does not include an unbounded channel; the
--  closest Go idiom is "buffered channel with capacity larger than
--  the worst-case backlog plus a producer that panics on full." This
--  package provides the dependency-free, "I genuinely don't want to
--  size the buffer" shape that some Go programs reach for via a
--  hand-written linked-list-of-channels wrapper. The compiler will
--  not emit calls to it from a vanilla `make (chan T, N)` (those
--  lower to Channels.Bounded); explicit `gada:unbounded` annotations
--  on the Go side, plus Phase 4's `runtime/<pkg>` shim points,
--  remain the routes in.
--
--  Semantics:
--
--    * Send (c, v) on an open channel always returns immediately
--      after appending v to the tail of the buffer. Storage_Error
--      is the only way Send raises (heap-allocation failure for the
--      list node — libgc-managed, so practically rare).
--
--    * Receive on a non-empty buffer returns (head_value, OK => True)
--      and consumes the head node (libgc reclaims it). Receive on an
--      empty *open* buffer parks the calling goroutine via
--      Gada.Async.Scheduler.Park; a subsequent Send wakes it. Receive
--      on an empty *closed* buffer returns OK => False with V left
--      unmodified — Go's zero-value-with-ok-false semantics. The
--      caller is responsible for V := <Element_Type's zero> at the
--      use site; Ada cannot synthesise a portable zero for an
--      opaque generic private type, and Phase 4's compiler emit
--      zeroes V at the lowering of `v, ok := <-c` because the v
--      binding is locally declared in the Go source.
--
--    * Close marks the channel closed. All parked Receives wake with
--      OK => False (and V left unmodified — see the closed-empty
--      Receive note above for the rationale). Subsequent
--      Send raises Channel_Closed (Go panic-equivalent). Subsequent
--      Close raises Channel_Closed (matches Go's panic-on-double-
--      close, mirrored from Channels.Bounded).
--
--  Ordering: per-channel FIFO across Send/Receive pairs. The
--  buffer is a singly-linked list with O(1) Send (append-at-tail
--  via a tail pointer) and O(1) Receive (consume-at-head). No ring
--  resize, no copy on grow — the cost of "send never blocks" is one
--  heap allocation per Send.
--
--  Layering: depends on Gada.Async.Scheduler for Park / Unpark /
--  Current / Goroutine_Id. Does NOT depend on Gada.Async.Context
--  (the scheduler is the only place co_switch appears at the
--  runtime level, per ADR-0002 §"layered").

with Gada.Async.Scheduler;

generic
   type Element_Type is private;
package Gada.Async.Channels.Unbounded is

   --  Opaque handle. Underlying Channel_Record lives on the heap
   --  (libgc-managed); the handle is a thin wrapper so closures over
   --  a channel value see the same object the original Make returned.
   type Channel is private;

   No_Channel : constant Channel;

   --  Construct an unbounded channel. No capacity argument — that
   --  is the package's defining contract. Heap allocation is the
   --  only failure mode (Storage_Error).
   function Make return Channel
     with Post => Make'Result /= No_Channel;

   --  Send V on C. Always returns immediately on an open channel
   --  after appending V to the buffer's tail (and Unparking one
   --  parked Receive, if any). Sending on an already-closed channel
   --  raises Channel_Closed. Send is callable from any context
   --  (goroutine, main task, helper task) — there is no parking
   --  branch, so the "Park is a no-op outside a goroutine" caveat
   --  that Channels.Bounded.Send carries does not apply here.
   procedure Send (C : Channel; V : Element_Type);

   --  Receive from C. Returns (head_of_buffer, OK => True) on
   --  success; blocks (parks) on empty-open; returns (default
   --  Element_Type, OK => False) on empty-closed. The blocking path
   --  is only meaningful inside a goroutine; a non-goroutine Receive
   --  on an empty open channel would hang.
   procedure Receive
     (C  : Channel;
      V  : in out Element_Type;
      OK : out Boolean);

   --  Close marks C as closed. Wakes every parked Receive (each one
   --  resumes with OK => False once the buffer drains). After Close
   --  returns, no new Send may proceed; further Receives drain the
   --  buffer in FIFO order, then keep returning OK => False.
   --
   --  Close on No_Channel raises Constraint_Error. Close on an
   --  already-closed channel raises Channel_Closed (matches Go's
   --  panic-on-double-close).
   procedure Close (C : Channel);

   --  Diagnostics — same shape as Channels.Bounded so tests can
   --  poll-on-park deterministically. Capacity is intentionally
   --  absent — the package's defining contract is "no capacity bound."
   function Length             (C : Channel) return Natural;
   function Is_Closed          (C : Channel) return Boolean;
   function Receivers_Waiting  (C : Channel) return Natural;

   --  Raised by Send on a closed channel and by Close on a channel
   --  that is already closed. Maps to Go's runtime panic for
   --  send-after-close / close-after-close in Phase 4's panic
   --  marshalling. Same exception type as Channels.Bounded would have
   --  been, except this generic doesn't share state with that one;
   --  callers that need to catch both can `with` both packages and
   --  match each Channel_Closed separately, or wrap Receive/Send in
   --  a thin adapter.
   Channel_Closed : exception;

private

   --  Channel_Record is the heap object. Holds the linked-list
   --  buffer, the closed flag, and a FIFO queue of parked receivers.
   --  All mutation goes through the inner protected.
   type Channel_Record;
   type Channel_Access is access all Channel_Record;

   type Channel is record
      Ref : Channel_Access := null;
   end record;

   No_Channel : constant Channel := (Ref => null);

end Gada.Async.Channels.Unbounded;
