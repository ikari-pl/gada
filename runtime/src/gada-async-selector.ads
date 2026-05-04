--  Gada.Async.Selector — Go's `select` statement runtime.
--
--  Lowers Go's
--
--    select {
--    case v := <-ch1:        ...
--    case ch2 <- value:      ...
--    case <-time.After(d):   ...
--    default:                ...
--    }
--
--  to a single Selector.Select_One call over an array of Case_Item
--  records. Each case names one Op_Kind:
--
--    Send_Op    — a Try_Send on the channel; "ready" when the
--                 channel's buffer has a free slot OR a parked
--                 receiver is waiting. The Send_V field is the
--                 value to send.
--    Recv_Op    — a Try_Receive on the channel; "ready" when the
--                 buffer has a value OR the channel is closed (the
--                 closed-empty case yields OK = False, mapping Go's
--                 zero-value-with-ok-false). The Recv_V / Recv_OK
--                 fields are filled in on success.
--    Default_Op — fires immediately if no other case is ready.
--                 Matches Go's `default:` clause.
--    Timeout_Op — fires after the given Duration. Models Go's
--                 `case <-time.After(d):` shape without requiring
--                 the std time-channel adapter (which lives in
--                 stdlib/, not the runtime).
--
--  ## v1 limitations (Phase 3 ship; Phase 4 follow-up)
--
--    * Single Element_Type per select. Go's select is fully
--      heterogeneous (different cases can name channels of
--      different element types). Doing that in Ada generic code
--      requires either a void* type-erasure scheme or a discriminant
--      record over every Element_Type the program uses. Phase 4's
--      compiler emit will add the type-erasure path; for v1, every
--      case must use the same Element_Type so the generic body can
--      read/write the value uniformly.
--
--    * Bounded-only. Channels.Unbounded is omitted from the case
--      vocabulary because Send-on-unbounded never blocks (its
--      "ready" predicate is always True barring closed), which
--      makes mixed bounded+unbounded selects degenerate into "the
--      first unbounded Send_Op always wins". Phase 4 may
--      reintroduce unbounded sends with a fairness adjustment.
--
--    * Polling loop, not parked-waiter. The implementation tries
--      each case in random order; if none ready and no Default,
--      it sleeps for a small interval and retries until one
--      becomes ready or the Timeout expires. This is correct under
--      our pinning model (the polling goroutine releases its
--      worker via the delay), but it has higher tail latency than
--      Go's parked-waiter scheme. Phase 4 will lift to per-case
--      Wait_Slot registration on the channels' parked queues with
--      a Select_State coordinator that does atomic claim-once
--      across waiters — same machinery Go's runtime/select.go uses.
--
--  ## Pseudo-random tie-breaking
--
--  When multiple cases are simultaneously ready, Go picks among
--  them uniformly at random. We use Ada.Numerics.Discrete_Random
--  seeded once per Select_One call so a given select instance
--  produces a fresh permutation. The shuffle is a Fisher-Yates over
--  the case-index array; Try_Op runs in the shuffled order, first
--  ready case wins.

with Gada.Async.Channels.Bounded;

generic
   type Element_Type is private;
   with package Bnd is new Gada.Async.Channels.Bounded (Element_Type);
package Gada.Async.Selector is

   type Op_Kind is
     (Send_Op,
      Recv_Op,
      Default_Op,
      Timeout_Op);

   --  Named access types for the Recv_Op out-pointers. Library-level
   --  accessibility — callers must heap-allocate (`new Element_Type'
   --  (initial)`) rather than pass `'Access` of stack locals. v1's
   --  compiler-emit hoists Recv-bound locals to a stack-frame heap
   --  scope; tests follow the same idiom.
   type Element_Ptr is access all Element_Type;
   type Boolean_Ptr is access all Boolean;

   --  One case in a select. Field discrimination is by Kind; only
   --  the Kind-specific fields are read.
   --
   --  We use a flat record (rather than a discriminant variant
   --  record) because the case array is built up element-by-element
   --  by generated code; a discriminant would force a type-cast on
   --  every assignment.
   --
   --  Recv_V_Out / Recv_OK_Out hold the named Element_Ptr / Boolean_
   --  Ptr access types declared above. They have library-level
   --  accessibility, which forces callers to pass heap-allocated
   --  values (`new Element_Type'(initial)` / `new Boolean'(...)`)
   --  rather than `'Access` of stack-aliased locals. A previous
   --  draft used anonymous access types here — anonymous access
   --  components in record types declared at library level *also*
   --  have library-level accessibility per Ada 2012's accessibility
   --  rules, so the change to named types preserves the same
   --  caller-side ergonomics while giving the access types a name
   --  the test suite and Phase 4 compiler-emit can refer to
   --  explicitly. See lines 114-118 below for the caller pattern.
   type Case_Item is record
      Kind             : Op_Kind := Default_Op;

      --  Send_Op / Recv_Op — channel handle.
      Chan             : Bnd.Channel := Bnd.No_Channel;

      --  Send_Op only.
      Send_V           : Element_Type;

      --  Recv_Op only — out-pointers to caller-allocated locals. Set
      --  to null in cases where the user discards the value (Go's
      --  `<-ch` form without binding); Select_One performs the
      --  Try_Receive but skips the writeback when the pointer is
      --  null.
      --
      --  Pointers are anonymous access types so the caller can
      --  pass heap-allocated `new Element_Type'(...)` /
      --  `new Boolean'(...)` directly. v1's compiler-emit (Phase 4)
      --  will hoist these allocations to the select scope; tests
      --  drive them via the local heap-allocation idiom.
      Recv_V_Out       : Element_Ptr := null;
      Recv_OK_Out      : Boolean_Ptr := null;

      --  Timeout_Op only — duration after which the case fires if
      --  no other case has become ready.
      Timeout_Duration : Duration := 0.0;
   end record;

   type Case_Array is array (Positive range <>) of Case_Item;

   --  Drives the select. Returns the 1-based index (within Cases)
   --  of the case that fired. Side effects:
   --
   --    Send_Op    — V was sent on the channel.
   --    Recv_Op    — Recv_V_Out.all and Recv_OK_Out.all are set
   --                 (skipped if either pointer is null).
   --    Default_Op — no side effect; caller branches on the index.
   --    Timeout_Op — no side effect; caller branches on the index.
   --
   --  Concurrency: the polling shape implies the calling goroutine
   --  yields between polls (`delay 0.0` releases the worker so
   --  siblings on the same OS thread make progress). Calling
   --  Select_One from a non-goroutine context with no Default and
   --  no Timeout will spin-with-yield indefinitely until some sibling
   --  task advances a channel — the same shape as a non-goroutine
   --  Receive on an empty channel.
   function Select_One (Cases : Case_Array) return Positive
     with Pre => Cases'Length >= 1;

   --  Raised when the cases array contains no cases at all (an
   --  empty `select {}` would be Go's deadlock-forever shape; we
   --  raise instead so the program can be diagnosed). Also raised
   --  if more than one Default_Op is supplied — Go's compiler
   --  rejects this, but our runtime sees the lowered case array
   --  and is the last line of defence.
   Selector_Error : exception;

private

   --  Tick interval between polls when no case is immediately
   --  ready and no Default is present. Picked at 1 ms because:
   --
   --    * Shorter (e.g. 100 µs) burns CPU on heavily-loaded shared
   --      schedulers.
   --    * Longer (e.g. 10 ms) shows up as visible latency in the
   --      ping-pong example's chained selects.
   --
   --  Phase 4's parked-waiter rework will eliminate this constant
   --  altogether — the polling loop disappears in favour of
   --  channel-side Unpark.
   Poll_Interval : constant Duration := 0.001;

end Gada.Async.Selector;
