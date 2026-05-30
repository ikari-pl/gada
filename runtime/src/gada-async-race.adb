--  Body of Gada.Async.Race — see spec for the cooperative model and
--  docs/adr/0010-race-detection-best-effort.md for what it does and
--  does not catch.
--
--  ## Monitor shape
--
--  Each Checked_Cell instance owns one protected Monitor (heap-
--  allocated behind the Cell_Type handle). The monitor tracks:
--
--    * Holder      — the goroutine currently inside an access section,
--                    or No_Goroutine if the cell is idle.
--    * Holder_Mode — the strongest mode that holder has declared in the
--                    current (possibly re-entrant) section. Read can be
--                    escalated to Write by a nested Begin_Access (Write)
--                    from the same goroutine; once Write it stays Write
--                    until the section fully closes.
--    * Depth       — re-entrancy counter so nested Begin/End from the
--                    same goroutine balance and the holder only clears
--                    on the outermost End_Access.
--    * The latched Race_Report (first race wins).
--
--  A race is recorded when Begin_Access arrives from a goroutine that
--  is NOT the current holder while the cell is held, and at least one
--  of {Holder_Mode, incoming Mode} is Write. The verdict is a pure
--  function of the Begin/End call order, so the suite drives it
--  deterministically. The end-to-end test spawns two goroutines that
--  each open a Write section and rendezvous on a protected entry so the
--  two sections provably overlap; the monitor latches the collision the
--  instant the second Begin_Access lands. Detection itself does not
--  depend on any particular OS-thread interleaving — the latch is taken
--  under the monitor's own lock.

with Ada.Strings.Fixed;

package body Gada.Async.Race is

   use type Gada.Async.Scheduler.Goroutine_Id;

   --  Stable short tag for a goroutine handle. We do not expose the
   --  underlying pointer identity (private), so the report renders a
   --  goroutine as either "none" (No_Goroutine) or "g#<n>" where <n>
   --  distinguishes the two holders within a single report — it is a
   --  diagnostic aid, not a stable cross-run identifier. Written as an
   --  expression function whose `(if ...)` is short enough that lcov 2.x
   --  attributes the hit to the `is (...)` line, so it needs no coverage
   --  exclusion. (Image below is longer; its expression-function form
   --  trips an lcov line-attribution quirk, so it ships as a begin/end
   --  body with the one terminator line excluded — see its comment.)
   function Holder_Tag
     (Who  : Gada.Async.Scheduler.Goroutine_Id;
      Slot : Positive) return String
   is (if Who = Gada.Async.Scheduler.No_Goroutine then "none"
       else "g#" & Ada.Strings.Fixed.Trim (Slot'Image, Ada.Strings.Left));

   -----------
   -- Image --
   -----------

   --  A normal begin/end body with a single returned conditional
   --  expression. Both arms (no-race / detected) are exercised by
   --  race_suite's Image test. The trailing `end Image;` is an
   --  unreachable fall-through basic block (the function always returns
   --  on line above), which lcov 2.x counts but no input reaches — the
   --  same unreachable-terminator shape already excluded for
   --  Gada.Async.Selector's Select_One end-block and the No_Return
   --  Trampoline tail loop. It is excluded in tools/coverage_thresholds.
   --  toml with a rationale in runtime/COVERAGE.md. (Folding to an
   --  expression function does NOT help — lcov 2.x then marks the
   --  expression-function signature line uncovered instead; either form
   --  leaves exactly one un-coverable line, verified empirically.)
   function Image (R : Race_Report) return String is
   begin
      return
        (if not R.Detected then "no race"
         else "data race: "
           & Holder_Tag (R.First_Holder, 1) & " (" & R.First_Mode'Image
           & ") concurrent with "
           & Holder_Tag (R.Second_Holder, 2) & " (" & R.Second_Mode'Image
           & ")");
   end Image;

   -----------------
   -- Checked_Cell --
   -----------------

   package body Checked_Cell is

      --  Forward declarations of the body-local helpers (style: nested
      --  package-body subprograms are forward-declared up front).

      --  The per-cell protected monitor. All state mutation funnels
      --  through here so concurrent Begin/End calls from distinct
      --  workers serialise.
      protected type Monitor is

         procedure Begin_Access
           (Mode : Access_Mode;
            Who  : Gada.Async.Scheduler.Goroutine_Id);

         procedure End_Access (Who : Gada.Async.Scheduler.Goroutine_Id);

         procedure Store (Value : Element_Type);
         function  Load return Element_Type;

         function Race_Detected return Boolean;
         function Report return Race_Report;

      private
         Value       : Element_Type := Default;
         Holder      : Gada.Async.Scheduler.Goroutine_Id :=
           Gada.Async.Scheduler.No_Goroutine;
         Holder_Mode : Access_Mode := Read;
         Depth       : Natural := 0;
         Race        : Race_Report := No_Race;
      end Monitor;

      protected body Monitor is

         procedure Begin_Access
           (Mode : Access_Mode;
            Who  : Gada.Async.Scheduler.Goroutine_Id) is
         begin
            if Depth = 0 then
               --  Cell idle: take ownership.
               Holder      := Who;
               Holder_Mode := Mode;
               Depth       := 1;
            elsif Holder = Who then
               --  Same goroutine re-entering: nest, escalate Read→Write
               --  if this access writes. The holder is unchanged.
               Depth := @ + 1;
               if Mode = Write then
                  Holder_Mode := Write;
               end if;
            else
               --  A distinct goroutine arrived while the cell is held.
               --  If either side writes, it's a data race. Latch the
               --  first one (Detected guard keeps the first verdict).
               if not Race.Detected
                 and then (Holder_Mode = Write or else Mode = Write)
               then
                  Race :=
                    (Detected      => True,
                     First_Holder  => Holder,
                     Second_Holder => Who,
                     First_Mode    => Holder_Mode,
                     Second_Mode   => Mode);
               end if;
               --  The intruder does NOT take ownership: the original
               --  holder keeps its section. The intruder's matching
               --  End_Access is a no-op (Who /= Holder), so the books
               --  stay balanced for the real holder.
            end if;
         end Begin_Access;

         procedure End_Access
           (Who : Gada.Async.Scheduler.Goroutine_Id) is
         begin
            if Depth > 0 and then Holder = Who then
               Depth := @ - 1;
               if Depth = 0 then
                  Holder      := Gada.Async.Scheduler.No_Goroutine;
                  Holder_Mode := Read;
               end if;
            end if;
            --  Else: unbalanced / intruder End_Access — defensively
            --  ignored so a buggy caller cannot clear another
            --  goroutine's live section.
         end End_Access;

         procedure Store (Value : Element_Type) is
         begin
            Monitor.Value := Value;
         end Store;

         function Load return Element_Type is (Value);

         function Race_Detected return Boolean is (Race.Detected);

         function Report return Race_Report is (Race);

      end Monitor;

      --  The heap state behind a Cell_Type handle is just the monitor.
      type Cell_State is record
         Mon : Monitor;
      end record;

      ----------
      -- Make --
      ----------

      function Make return Cell_Type is
      begin
         return (Ref => new Cell_State);
      end Make;

      ------------------
      -- Begin_Access --
      ------------------

      procedure Begin_Access
        (C    : in out Cell_Type;
         Mode : Access_Mode;
         Who  : Gada.Async.Scheduler.Goroutine_Id) is
      begin
         C.Ref.Mon.Begin_Access (Mode, Who);
      end Begin_Access;

      ----------------
      -- End_Access --
      ----------------

      procedure End_Access
        (C   : in out Cell_Type;
         Who : Gada.Async.Scheduler.Goroutine_Id) is
      begin
         C.Ref.Mon.End_Access (Who);
      end End_Access;

      ----------
      -- Load --
      ----------

      function Load (C : Cell_Type) return Element_Type is
        (C.Ref.Mon.Load);

      -----------
      -- Store --
      -----------

      procedure Store (C : in out Cell_Type; Value : Element_Type) is
      begin
         C.Ref.Mon.Store (Value);
      end Store;

      -------------------
      -- Race_Detected --
      -------------------

      function Race_Detected (C : Cell_Type) return Boolean is
        (C.Ref.Mon.Race_Detected);

      ------------
      -- Report --
      ------------

      function Report (C : Cell_Type) return Race_Report is
        (C.Ref.Mon.Report);

   end Checked_Cell;

end Gada.Async.Race;
