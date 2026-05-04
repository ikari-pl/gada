--  Body of Gada.Async.Channels.Bounded — see spec for semantics.
--
--  ## Layout
--
--  Each Channel handle wraps a heap-allocated Channel_Record. The
--  record carries a static-sized ring buffer (sized at Make via the
--  discriminant), the closed flag, and two FIFO lists of parked
--  Wait_Slots. Mutation goes through one inner protected, which
--  serialises every Send / Receive / Close / Length / etc.
--
--  ## Wait_Slot
--
--  When a Send finds the buffer full or a Receive finds it empty,
--  the calling goroutine allocates a Wait_Slot, fills it with its
--  own Goroutine_Id (via Scheduler.Current) plus the value-being-
--  sent (sender) or a default placeholder (receiver), and registers
--  the slot in the channel's parked-senders or parked-receivers
--  list. Then it Parks, releasing the worker.
--
--  When a counterpart op fires:
--    * Receive consuming a parked sender takes the sender's Wait_
--      Slot, copies its V into the buffer (preserving FIFO across
--      "buffered + queued" combined order), unparks the sender.
--      Sender resumes from Park; its slot's Closed_On_Wake field is
--      False, so it returns successfully.
--    * Send consuming a parked receiver takes the receiver's Wait_
--      Slot, writes its V directly into the slot (skipping the ring
--      buffer entirely — the buffer was empty), unparks the receiver.
--      Receiver resumes from Park; reads V and OK from the slot.
--
--  ## Close semantics
--
--  Close marks the channel closed and walks both parked lists:
--    * Parked receivers wake with OK => False (the Go zero-value-
--      with-ok-false signal).
--    * Parked senders wake with Closed_On_Wake => True; Send's post-
--      Park check raises Channel_Closed.
--
--  Close on an already-closed channel raises Channel_Closed (Go's
--  panic-on-double-close).
--
--  ## Memory ordering note
--
--  The Wait_Slot is allocated on the heap via libgc so the unparker
--  on a different OS thread has a stable address to write to. The
--  cross-thread visibility of writes to Slot.Value / Slot.OK relies
--  on the protected lock's release/acquire pairing: the unparker
--  releases the channel's protected (release fence over its writes
--  to Slot), then calls Scheduler.Unpark which goes through the
--  Run_Queue's Inject_Local protected (release fence). The parked
--  goroutine's worker re-acquires Run_Queue at Pop (acquire fence),
--  reading the freshly-injected Goroutine_Access. By the time the
--  goroutine resumes from Park and reads Slot.Value / Slot.OK, the
--  unparker's writes are visible. (See ARM C.6 + Ada protected
--  semantics; matches Go's M:N gc-runtime model where the equivalent
--  happens via runtime.lock / runtime.unlock pairs.)

with Ada.Containers.Doubly_Linked_Lists;
with Ada.Unchecked_Deallocation;

package body Gada.Async.Channels.Bounded is

   type Wait_Slot is record
      G              : Scheduler.Goroutine_Id := Scheduler.No_Goroutine;
      Value          : aliased Element_Type;
      OK             : Boolean := True;
      Closed_On_Wake : Boolean := False;
   end record;

   type Wait_Slot_Access is access all Wait_Slot;

   procedure Free_Slot is new Ada.Unchecked_Deallocation
     (Object => Wait_Slot, Name => Wait_Slot_Access);

   package Wait_Lists is new Ada.Containers.Doubly_Linked_Lists
     (Element_Type => Wait_Slot_Access);

   --  ## Channel_State — protected core
   --
   --  Discriminated by the channel capacity so the ring buffer can be
   --  a static array. Every public Send / Receive / Close / etc. on
   --  the outer Channel handle delegates here.

   type Slot_Array is array (Positive range <>) of Element_Type;

   protected type Channel_State (Cap : Positive) is

      --  Try_Buffered_Send: store V in the ring buffer if there is a
      --  free slot. Returns Stored => True on success, False if the
      --  buffer is full or if the channel is closed (the latter sets
      --  Closed => True so the caller can raise Channel_Closed).
      --  If a parked receiver is waiting AND the buffer is empty, the
      --  protected hands V directly to the receiver's slot and
      --  Unparks them — Stored is True, no buffering.
      procedure Try_Buffered_Send
        (V       : Element_Type;
         Stored  : out Boolean;
         Closed  : out Boolean);

      --  Park_Sender: register the calling goroutine as a parked
      --  sender (buffer was full). The Slot is heap-allocated by the
      --  caller so the address survives across the Park / Unpark /
      --  Switch_To dance. Returns Closed => True if the channel is
      --  closed (in which case the caller raises Channel_Closed
      --  without parking).
      procedure Park_Sender
        (Slot    : Wait_Slot_Access;
         Closed  : out Boolean);

      --  Try_Buffered_Receive: pull V from the ring buffer. Returns
      --  Got => True on success. On failure: Closed => True if the
      --  channel is closed AND empty (caller returns OK => False
      --  without parking); otherwise both False (caller parks). If a
      --  parked sender exists, the protected pulls V from the buffer
      --  head AND slides the parked-sender's V into the freed slot,
      --  Unparking the sender. FIFO across the combined queue is
      --  preserved.
      procedure Try_Buffered_Receive
        (V       : out Element_Type;
         Got     : out Boolean;
         Closed  : out Boolean);

      --  Park_Receiver: register the calling goroutine as a parked
      --  receiver (buffer empty AND channel open). Slot is heap-
      --  allocated by the caller; its OK / Value fields are written
      --  by the matching Send (or by Close which sets OK => False).
      --  Returns Got => True if the protected found a parked sender
      --  to match without parking — happens if a sender raced in
      --  between the caller's Try_Buffered_Receive and Park_Receiver
      --  invocations. Closed => True is the symmetric "closed during
      --  the racy window" early-return.
      procedure Park_Receiver
        (Slot    : Wait_Slot_Access;
         V       : out Element_Type;
         Got     : out Boolean;
         Closed  : out Boolean);

      --  Mark_Closed: flip Closed flag, drain both parked lists.
      --  Each parked sender gets Closed_On_Wake => True (resume +
      --  raise); each parked receiver gets OK => False (resume +
      --  return zero-value-with-ok-false). Already_Closed => True
      --  if Close was called twice.
      procedure Mark_Closed (Already_Closed : out Boolean);

      function  Length              return Natural;
      function  Is_Closed           return Boolean;
      function  Senders_Waiting     return Natural;
      function  Receivers_Waiting   return Natural;

   private
      Buf     : Slot_Array (1 .. Cap);
      Head    : Positive := 1;
      Tail    : Positive := 1;
      Count   : Natural  := 0;
      Closed_F : Boolean := False;
      Senders   : Wait_Lists.List;
      Receivers : Wait_Lists.List;
   end Channel_State;

   protected body Channel_State is

      ---------------------------------------------------------------

      procedure Try_Buffered_Send
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

         --  Direct hand-off: if a receiver is parked, the buffer is
         --  necessarily empty (a non-empty buffer would have served
         --  the receiver before parking). Write V into the receiver's
         --  Wait_Slot and unpark them.
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

         --  Buffered store: if there's a free slot, append.
         if Count < Cap then
            Buf (Tail) := V;
            Tail := (if Tail = Cap then 1 else Tail + 1);
            Count := Count + 1;
            Stored := True;
            return;
         end if;

         --  Buffer full and no parked receiver — caller must park.
         Stored := False;
      end Try_Buffered_Send;

      ---------------------------------------------------------------

      procedure Park_Sender
        (Slot   : Wait_Slot_Access;
         Closed : out Boolean)
      is
      begin
         --  The caller already failed Try_Buffered_Send for "buffer
         --  full," but the channel could have been closed since. Re-
         --  check under the same protected lock to avoid a racy
         --  Send-after-close that slips through.
         if Closed_F then
            Closed := True;
            return;
         end if;
         Closed := False;
         Senders.Append (Slot);
      end Park_Sender;

      ---------------------------------------------------------------

      procedure Try_Buffered_Receive
        (V      : out Element_Type;
         Got    : out Boolean;
         Closed : out Boolean)
      is
      begin
         --  Buffer non-empty: pull from head, optionally promote a
         --  parked sender into the freed slot.
         if Count > 0 then
            V := Buf (Head);
            Head := (if Head = Cap then 1 else Head + 1);
            Count := Count - 1;

            --  Promote parked sender (FIFO). Preserves "send order =
            --  receive order" across the buffered + queued combined
            --  sequence.
            if not Senders.Is_Empty then
               declare
                  S : constant Wait_Slot_Access := Senders.First_Element;
               begin
                  Senders.Delete_First;
                  Buf (Tail) := S.Value;
                  Tail := (if Tail = Cap then 1 else Tail + 1);
                  Count := Count + 1;
                  Scheduler.Unpark (S.G);
               end;
            end if;

            Got := True;
            Closed := False;
            return;
         end if;

         --  Buffer empty. If closed, return ok=False.
         if Closed_F then
            Got := False;
            Closed := True;
            return;
         end if;

         --  Buffer empty, channel open — caller must park.
         Got := False;
         Closed := False;
      end Try_Buffered_Receive;

      ---------------------------------------------------------------

      procedure Park_Receiver
        (Slot   : Wait_Slot_Access;
         V      : out Element_Type;
         Got    : out Boolean;
         Closed : out Boolean)
      is
      begin
         --  Re-check under lock for race-with-Send / race-with-Close
         --  between Try_Buffered_Receive and us.
         if Count > 0 then
            V := Buf (Head);
            Head := (if Head = Cap then 1 else Head + 1);
            Count := Count - 1;
            if not Senders.Is_Empty then
               declare
                  S : constant Wait_Slot_Access := Senders.First_Element;
               begin
                  Senders.Delete_First;
                  Buf (Tail) := S.Value;
                  Tail := (if Tail = Cap then 1 else Tail + 1);
                  Count := Count + 1;
                  Scheduler.Unpark (S.G);
               end;
            end if;
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

         --  Wake every parked sender with Closed_On_Wake => True so
         --  Send's post-Park check raises Channel_Closed. We don't
         --  consume the parked-sender's Value into the buffer because
         --  the sender will raise rather than complete the Send.
         while not Senders.Is_Empty loop
            declare
               S : constant Wait_Slot_Access := Senders.First_Element;
            begin
               Senders.Delete_First;
               S.Closed_On_Wake := True;
               Scheduler.Unpark (S.G);
            end;
         end loop;

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
               --  whatever the instantiation provides (Integer => 0,
               --  String => "", record types => their defaults).
               Scheduler.Unpark (R.G);
            end;
         end loop;
      end Mark_Closed;

      ---------------------------------------------------------------

      function Length return Natural is (Count);
      function Is_Closed return Boolean is (Closed_F);
      function Senders_Waiting return Natural is
        (Natural (Senders.Length));
      function Receivers_Waiting return Natural is
        (Natural (Receivers.Length));

   end Channel_State;

   --  ## Channel_Record
   --
   --  Heap object that the Channel handle wraps. Holds the protected
   --  state, sized at Make.

   type Channel_Record (Cap : Positive) is limited record
      State : Channel_State (Cap);
   end record;

   ---------------------------------------------------------------
   --  Public API
   ---------------------------------------------------------------

   function Make (Capacity : Positive) return Channel is
      R : constant Channel_Access :=
        new Channel_Record (Cap => Capacity);
   begin
      return (Ref => R);
   end Make;

   procedure Send (C : Channel; V : Element_Type) is
      Stored        : Boolean;
      Was_Closed    : Boolean;
      Slot          : Wait_Slot_Access;
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Bounded.Send: No_Channel";
      end if;

      C.Ref.State.Try_Buffered_Send (V, Stored, Was_Closed);
      if Was_Closed then
         raise Channel_Closed
           with "Gada.Async.Channels.Bounded.Send: channel is closed";
      end if;
      if Stored then
         return;
      end if;

      --  Buffer was full, no parked receiver — park.
      Slot := new Wait_Slot'(G              => Scheduler.Current,
                             Value          => V,
                             OK             => True,
                             Closed_On_Wake => False);
      C.Ref.State.Park_Sender (Slot, Was_Closed);
      if Was_Closed then
         Free_Slot (Slot);
         raise Channel_Closed
           with "Gada.Async.Channels.Bounded.Send: closed during park";
      end if;

      Scheduler.Park;
      --  Resumed. Either the matching Receive consumed our slot (and
      --  we returned successfully — Closed_On_Wake = False) or Close
      --  fired while we were parked (Closed_On_Wake = True; raise).
      declare
         Closed_On_Wake : constant Boolean := Slot.Closed_On_Wake;
      begin
         Free_Slot (Slot);
         if Closed_On_Wake then
            raise Channel_Closed
              with "Gada.Async.Channels.Bounded.Send: channel was "
                   & "closed while sender was parked";
         end if;
      end;
   end Send;

   procedure Receive
     (C  : Channel;
      V  : out Element_Type;
      OK : out Boolean)
   is
      Got        : Boolean;
      Was_Closed : Boolean;
      Slot       : Wait_Slot_Access;
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Bounded.Receive: No_Channel";
      end if;

      C.Ref.State.Try_Buffered_Receive (V, Got, Was_Closed);
      if Got then
         OK := True;
         return;
      end if;
      if Was_Closed then
         --  Buffer empty + channel closed — Go's zero-value-with-ok
         --  -false. Element_Type's default is the instantiation's
         --  zero; out parameter V is left at its initialised default.
         OK := False;
         return;
      end if;

      --  Buffer empty, channel open — park.
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
      --  Resumed: either a Send wrote into our slot (OK => True) or
      --  Close walked the parked-receivers list (OK => False).
      V  := Slot.Value;
      OK := Slot.OK;
      Free_Slot (Slot);
   end Receive;

   procedure Close (C : Channel) is
      Already_Closed : Boolean;
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Bounded.Close: No_Channel";
      end if;
      C.Ref.State.Mark_Closed (Already_Closed);
      if Already_Closed then
         raise Channel_Closed
           with "Gada.Async.Channels.Bounded.Close: already closed";
      end if;
   end Close;

   procedure Try_Send
     (C    : Channel;
      V    : Element_Type;
      Sent : out Boolean)
   is
      Stored     : Boolean;
      Was_Closed : Boolean;
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Bounded.Try_Send: No_Channel";
      end if;
      C.Ref.State.Try_Buffered_Send (V, Stored, Was_Closed);
      if Was_Closed then
         raise Channel_Closed
           with "Gada.Async.Channels.Bounded.Try_Send: channel is closed";
      end if;
      Sent := Stored;
   end Try_Send;

   procedure Try_Receive
     (C   : Channel;
      V   : in out Element_Type;
      OK  : out Boolean;
      Got : out Boolean)
   is
      Have       : Boolean;
      Was_Closed : Boolean;
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Bounded.Try_Receive: No_Channel";
      end if;
      declare
         V_Tmp : Element_Type := V;
      begin
         C.Ref.State.Try_Buffered_Receive (V_Tmp, Have, Was_Closed);
         if Have then
            V   := V_Tmp;
            OK  := True;
            Got := True;
            return;
         end if;
      end;
      if Was_Closed then
         --  Buffer empty + closed: surface the comma-ok-False shape
         --  to the select-side caller so it can dispatch the
         --  closed-channel branch the same way the blocking
         --  Receive does. V is left at the call-site value (see
         --  Try_Receive spec note).
         OK  := False;
         Got := True;
         return;
      end if;
      --  Empty + open: not ready for select.
      OK  := False;
      Got := False;
   end Try_Receive;

   function Length (C : Channel) return Natural is
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Bounded.Length: No_Channel";
      end if;
      return C.Ref.State.Length;
   end Length;

   function Capacity (C : Channel) return Positive is
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Bounded.Capacity: No_Channel";
      end if;
      return C.Ref.Cap;
   end Capacity;

   function Is_Closed (C : Channel) return Boolean is
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Bounded.Is_Closed: No_Channel";
      end if;
      return C.Ref.State.Is_Closed;
   end Is_Closed;

   function Senders_Waiting (C : Channel) return Natural is
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Bounded.Senders_Waiting: "
                & "No_Channel";
      end if;
      return C.Ref.State.Senders_Waiting;
   end Senders_Waiting;

   function Receivers_Waiting (C : Channel) return Natural is
   begin
      if C.Ref = null then
         raise Constraint_Error
           with "Gada.Async.Channels.Bounded.Receivers_Waiting: "
                & "No_Channel";
      end if;
      return C.Ref.State.Receivers_Waiting;
   end Receivers_Waiting;

end Gada.Async.Channels.Bounded;
