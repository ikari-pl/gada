## runtime/ — coverage exceptions

The default contract for `runtime/` is **100% executable line coverage**
(see `AGENTS.md` → "Design principles" → §1). Exceptions are listed
here per AGENTS.md's policy:

> Deviations are documented per package in
> `runtime/<package>/COVERAGE.md` with rationale and an explicit
> reviewer-approved exception.

The mechanical enforcement of these exceptions lives in
`tools/coverage_thresholds.toml` (top-level `[[exclude]]` entries),
read by `tools/coverage_gate.sh`. This file is the **rationale**
side of that pair: a code review that touches an exclusion should
load both files and confirm the entries still apply.

### `runtime/src/gada-async-context.adb`

#### `Make` — libco OOM path  *(lines 243–244)*

```ada
if New_Co = Libco.Null_Cothread then
   raise Storage_Error
     with "Gada.Async.Context.Make: co_create returned NULL";
end if;
```

`libco.co_create` calls `LIBCO_MALLOC(size)` and returns NULL on
failure. CI runs on Linux (overcommit on by default) and macOS arm64
(very-large per-process VA), and **neither** deterministically returns
NULL for any `Stack_Size` value representable in `Positive`. Common
ground tactics — `Stack_Size => Positive'Last`, `setrlimit(RLIMIT_AS)`,
`MallocFailureLog` on Darwin — either succeed transparently or are
non-portable across the CI fleet.

The defensive raise is **one statement guarded by a deterministic
equality test against `Null_Cothread`**: a code-review pass over the
surrounding seven lines is sufficient to verify it. The Phase 3
scheduler (roadmap item 3) will introduce a fault-injection seam
through which a synthetic NULL can be threaded; once that seam lands
the exclusion should be removed and the test added.

#### `Trampoline` — tail-loop terminator  *(line 215)*

```ada
loop
   Libco.Co_Switch (State.Lookup_Exit (Self));
end loop;     --  line 215
```

`Trampoline` is `pragma No_Return`. The tail loop has no exit branch
and `Co_Switch` does not return to the caller (it switches the libco
cothread away and only returns *if* something later switches back —
but then the loop body re-runs, never the trailing `end loop;`).

GCC still emits a basic block at `end loop;` for the implicit fall-
through that the language standard requires; gcov instruments it as
executable but it is unreachable under any input. Excluding it keeps
the 100% gate honest without forcing dead-code synthesis just to
satisfy a coverage tool.

#### `Trampoline` — C-boundary exception arm  *(lines 197, 198, 202)*

```ada
begin
   Ep.all;
exception
   when E : others =>                                 --  line 197
      Ada.Text_IO.Put_Line                            --  line 198
        (Ada.Text_IO.Standard_Error,
         "Gada.Async.Context.Trampoline: unhandled "
         & "exception from cothread entry: "
         & Ada.Exceptions.Exception_Information (E)); --  line 202
end;
```

`Trampoline` is `Convention => C` — libco invokes it via a
`void(*)(void)` C function pointer, and propagating an Ada exception
across that frame is undefined behaviour on the Itanium / AArch64
unwinders. The `when E : others` arm catches and logs to stderr so the
unwinder never crosses the C ABI boundary.

Triggering this arm in a unit test is a chicken-and-egg problem: the
only code that runs *on* a libco cothread under this body IS the
trampoline, so a "raising" entry would have to be installed by the
same `Make` path we're testing. The Phase 3 scheduler's
`Goroutine_Trampoline` (already in this PR, layered above
`Gada.Async.Context`) will introduce a panic-injection seam that
re-covers these lines from one layer up — at which point this
exception can be removed.

Added in PR #3 review feedback (gemini-code-assist comment #1).

---

### `runtime/src/gada-async-scheduler.adb`

#### `Init` — per-worker `new Worker_Task` rollback  *(lines 547–553)*

```ada
begin
   for I in 1 .. Effective_Workers loop
      Run_Queue.Worker_Started;
      The_Workers (I) := new Worker_Task (Idx => I);
   end loop;
exception
   when others =>                          --  line 547
      Run_Queue.Worker_Stopped;            --  line 548
      Run_Queue.Mark_Shutdown;             --  line 549
      Run_Queue.Drain;                     --  line 550
      The_Workers := null;                  --  line 551
      Run_Queue.Set_Initialised (False);   --  line 552
      raise;                                --  line 553
end;
```

`Init` flips `Initialised => True` and bumps `Workers_Active` once per
allocated worker *before* the per-task `new Worker_Task` runs, so a
`Shutdown` racing in between sees a sane state. If a `new Worker_Task`
itself raises (Storage_Error on a tight task-storage budget,
Tasking_Error on a policy mismatch with the target's runtime), the
rollback arm undoes the just-bumped-but-not-allocated counter
(`Worker_Stopped`), tells the workers that *did* succeed to drain
(`Mark_Shutdown` + `Drain`), nulls the array (lets Boehm GC reclaim it),
and clears the lifecycle flag so the next `Init` doesn't see "already
initialised" and a future `Shutdown.Drain` doesn't wait forever for a
worker that was never spawned.

Triggering it requires Storage_Error or Tasking_Error from the Ada
task allocation path, which the Alire FSF GNAT 15.1 runtime does not
expose a portable hook for. A future fault-injection seam (slated
alongside the lock-free queue work tracked in `runtime/PERF.md`) will
re-cover this rollback; the seven-statement arm is straightforward
enough for a code-review pass until then.

Added in PR #3 review feedback (gemini-code-assist comment #2),
lifted to the multi-worker rollback shape in sub-item 3b. Sub-items
3c (the worker-local SPSC YIELDED list) and 3e (Enter_Syscall /
Exit_Syscall surface) shifted the line numbers but did not change
the arm's structure.

#### `Spawn` — `Make` failure leak guard  *(lines 587–589)*

```ada
begin
   Gada.Async.Context.Make
     (G.Ctx, Goroutine_Trampoline'Access, Stack_Size => 256 * 1024);
exception
   when others =>          --  line 587
      Free_Goroutine (G);  --  line 588
      raise;                --  line 589
end;
```

Both `Spawn` failure paths — `Init` not called and `Make` raising
`Storage_Error` from libco's `co_create` — would otherwise leak the
`Goroutine_Record` allocated at the head of `Spawn`. The Boehm GC
would eventually reclaim it, but a deterministic free narrows the
failure-mode surface for scheduler stress tests.

This shares a fault-injection prerequisite with the
`Make` OOM exclusion in `gada-async-context.adb:243` — when the
Phase 3 seam lands it re-covers both the raise and this cleanup arm
in a single test.

Added in PR #3 review feedback (gemini-code-assist comment #4).

---

### `runtime/src/gada-async-channels-bounded.adb`

#### `Send` — `Park_Sender` close-race recheck  *(lines 413–414)*

```ada
C.Ref.State.Park_Sender (Slot, Was_Closed);
if Was_Closed then
   Free_Slot (Slot);                                  --  line 413
   raise Channel_Closed                               --  line 414
     with "Gada.Async.Channels.Bounded.Send: closed during park";
end if;
```

`Park_Sender` re-checks `Closed_F` under its protected lock before
appending the caller's `Wait_Slot` to the parked-senders list. The
arm fires only if a third party calls `Close` in the source-line gap
between the caller's `Try_Buffered_Send` (which returned
`Was_Closed = False`, otherwise we'd have raised earlier on line
399) and `Park_Sender`'s own `Closed_F` test.

GNAT's protected calls are uninterruptible — the only window for
the race is the Ada source-line gap between the two calls, with the
calling cothread fully scheduled on its worker for the duration. A
deterministic single-worker test that owns the Send's caller cannot
interpose a Close at that exact gap; multi-worker tests can race
but cannot *force* the race to land on this specific gap rather
than the larger pre-`Try_Buffered_Send` gap. A future fault-
injection seam (slated alongside Phase 4 panic-marshalling work)
will park the calling goroutine *between* those two protected calls,
fire a Close, and re-cover this arm. Two lines.

#### `Receive` — `Park_Receiver` send/close-race recheck  *(lines 466–468, 471–473)*

```ada
C.Ref.State.Park_Receiver (Slot, V, Got, Was_Closed);
if Got then
   Free_Slot (Slot);   --  line 466
   OK := True;          --  line 467
   return;              --  line 468
end if;
if Was_Closed then
   Free_Slot (Slot);   --  line 471
   OK := False;         --  line 472
   return;              --  line 473
end if;
```

Mirror image of the Send-side race-recheck above. `Park_Receiver`
re-checks `Count > 0` and `Closed_F` under its protected lock;
either arm fires only if a third party Sends or Closes in the source-
line gap between the caller's `Try_Buffered_Receive` and
`Park_Receiver`'s own re-tests. Same single-worker-determinism
constraint as the Send arm. Six lines (two 3-line arms). The same
fault-injection seam covers both arms.

The arms are not dead code — they exist *because* the race window is
real and silent corruption (a parked receiver that should have
matched a freshly-arrived sender, or a parked receiver that hangs
forever on a freshly-closed channel) is unacceptable. Excluding
them here documents the testability gap, not their value.

---

### `runtime/src/gada-async-channels-unbounded.adb`

#### `Receive` — `Park_Receiver` send/close-race recheck  *(lines 387–389, 392–394)*

```ada
C.Ref.State.Park_Receiver (Slot, V, Got, Was_Closed);
if Got then
   Free_Slot (Slot);   --  line 387
   OK := True;          --  line 388
   return;              --  line 389
end if;
if Was_Closed then
   Free_Slot (Slot);   --  line 392
   OK := False;         --  line 393
   return;              --  line 394
end if;
```

Mirror of the Channels.Bounded Park_Receiver race-recheck above.
Same single-worker-determinism constraint: the only window for the
race is the Ada source-line gap between `Try_Receive` and
`Park_Receiver`, which a single-worker test cannot interpose a
third-party Send or Close into. Same Phase 4 fault-injection seam
closes both. Six lines (two 3-line arms).

The Send-side mirror is intentionally absent — `Unbounded.Send`
never blocks (there is no buffer-full state), so there is no
`Park_Sender` arm to either ship or exclude. This is the structural
asymmetry between bounded and unbounded channels carried into the
coverage surface.

---

### `runtime/src/gada-async-selector.adb`

#### `Shuffle` — float-rounding clamp + loop terminator  *(lines 76, 81)*

```ada
J :=
  A'First
  + Natural (Float'Floor
      (Random (Gen) * Float (I - A'First + 1)));
if J > I then
   J := I; -- defensive cap on float-rounding edges  --  line 76
end if;
...
end loop;                                            --  line 81
```

`Ada.Numerics.Float_Random.Random` returns a value in `[0.0, 1.0)`,
so `Float'Floor (Random * Float (N))` is always `< N` and the
`J > I` clamp at line 76 is unreachable on every IEEE-conformant
target. We keep the clamp because:

  * Ada's RNG spec leaves the half-open boundary
    implementation-defined; a future toolchain that accidentally
    returns 1.0 (e.g. via a non-IEEE round-to-positive-infinity
    cast) would land *exactly* on `J = I + 1`, producing an array
    out-of-range read.
  * The clamp is one statement, deterministic on review, and
    cheaper than narrowing the type or asserting at runtime.

Line 81 is the implicit basic block at the bottom of Shuffle's
outer `for I in reverse ... loop`. Same pattern as `Gada.Async.
Context.Trampoline`'s tail-loop terminator (`gada-async-context.adb:
215`): gcov instruments the line as executable but control never
reaches it under normal flow.

#### `Try_One_Case` — Default/Timeout dead arm  *(lines 127–129)*

```ada
when Default_Op | Timeout_Op =>
   Fired := False;                                   --  line 127
end case;                                            --  line 128 (block end)
end Try_One_Case;                                    --  line 129
```

`Try_One_Case` is invoked only from `Select_One`, which filters out
`Default_Op` and `Timeout_Op` before the call:

```ada
if Cases (Idx).Kind not in Default_Op | Timeout_Op then
   Try_One_Case (Cases (Idx), Fired);
   ...
end if;
```

The arm is therefore unreachable. We keep it for Ada
exhaustiveness — the `Fired := False` write is defensive
belt-and-braces in case a future refactor calls `Try_One_Case`
directly. A future invariant-tightening pass (per the same
fault-injection seam tracked alongside the channels race-window
exclusions) may replace it with a `pragma Assert (Kind in
Send_Op | Recv_Op)` and remove the arm.

#### `Select_One` — declare-block terminator  *(line 256)*

```ada
loop
   ...                  --  every exit branch is `return`
end loop;
end;                                                  --  line 256
end Select_One;
```

The outer `loop ... end loop;` only exits via `return Default_
Index;`, `return Timeout_Index;`, or `return Idx;`. Control never
reaches the `end;` of the enclosing `declare` block. Same shape as
`Gada.Async.Context.Trampoline`'s tail-loop end exclusion.

---

### Adding a new exception

1. Confirm the line is **genuinely** untestable in CI (not just
   "haven't gotten around to it yet"). Document a Phase-N follow-up
   to remove the exclusion when the missing seam lands.
2. Add a `[[exclude]]` block in `tools/coverage_thresholds.toml`
   with `file`, `lines`, and a `reason` that points back here.
3. Add a section to this file explaining *why*. A future reader
   should be able to decide whether the exclusion still applies
   without re-deriving the analysis.
4. Get a code-review sign-off on the exclusion specifically.
