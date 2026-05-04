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
