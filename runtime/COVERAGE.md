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

#### `Send` — `Park_Sender` close-race recheck  *(lines 448–449)*

```ada
C.Ref.State.Park_Sender (Slot, Was_Closed);
if Was_Closed then
   Free_Slot (Slot);                                  --  line 448
   raise Channel_Closed                               --  line 449
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

#### `Receive` — `Park_Receiver` send/close-race recheck  *(lines 527–529, 532–534)*

```ada
C.Ref.State.Park_Receiver (Slot, V, Got, Was_Closed);
if Got then
   Free_Slot (Slot);   --  line 527
   OK := True;          --  line 528
   return;              --  line 529
end if;
if Was_Closed then
   Free_Slot (Slot);   --  line 532
   OK := False;         --  line 533
   return;              --  line 534
end if;
```

The main-task timed-poll arms of both `Send` and `Receive` (including
the poll-sees-closed arms) are covered, not excluded:
`Test_Main_Task_{Send_Polls_When_Full, Receive_Polls_Until_Send,
Send_Poll_Raises_On_Close, Receive_Poll_Closed_Gives_False}`.

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

#### `Receive` — `Park_Receiver` send/close-race recheck  *(lines 416–418, 421–423)*

```ada
C.Ref.State.Park_Receiver (Slot, V, Got, Was_Closed);
if Got then
   Free_Slot (Slot);   --  line 416
   OK := True;          --  line 417
   return;              --  line 418
end if;
if Was_Closed then
   Free_Slot (Slot);   --  line 421
   OK := False;         --  line 422
   return;              --  line 423
end if;
```

The main-task timed-poll arm of `Receive` (including the
poll-sees-closed arm) is covered, not excluded:
`Channels_Unbounded_Suite.Test_Main_Task_Receive_Polls_Until_Send` and
`..._Poll_Closed_Gives_False`.

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
when Default_Op | Timeout_Op =>                      --  line 127
   Fired := False;                                   --  line 128
end case;                                            --  line 129
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

### `runtime/src/gada-async-race.adb`

#### `Image` — fall-through terminator  *(line 80)*

```ada
function Image (R : Race_Report) return String is
begin
   return
     (if not R.Detected then "no race"
      else "data race: " & ...);
end Image;     --  line 80
```

`Image` always returns — the single `return` of a conditional
expression covers both the no-race and the detected arm, and
`race_suite`'s `Test_Image_Renders_No_Race_And_Detected` exercises both
(including the `Holder_Tag` `"none"` / `"g#n"` branches). Control never
reaches the implicit basic block lcov 2.x instruments at `end Image;`.

Same unreachable-terminator category as the Selector `Select_One`
end-block (`gada-async-selector.adb:306`) and the `No_Return`
Trampoline tail loop (`gada-async-context.adb:215`).

What makes this one *unavoidable* rather than a test gap: it was
verified empirically against the project toolchain (Alire FSF GNAT
15.1 + lcov 2.4) that **both** function forms leave exactly one
un-coverable line:

  * a `begin/end` body leaves `end Image;` at hit-count 0 (the
    fall-through after the trailing `return`);
  * folding to an Ada 2022 *expression function* moves the problem —
    lcov 2.x then reports the expression-function's own signature line
    as uncovered (`"function 'image' is hit but no contained lines are
    hit"`), because it cannot reconcile a single-line function entry
    whose expression spans the following lines.

Neither form reaches 100% on its own. The `begin/end` body is the more
readable of the two equally-uncoverable shapes, so we ship it and
exclude the single terminator line rather than the signature line.
`Holder_Tag` (the sibling helper) is kept as an expression function and
is fully covered — its `(if ...)` is short enough that lcov attributes
the hit to the `is (...)` line, so it needs no exclusion.

Unlike the libco-OOM / Trampoline exclusions, there is no future
"fault-injection seam" that removes this one — it is a fixed property
of how lcov 2.x attributes basic blocks to an always-returning Ada
function. It can be revisited only if the coverage toolchain changes
its line attribution (e.g. a future lcov that drops the implicit
terminator block, or a switch to `gnatcoverage`).

---

### `runtime/src/gada-std-strconv.adb` (Phase 5)

Excluded lines (see `tools/coverage_thresholds.toml`):

  * **405-406, 415-418, 431-432** — the three zero-pad loop bodies of
    `Fmt_F`. These *are* executed — `Format_Float (123.0, 'f', 3) =
    "123.000"` can only be produced through the `RDP >= RN` pad arm
    (407-410), `Format_Float (1.5, 'f', 5) = "1.50000"` through the
    middle-branch pad (423-424) — yet lcov 2.4 reports hit-count 0 on
    the loop-body lines while crediting the `for` lines. Same
    misattribution class as the approved `gada-async-race.adb:80`
    terminator exclusion. (`Format_Float (0.5, 'f', 3) = "0.500"`
    additionally exercises 397-398 semantically.)
  * **451-452** — `return 17` fallback of `Shortest_K` plus its
    terminator. Unreachable by construction: 17 significant decimal
    digits always round-trip a binary64 (that is the worst case, and
    the `K = 17` iteration returns first). Mathematical fact, not a
    test gap.
  * **522, 694, 695, 697, 740, 745, 845, 868, 890, 902** —
    `end X;` fall-through terminators and `declare`/`end;` block
    markers (`end Normalize;`, `end Format_Float;`, `end Message;`,
    inner block ends in the 'g' branch, Parse_Float and Unquote).
    lcov 2.x instruments the implicit basic block at 0 even when the
    enclosing routine is fully covered — the same fixed toolchain
    property documented for `gada-async-race.adb:80`.
  * **751, 753, 755, 756** — `Parse_Float`'s `when Constraint_Error`
    arm. The Alire FSF GNAT 15.1 runtime *returns* ±Inf on decimal
    overflow instead of raising, so this arm cannot fire on the CI
    toolchain; the `Value > Long_Float'Last` post-check right below it
    handles the overflow and is covered by the `1e999`/`-1e999`
    Err_Range tests. The arm is kept for GNAT modes/configurations
    that do raise.

### `runtime/src/gada-std-strings.adb` (Phase 5)

Excluded lines: 142, 249, 377, 386, 395, 522, 544 — `end loop;` /
`end To_Upper;` / `end To_Lower;` / `end Map;` terminators and two
`declare` markers in `Replacer.Replace`. All executed — the Split,
Case and Replacer tests are green in the same run — but lcov 2.4
leaves hit-count 0 on in-loop returns and block markers. Same
misattribution class as `gada-async-race.adb:80`.

### `runtime/src/gada-std-fmt.adb` (Phase 5)

Excluded lines: 54, 55, 100, 143, 253, 314, 390, 400, 440, 509. Line 54
(`when others => null;` in `Parse_Spec`) is unreachable by
construction: the `while` guard already restricts `F (I)` to
`'-' | '+' | ' ' | '#' | '0'`, so the `others` arm can never fire —
defensive exhaustiveness. The rest are `end;`/`declare` block markers
misattributed by lcov 2.4 (same class as above).

### `runtime/src/gada-std-os.adb` (Phase 5)

Superseded by the Phase 6 wave 2 entry below: the Read_File body was
rewritten (heap buffer + directory guard), so the old Phase-5 line
numbers no longer exist. The current exclusions for this file are
documented in the Phase 6 wave 2 section.

### `runtime/src/gada-std-bytes.adb`, `gada-std-bufio.adb`, `gada-std-io.adb` (Phase 5)

bytes: 28, 122, 166 — `end To_String;` terminators and an `end loop;`
marker. bufio: 51, 106, 179, 295 — `end Fill;`, two `declare` markers
in the Read_Line/Read_String search loops, and the `end if;` after
Scanner's final-token `return True;` (executed by the "final token
w/o LF" assert). The stored-error branches of Read/Read_Line/
Read_String are covered by the readErr tests, not excluded. io: 44,
57, 81 — the inner `end;`, `end Copy;`, `end Read_All;` markers (the
ErrShortWrite arm itself is covered by the short-write test). All in
the lcov 2.4 misattribution class documented above.

### `runtime/src/gada-std-time.adb` (Phase 6 wave 2)

69, 231, 242, 455 — `end Append_Frac;`, `end Dig2;`, `end Image_Date_Time;`,
`end New_Timer;` terminators. Every contained line of these subprograms is
hit by Time_Suite (Duration.String/Arith, Date + accessors, UTC/Local
RFC3339, NewTimer + Stop are all green in the same run); lcov 2.4 leaves
hit-count 0 on the block terminator itself. Same misattribution class as
`gada-async-race.adb:80` documented above. The zone-conversion bodies of
UTC()/Local() (from a Local value) are covered by Test_UTC_Local_Format,
the public Stop_All wrapper by Test_Stop_All, the Repeater's atomic
Tick_Fire path by Test_Tick, and the one-shot Try_Fire claim by
Test_Timer_Stop — none excluded.

### `runtime/src/gada-std-os.adb` (Phase 6 wave 2)

62-68 — Read_File's `when Device_Error | End_Error | Data_Error` arm.
The directory case is rejected up front by the `Ada.Directories.Kind`
guard (covered by OS_Suite's Test_Read_File_Dir, which asserts the
"is a directory" error); a read failure on a regular file needs a
failing device, which no portable AUnit test can arrange. 70-71, 149,
168 — `end;`/`end Read_File;`/`end Open;`/`end Create;` block terminators
where lcov 2.4 leaves hit-count 0 despite every contained line being hit
(same misattribution class as gada-std-time.adb). 83-84 — the `Args` argv
loop body; the CI full-suite coverage run invokes test_runner with no
filter argument (Argument_Count = 0), so the loop body never executes
there (single-suite `make stdlib-test PKG=...` runs do pass one).
Open/Create/Stat/Mkdir happy and error paths are all covered by
OS_Suite, not excluded.

### `runtime/src/gada-std-runtime.adb` (Phase 6 wave 2)

31 — `end Go_Max_Procs;` terminator: lcov 2.4 leaves hit-count 0 on the
block terminator even though every contained line is hit by
Runtime_Suite (NumGoroutine/GOMAXPROCS/Gosched+GC all green in the same
run; the GOMAXPROCS resize arm is covered by the main-task resize
test). Same misattribution class as gada-std-time.adb.

### `runtime/src/gada-std-net.adb` (Phase 7 wave 3)

82 — `Parse_IPv4`'s `Part < 4 and then Dot = 0` arm. Unreachable:
the `Count (S, ".") = 3` guard at line 66 guarantees a dot remains
in the searched suffix for parts 1..3 (each iteration consumes exactly
one dot and advances Pos past it), so `Index` never returns 0 there.
92, 96, 141, 176, 230, 279, 280, 452, 453, 484, 820, 982, 1014 —
declare-block, loop, exception-handler, and subprogram terminators;
lcov 2.4 no-return-block misattribution class
documented above (every contained line is hit by Net_Suite's parse,
TCP, UDP, LookupHost, and error-path tests). 455-456 — `Resolve`'s
"resolved but no IPv4 address" fall-through (v6-only names): v1
sockets are IPv4-only and on Linux CI every resolvable name the suite
uses (localhost) has a v4 entry; the v6-literal early-out above it IS
covered by the `[::1]:80` dial error test, and the v4-found loop arm
by the `localhost:0` listen control. 478-481 — `To_IP`'s
`Family_Inet6` arm: v1 creates every socket with `Family_Inet`, so no
Inet6 `Sock_Addr_Type` is ever produced and this arm cannot execute
(the bracket-parse path in `Split_Address`, 395-400, IS covered by the
`[::1]:80` dial error test — only the post-socket conversion arm is
excluded). 507 — `Addr_Image`'s non-inet family guard, same defensive
class. 704, 814, 976 — the nested `when others => null` inside the
`Socket_Error` cleanup handlers of `Dial`/`Listen`/`Listen_Packet`:
reachable only if `Close_Socket` itself raises during error cleanup,
which needs fault injection; the handlers themselves (808-820,
970-982) are covered by the `192.0.2.1:0` unassigned-bind tests. All
other net lines — IP
parse/format tables, Split_Address, Resolve, Dial/Listen/Listen_Packet
happy + error paths, Conn/Listener/Packet_Conn ops incl. closed-socket
and EOF arms, Lookup_Host — are covered by Net_Suite, not excluded.

### `runtime/src/gada-std-json.adb` (Phase 7 wave 3, items 2a/2b)

145-146 — `Unescape`'s `Code > 16#FFFF#` reject: unreachable, four hex
digits cap Code at 0xFFFF (the surrogate-half reject at 140-142 IS
covered by the `\uD800` bad case). 392-393, 404-405 — `Parse_Scalar_At`'s
`Constraint_Error` arms on `Long_Float'Value`: a syntactically valid
JSON number always parses as a float64, so these cannot fire (the
int64-overflow → float-widening arm IS covered by the 20-digit test).
606-608 — `Marshal`'s NaN arm: Go's encoder rejects NaN, but Ada has no
portable non-finite `Long_Float` literal to test with. 153, 220, 228,
264, 310, 411, 638, 665, 689, 711 — lcov 2.4 no-return-block
misattribution on declare / end / subprogram-header lines (same class
as gada-std-net.adb). Everything else — Escape/Unescape tables incl.
2/3-byte UTF-8, Float_Image in both plain and scientific forms,
Parse_Scalar over all scalar tokens plus malformed inputs, Parse_Object
(member kinds, escaped keys, every malformed shape), Encode_Value over
registered descriptors, and all four Marshal/Unmarshal overloads incl.
null no-op and kind mismatch — is covered by Json_Suite, not excluded.

### `runtime/src/gada-std-bytes.adb` (Phase 7 wave 3 delta)

38, 132, 176 — `end To_String;` (Byte_Slice), `end loop;` in Join's
`Append_All`, `end To_String;` (Buffer): lcov 2.4 block-terminator
misattribution; the contained loop bodies are hit by Bytes_Suite and
Net_Suite. The Phase 5 exclusions for this file (28, 122, 166) were
superseded when the file was rewritten for Phase 7 and are replaced by
this entry.

### `runtime/src/gada-std-http.adb` (Phase 7 wave 3, items 3-4)

122, 181, 229, 323, 446, 558-559 — `end To_Lower;` / block `end;` /
`end Serve_One;` terminators; 126 — the `Read_Request` subprogram-header
line; 160, 210, 510 — `declare` markers: lcov 2.4 no-return-block
misattribution, same class as the
gada-std-time.adb / gada-std-json.adb entries (every contained line of
these blocks is hit by Http_Suite). 391-392 — the accept loop's
top-of-loop `Stopping` arm: only fires when Stop lands while the loop is
inside Serve_One; the suite always stops while the loop is blocked in
Accept_K, which takes the post-accept stop arm (covered). Racy, not
deterministically triggerable in CI. 147-148 and 245-247 — the
`N = 0`-without-error arms of the header and body read loops:
`Gada.Std.Net.Conn.Read` always sets `Err = EOF` on an orderly peer
shutdown, so `N = 0` implies `E /= No_Error`; the arms are defensive
and unreachable through the net layer. 166-167 — the `First_Lf = 0`
arm: unreachable because `Hd > 0` (a CRLFCRLF was found) already
guarantees a CRLF inside `Head`. 396-397 — the accept-error arm of
`Listen_And_Serve`: `Stop_Server` wakes a blocked accept with a
self-connect that succeeds, and genuine accept errors (EMFILE/ENFILE)
are not deterministically triggerable in CI. 495-497 — the client
write-error arm of `Do_Request`: it needs EPIPE/RST, and the tests only
close connections after the server has read the full request.
Everything else — mux register/lookup, Read_Request request line,
header loop incl. Content-Length (last-header-line arm), the body read
loop incl. its EOF arm (Http_Suite Test_Bad_Requests truncated-body
case and Test_Split_Body), Write_Response, Serve_One incl. its
exception handler (Test_Handler_Raises), the accept loop's stop paths,
Split_URL, Do_Request happy + parse-error paths, Client Get/Post — is
covered by Http_Suite, not excluded.

---

### `runtime/src/gada-std-hash-crc32.adb` / `gada-std-hash-crc64.adb` (Phase 8 wave 4, item 1)

25 in each — `end Make_Table;` terminators: lcov 2.4 leaves hit-count 0
on the block terminator because `Make_Table` returns via `return Tab;`
on its own line; every contained line (both polynomial-bit arms of the
table build) is hit by Std_Hash_Suite. Same misattribution class as the
gada-std-time.adb / gada-std-http.adb entries. Everything else in the
four hash ports — Make_Table, Update, Checksum(_IEEE), the FNV
constructors/Write (both FNV-1 and FNV-1a arms)/Sum/Sum32/Sum64/Reset/
Size, and Adler32 incl. the NMAX batching loop — is covered by
Std_Hash_Suite with Go-1.27-pinned vectors, not excluded.

---

### `runtime/src/gada-std-crypto-sha256.adb` / `-sha512.adb` / `-sha1.adb` / `-md5.adb` (Phase 8 wave 4, item 2)

66 / 98 / 49 / 72 respectively — the `end Transform;` terminators: lcov
2.4 leaves hit-count 0 on a procedure's block terminator when the
procedure has no return statement; every contained line (word load,
schedule, all round arms, the state adds) is hit by
Std_Crypto_Hash_Suite, which hashes inputs from 0 to 1000 bytes through
both the one-shot and split-Write paths for all four algorithms. Same
misattribution class as the `end Make_Table;` entries above. Everything
else in the four crypto ports — Transform, Append_Byte (incl. the
block-full arm), New_K, Write, Sum (incl. the padding while-loop and
the SHA-512 zero high length half), Reset, Size, Block_Size, and the
one-shot Sum256/Sum512/Sum — is covered, not excluded.

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
