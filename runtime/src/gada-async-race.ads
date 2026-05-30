--  Gada.Async.Race — best-effort cooperative data-race detector.
--
--  Phase 3 "Race detector integration (best-effort)" surface. This is
--  NOT a TSan-style happens-before detector: GADA does not ship a full
--  shadow-memory/vector-clock engine for v1 (the same "precise X is a
--  research effort, not a 1.0 deliverable" stance CLAUDE.md takes on the
--  GC). What it IS: a lightweight *checked cell* — a guarded location
--  whose every access is funnelled through a protected monitor that
--  records the accessing goroutine and access mode (Read / Write) and
--  flags the moment two DISTINCT goroutines hold overlapping access
--  sections where at least one is a Write. That is exactly Go's data-
--  race definition ("two goroutines access the same variable
--  concurrently and at least one of the accesses is a write") narrowed
--  to a single instrumented cell.
--
--  The full rationale, the cooperative model, and — importantly — what
--  this does and does NOT catch live in
--  docs/adr/0010-race-detection-best-effort.md. Read that before
--  relying on this for anything beyond the instrumented-cell contract.
--
--  ## Cooperative model
--
--  Callers bracket each access to the guarded value with
--  Begin_Access / End_Access:
--
--     declare
--        package Cell is new Gada.Async.Race.Checked_Cell
--          (Element_Type => Integer, Default => 0);
--        C : Cell.Cell_Type := Cell.Make;
--     begin
--        Cell.Begin_Access (C, Write, Me);   --  Me : Goroutine_Id
--        Cell.Store (C, 42);
--        Cell.End_Access (C, Me);
--     end;
--
--  A correctly-synchronised program calls End_Access before any other
--  goroutine calls Begin_Access on the same cell — accesses do not
--  overlap, and Race_Detected stays False. A buggy program lets two
--  goroutines hold open access sections at once (e.g. both Begin_Access
--  (Write, ...) without an intervening End_Access); the monitor sees a
--  second distinct holder arrive while the first is still in its
--  section and, if either is a Write, records a Race_Report.
--
--  ## What it catches  (see ADR-0010 for the full table)
--
--    * Write/Write and Read/Write *overlap* on one instrumented cell
--      from two distinct goroutines — the canonical unsynchronised
--      access. Detected and reported deterministically.
--
--  ## What it does NOT catch
--
--    * Anything not routed through a Checked_Cell. Raw slices, maps,
--      record fields, and pointer chases are invisible (no general
--      shadow memory).
--    * Read/Read overlap — concurrent reads are not a race (matches Go).
--    * Happens-before via channels / locks beyond the cell's own
--      Begin/End bracket — there is no vector clock. A program that is
--      *actually* race-free but brackets sloppily can produce a false
--      positive; a program that races on memory it never wrapped
--      produces a false negative. This is a *cooperative* aid, not a
--      sound-and-complete detector.
--
--  ## Layering
--
--  Lives in the Async layer. Depends only on Gada.Async.Scheduler
--  (for Goroutine_Id identity) — never on Context or libco directly.
--  Deterministic by construction: the monitor's verdict is a pure
--  function of the Begin/End call sequence, so tests drive it without
--  timing races.

with Gada.Async.Scheduler;

package Gada.Async.Race is

   --  Access intent declared at Begin_Access. Two overlapping accesses
   --  race iff at least one is a Write (Read/Read overlap is benign,
   --  matching Go's memory model).
   type Access_Mode is (Read, Write);

   --  A race report: who collided, in which modes. First_Holder is the
   --  goroutine already inside its access section; Second_Holder is the
   --  one that arrived and triggered the verdict. Modes record the
   --  intent each declared so a diagnostic can say "write/write" vs
   --  "read/write".
   type Race_Report is record
      Detected      : Boolean := False;
      First_Holder  : Gada.Async.Scheduler.Goroutine_Id :=
        Gada.Async.Scheduler.No_Goroutine;
      Second_Holder : Gada.Async.Scheduler.Goroutine_Id :=
        Gada.Async.Scheduler.No_Goroutine;
      First_Mode    : Access_Mode := Read;
      Second_Mode   : Access_Mode := Read;
   end record;

   No_Race : constant Race_Report :=
     (Detected      => False,
      First_Holder  => Gada.Async.Scheduler.No_Goroutine,
      Second_Holder => Gada.Async.Scheduler.No_Goroutine,
      First_Mode    => Read,
      Second_Mode   => Read);

   --  Render a report as a stable human-readable line for logs /
   --  test diagnostics. Pure: no side effects, no globals.
   function Image (R : Race_Report) return String;

   ----------------------------------------------------------------
   --  Checked_Cell — a guarded value with race-checked access.
   ----------------------------------------------------------------

   generic
      type Element_Type is private;
      Default : Element_Type;
   package Checked_Cell is

      type Cell_Type is private;

      --  A fresh cell holding Default, with no open access section and
      --  a cleared race report.
      function Make return Cell_Type;

      --  Open an access section for Who in the given Mode. If another
      --  DISTINCT goroutine already has an open section and at least
      --  one of the two is a Write, a race is recorded into the cell's
      --  report (latched — the first race wins; subsequent collisions
      --  do not overwrite it). Begin_Access never blocks and never
      --  raises: a detected race is *data*, surfaced via Race_Detected
      --  / Report, not an exception. Calling Begin_Access twice from the
      --  SAME goroutine without an End_Access is re-entrancy, not a
      --  race (the holder is unchanged); the nesting depth is tracked
      --  so the matching End_Access calls balance.
      procedure Begin_Access
        (C    : in out Cell_Type;
         Mode : Access_Mode;
         Who  : Gada.Async.Scheduler.Goroutine_Id);

      --  Close Who's access section. Balanced against Begin_Access: a
      --  cell only clears its holder once the outermost End_Access for
      --  the current holder runs. End_Access by a goroutine that is not
      --  the current holder is a no-op (defensive — a buggy unbalanced
      --  caller cannot corrupt another goroutine's section).
      procedure End_Access
        (C   : in out Cell_Type;
         Who : Gada.Async.Scheduler.Goroutine_Id);

      --  Read the guarded value. Does not itself open a section — the
      --  caller is expected to bracket with Begin_Access (Read, ...) /
      --  End_Access around it; Load is the in-section accessor.
      function Load (C : Cell_Type) return Element_Type;

      --  Write the guarded value. As with Load, the caller brackets
      --  with Begin_Access (Write, ...) / End_Access.
      procedure Store (C : in out Cell_Type; Value : Element_Type);

      --  True once any race has been recorded on this cell.
      function Race_Detected (C : Cell_Type) return Boolean;

      --  The latched race report (No_Race until a race is recorded).
      function Report (C : Cell_Type) return Race_Report;

   private

      --  The cell is a handle to a heap-allocated state record carrying
      --  the protected monitor. A handle (rather than the protected
      --  object inline) keeps Cell_Type copyable / passable by value
      --  the same way Channel handles are, and lets two goroutines
      --  share one logical cell through copies of the handle.
      type Cell_State;
      type Cell_State_Access is access all Cell_State;

      type Cell_Type is record
         Ref : Cell_State_Access := null;
      end record;

   end Checked_Cell;

end Gada.Async.Race;
