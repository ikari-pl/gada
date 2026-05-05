--  Body of Gada.Async.Channels.Unbounded — see spec for semantics.
--
--  ## Layout
--
--  Each Channel handle wraps a heap-allocated Channel_Record. The
--  record carries a singly-linked list of buffer Nodes (head + tail
--  pointers, count for O(1) Length), the closed flag, and a FIFO
--  list of parked-Receiver Wait_Slots. All mutation goes through
--  one inner protected so concurrent Send + Receive + Close cannot
--  tear state.
--
--  ## Wait_Slot (Receive-side only)
--
--  A Receive that finds the buffer empty allocates a Wait_Slot,
--  fills it with its own Goroutine_Id (via Scheduler.Current) plus
--  default V/OK fields, and registers the slot in the channel's
--  parked-receivers list. Then it Parks, releasing the worker.
--
--  When a Send arrives with the buffer empty AND a parked receiver
--  waiting, the protected hands V directly into the receiver's
--  Wait_Slot (skipping the linked list entirely) and Unparks them.
--  The receiver resumes from Park, reads V/OK from the slot, frees
--  the slot, and returns. This direct-handoff path matches
--  Channels.Bounded's symmetric optimisation; it costs one less
--  Node allocation per Send/Receive pair where Receive is already
--  parked.
--
--  ## No parked-Senders queue
--
--  Send never blocks on this channel — there is no buffer-full
--  state to park on. The mirror-image queue from Bounded
--  (Parked_Senders) is therefore absent here, and Close has only
--  one wake-up walk to do (parked Receivers).
--
--  ## Close semantics
--
--  Close marks the channel closed and walks the parked-Receivers
--  list. Each receiver wakes with OK => False — the Go zero-value-
--  with-ok-false signal. Buffered values still drain in FIFO order
--  with OK => True (Receive checks the buffer head before checking
--  Closed_F + empty), matching Channels.Bounded.
--
--  Close on an already-closed channel raises Channel_Closed.
--  Subsequent Send raises Channel_Closed.
--
--  ## Memory ordering note
--
--  Same release/acquire pairing as Channels.Bounded: the unparker
--  releases the channel's protected (release fence over its writes
--  to Slot.Value / Slot.OK), then calls Scheduler.Unpark which goes
--  through the Run_Queue's Inject_Local protected (release fence).
--  The parked goroutine's worker re-acquires Run_Queue at Pop
--  (acquire fence). By the time the goroutine resumes from Park
--  and reads the slot, the unparker's writes are visible.

with Ada.Containers.Doubly_Linked_Lists;
with Ada.Unchecked_Deallocation;

package body Gada.Async.Channels.Unbounded is

   --  Bring "=" on Scheduler.Goroutine_Id into scope for the non-
   --  goroutine-context guard in Receive. Goroutine_Id is a private
   --  record so the default "=" needs `use type`. Mirror of the
   --  same use clause in Channels.Bounded.
   use type Scheduler.Goroutine_Id;

   --  ## Wait_Slot — receiver-only rendezvous record.

   type Wait_Slot is record
      G              : Scheduler.Goroutine_Id := Scheduler.No_Goroutine;
      Value          : aliased Element_Type;
      OK             : Boolean := True;
   end record;

   type Wait_Slot_Access is access all Wait_Slot;

   procedure Free_Slot is new Ada.Unchecked_Deallocation
     (Object => Wait_Slot, Name => Wait_Slot_Access);

   package Wait_Lists is new Ada.Containers.Doubly_Linked_Lists
     (Element_Type => Wait_Slot_Access);

   --  ## Buffer Node — singly-linked list cell.

   type Node;
   type Node_Access is access all Node;
   type Node is record
      Value : aliased Element_Type;
      Next  : Node_Access := null;
   end record;

   procedure Free_Node is new Ada.Unchecked_Deallocation
     (Object => Node, Name => Node_Access);

   --  ## Channel_State — protected core
   --
   --  No discriminant: there is no fixed-size storage to size at
   --  Make. The buffer is the linked list (Head, Tail, Count) and
   --  the parked-Receivers list.

   protected type Channel_State is

      --  Send_Or_Handoff: store V in the buffer (append to tail).
      --  If a receiver is parked AND the buffer is empty, hand V
      --  directly to the parked receiver instead and Unpark them.
      --  Closed => True if the channel is closed (caller raises
      --  Channel_Closed); Stored is set True on every successful
      --  path so the spec stays uniform with Bounded.
      procedure Send_Or_Handoff
        (V       : Element_Type;
         Stored  : out Boolean;
         Closed  : out Boolean);

      --  Try_Receive: pull V from the buffer head. Returns Got =>
      --  True on success. On failure: Closed => True if the channel
      --  is closed AND empty (caller returns OK => False without
      --  parking); otherwise both False (caller parks). V is `in
      --  out` rather than `out` so the closed-empty path can leave
      --  the caller's V untouched — see the closed-empty Receive
      --  contract in the package spec.
      procedure Try_Receive
        (V       : in out Element_Type;
         Got     : out Boolean;
         Closed  : out Boolean);

      --  Park_Receiver: register the calling goroutine as a parked
      --  receiver (buffer was empty AND channel open). The Slot is
      --  heap-allocated by the caller. Returns Got => True if a
      --  Send raced in between Try_Receive and Park_Receiver and
      --  the buffer is now non-empty (caller drains the head into V
      --  without parking). Closed => True is the symmetric "closed
      --  during the racy window" early-return.
      procedure Park_Receiver
        (Slot    : Wait_Slot_Access;
         V       : in out Element_Type;
         Got     : out Boolean;
         Closed  : out Boolean);

      --  Mark_Closed: flip Closed flag, drain the parked-Receivers
      --  list. Each parked receiver gets OK => False (resume +
      --  return zero-value-with-ok-false). Already_Closed => True
      --  if Close was called twice.
      procedure Mark_Closed (Already_Closed : out Boolean);

      function  Length             return Natural;
      function  Is_Closed          return Boolean;
      function  Receivers_Waiting  return Natural;

   private
      Head      : Node_Access := null;
      Tail      : Node_Access := null;
      Count     : Natural     := 0;
      Closed_F  : Boolean     := False;
      Receivers : Wait_Lists.List;
   end Channel_State;

   protected body Channel_State is

      ---------------------------------------------------------------

      procedure Send_Or_Handoff
        (V      : Element_Type;
         Stored : out Boolean;
         Closed : out Boolean)
      is
      begin
         if Closed_F then
            Stored := False;
            Closed := True;
            return;
         end if;
         Closed := False;

         --  Direct hand-off: parked receiver waiting AND buffer
         --  empty (a non-empty buffer would have served the
         --  receiver before parking). Skip the Node allocation.
         if not Receivers.Is_Empty then
            declare
               R : constant Wait_Slot_Access := Receivers.First_Element;
            begin
               Receivers.Delete_First;
               R.Value := V;
               R.OK    := True;
               Scheduler.Unpark (R.G);
            end;
            Stored := True;
            return;
         end if;

         --  Append to tail. Single Node allocation per Send is the
         --  cost of "send never blocks." Tail = null marks empty
         --  buffer; otherwise Tail.Next gets the new node and Tail
         --  advances.
         declare
            New_Node : constant Node_Access :=
              new Node'(Value => V, Next => null);
         begin
            if Tail = null then
               Head := New_Node;
            else
               Tail.Next := New_Node;
            end if;
            Tail  := New_Node;
            Count := Count + 1;
         end;
         Stored := True;
      end Send_Or_Handoff;

      ---------------------------------------------------------------

      procedure Try_Receive
        (V      : in out Element_Type;
         Got    : out Boolean;
         Closed : out Boolean)
      is
         Old_Head : Node_Access;
      begin
         if Head /= null then
            Old_Head := Head;
            V := Old_Head.Value;
            Head := Old_Head.Next;
            if Head = null then
               Tail := null;
            end if;
            Count := Count - 1;
            Free_Node (Old_Head);
            Got := True;
            Closed := False;
            return;
         end if;

         --  Empty buffer.
         if Closed_F then
            Got := False;
            Closed := True;
            return;
         end if;

         Got := False;
         Closed := False;
      end Try_Receive;

      ---------------------------------------------------------------

      procedure Park_Receiver
        (Slot   : Wait_Slot_Access;
         V      : in out Element_Type;
         Got    : out Boolean;
         Closed : out Boolean)
      is
         Old_Head : Node_Access;
      begin
         --  Re-check under lock for race-with-Send / race-with-Close
         --  between Try_Receive and us.
         if Head /= null then
            Old_Head := Head;
            V := Old_Head.Value;
            Head := Old_Head.Next;
            if Head = null then
               Tail := null;
            end if;
            Count := Count - 1;
            Free_Node (Old_Head);
            Got    := True;
            Closed := False;
            return;
         end if;
         if Closed_F then
            Got    := False;
            Closed := True;
            return;
         end if;
         Got    := False;
         Closed := False;
         Receivers.Append (Slot);
      end Park_Receiver;

      ---------------------------------------------------------------

      procedure Mark_Closed (Already_Closed : out Boolean) is
      begin
         if Closed_F then
            Already_Closed := True;
            return;
         end if;
         Already_Closed := False;
         Closed_F := True;

         --  Wake every parked receiver with OK => False — the Go
         --  spec's zero-value-with-ok-false signal for a closed-and-
         --  drained channel.
         while not Receivers.Is_Empty loop
            declare
               R : constant Wait_Slot_Access := Receivers.First_Element;
            begin
               Receivers.Delete_First;
               R.OK := False;
               --  R.Value is left at its initialised default — Go's
               --  zero-value semantics. Element_Type's default is
               --  whatever the instantiation provides.
               Scheduler.Unpark (R.G);
            end;
         end loop;
      end Mark_Closed;

      ---------------------------------------------------------------

      function Length return Natural is (Count);
      function Is_Closed return Boolean is (Closed_F);
      function Receivers_Waiting return Natural is
        (Natural (Receivers.Length));

   end Channel_State;

   --  ## Channel_Record
   --
   --  Heap object that the Channel handle wraps. Holds the protected
   --  state. No discriminant — buffer is on the heap as a linked
   --  list.

   type Channel_Record is limited record
      State : Channel_State;
   end record;

   ---------------------------------------------------------------
   --  Public API
   ---------------------------------------------------------------

   function Make return Channel is
      R : constant Channel_Access := new Channel_Record;
   begin
      return (Ref => R);
   end Make;

   procedure Send (C : Channel; V : Element_Type) is
      Stored     : Boolean;
      Was_Closed : Boolean;
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Unbounded.Send: No_Channel";
      end if;

      C.Ref.State.Send_Or_Handoff (V, Stored, Was_Closed);
      if Was_Closed then
         raise Channel_Closed
           with "Gada.Async.Channels.Unbounded.Send: channel is closed";
      end if;
      pragma Assert (Stored, "Send_Or_Handoff returned not-Stored without"
                     & " setting Was_Closed");
   end Send;

   procedure Receive
     (C  : Channel;
      V  : in out Element_Type;
      OK : out Boolean)
   is
      Got        : Boolean;
      Was_Closed : Boolean;
      Slot       : Wait_Slot_Access;
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Unbounded.Receive: No_Channel";
      end if;

      C.Ref.State.Try_Receive (V, Got, Was_Closed);
      if Got then
         OK := True;
         return;
      end if;
      if Was_Closed then
         --  Buffer empty + channel closed — Go's zero-value-with-ok-
         --  False. V is left at the caller's pre-call value because
         --  Element_Type is an opaque private formal: Ada cannot
         --  synthesise a "zero" for an arbitrary private type.
         --  Phase 4's compiler emit will zero V at the call site
         --  before invoking Receive on a closed-empty channel
         --  (lowering Go's `v, ok := <-c` semantics — the v binding
         --  is locally declared and zero-initialised by the Go
         --  scope).  The runtime's contract is therefore "OK = False
         --  on closed-empty; V is unmodified."  See
         --  runtime/COVERAGE.md for the rationale.
         OK := False;
         return;
      end if;

      --  Buffer empty, channel open — park.
      --
      --  Park is meaningful only inside a goroutine. Outside one,
      --  Scheduler.Current is No_Goroutine: allocating Slot, calling
      --  Park_Receiver (which enqueues the slot on the parked-
      --  receivers list), and then returning without an actual Park
      --  leaves Slot orphaned for a later Send or Close to write
      --  through. Raise before allocation so the contract violation
      --  surfaces at the call site rather than as delayed memory
      --  corruption. Mirror of the same guard in Channels.Bounded.
      if Scheduler.Current = Scheduler.No_Goroutine then
         raise Program_Error with "Gada.Async.Channels.Unbounded.Receive: cannot park outside a goroutine context (call from a Scheduler.Spawn body, not from a top-level task or main)";
      end if;
      Slot := new Wait_Slot;
      Slot.G := Scheduler.Current;
      C.Ref.State.Park_Receiver (Slot, V, Got, Was_Closed);
      if Got then
         Free_Slot (Slot);
         OK := True;
         return;
      end if;
      if Was_Closed then
         Free_Slot (Slot);
         OK := False;
         return;
      end if;

      Scheduler.Park;
      --  Resumed: a Send wrote into our slot (OK => True) or Close
      --  walked the parked-receivers list (OK => False).
      V  := Slot.Value;
      OK := Slot.OK;
      Free_Slot (Slot);
   end Receive;

   procedure Close (C : Channel) is
      Already_Closed : Boolean;
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Unbounded.Close: No_Channel";
      end if;
      C.Ref.State.Mark_Closed (Already_Closed);
      if Already_Closed then
         raise Channel_Closed
           with "Gada.Async.Channels.Unbounded.Close: already closed";
      end if;
   end Close;

   function Length (C : Channel) return Natural is
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Unbounded.Length: No_Channel";
      end if;
      return C.Ref.State.Length;
   end Length;

   function Is_Closed (C : Channel) return Boolean is
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Unbounded.Is_Closed: No_Channel";
      end if;
      return C.Ref.State.Is_Closed;
   end Is_Closed;

   function Receivers_Waiting (C : Channel) return Natural is
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Unbounded.Receivers_Waiting: "
                & "No_Channel";
      end if;
      return C.Ref.State.Receivers_Waiting;
   end Receivers_Waiting;

end Gada.Async.Channels.Unbounded;
