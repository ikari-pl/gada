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

#### `Make` — libco OOM path  *(lines 139–140)*

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

#### `Trampoline` — tail-loop terminator  *(line 111)*

```ada
loop
   Libco.Co_Switch (Exits.Element (Self));
end loop;     --  line 111
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
