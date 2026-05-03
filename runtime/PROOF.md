# GADA runtime SPARK proof ledger

Per-package SPARK posture and last gnatprove result. Per
[`docs/adr/0008-spark-policy.md`](../docs/adr/0008-spark-policy.md):

- **Policy:** SPARK is opt-in per package, not whole-runtime. The
  opt-in set is the algorithmic core (hash, slices, maps); the
  permanent opt-out set is everything that touches the OS, C, or
  finalisation (Async, Defer, IO).
- **Verification gate:** `tools/prove.sh` discharges every VC on
  every opt-in unit. CI does not run it (Phase 3-era latency
  budget); a `make prove` target lands once the opt-in set is large
  enough that proof drift is a real regression risk.

Methodology: `tools/prove.sh` invokes `gnatprove --mode=all
--level=2 --report=fail -j0 -P gada_core.gpr -u <unit>`. Numbers
shown are from a representative run on the dev host (darwin/arm64,
gnatprove 15.1.0 from the Alire `gnatprove` crate). The "VCs"
column counts verification conditions emitted; "Unproven" must be
`0` for every row, no exceptions.

## Opt-in packages

| Package | SPARK_Mode | Body | VCs | Unproven | Last proven | Notes |
|---|---|---|---:|---:|---|---|
| `Gada.Core.Hash` | `On` (spec) | `On` | 6 | 0 | 2026-05-02 | Pure modular arithmetic over `Interfaces.Unsigned_64`. 3 run-time checks + 3 termination, all discharged trivially (max 1 prover step). The `Hash_Long_Float` body uses `Ada.Unchecked_Conversion` between same-sized 64-bit scalars; SPARK accepts this because `Unsigned_64` has no invalid bit patterns. **First-prove caught a real bug**: `Unsigned_64 (K)` raised Constraint_Error for negative `K` (RM 4.6 modular conversion does not apply to value-conversions from signed integers in GNAT); fixed by `Unsigned_64'Mod (K)`. |

VCs and Unproven columns are populated by `tools/prove.sh` on each
run; the values shown are from the most recent green run on the
dev host.

## Opt-out packages (permanent)

| Package | Why off | Reviewer note |
|---|---|---|
| `Gada.Core.IO` | Wraps `Ada.Text_IO` (side-effecting I/O perimeter). | No proof value; the proof obligation is on the user code that calls Println, not on the wrapper. |
| `Gada.Core.Defer` | `Limited_Controlled` finalisation chains. | SPARK subset profiles exclude controlled types. Defer's correctness is regression-tested via `defer_suite`, not proven. |
| `Gada.Async.Context` | Raw `System.Address`, `Convention => C` trampoline, `access procedure` dispatch, libco binding. | Forbidden constructs across the board. The public spec is intentionally narrow so future binding wrappers can opt in even if the body cannot. |
| `Gada.Async.Context.Libco` | C bindings (libco). | `Convention => C` subprograms are excluded from SPARK by definition. |
| `Gada.Async.Scheduler` (Phase 3) | Tasking outside Ravenscar profile (TBD by scheduler design). | If the scheduler design picks Ravenscar, this row may be revisited under a follow-up ADR. |

## Opt-in candidates (deferred)

| Package | Why deferred | Owner / blocker |
|---|---|---|
| `Gada.Core.Slices` | Public API still in flux around `Append`/`Set_Element` capacity invariants. | Convert when API is stable across one full Phase. |
| `Gada.Core.Maps` | Open-addressing probe loop is a strong SPARK target (loop variant + bucket bound), but contracts depend on `Gada.Core.Hash` already proven. | This PR (Hash) unblocks the eventual Maps PR. |

## How to add a package to the opt-in set

1. Mark the spec with `with SPARK_Mode => On;` (and any necessary
   contracts).
2. Mark the body with `pragma SPARK_Mode (On);` at the top.
3. Add the unit name (lowercased, hyphenated, no extension) to
   `OPT_IN_UNITS` in `tools/prove.sh`.
4. Add a row to the **Opt-in packages** table above with the proof
   numbers from a fresh run.
5. Cross-link from ADR-0008's "first inclusions" list if the package
   is broadly load-bearing.

If the package cannot reach 0 unproven VCs without `pragma
Annotate (GNATprove, ...)` justifications, add a sub-section
explaining each justification — undocumented justifications are
rejected at PR review.

## Mixed posture: spec-level contracts when the body must stay Off

Some packages cannot be fully `SPARK_Mode => On` (the body touches C
bindings, raw addresses, finalisation, or non-Ravenscar tasking) but
*can* express SPARK-checkable invariants at the **spec** level. The
canonical examples come from
[[../docs/journal/2026-05-03-async-context-concurrency.md]] hazards
#3 (lifecycle state machine) and #5 (`Yield` outside goroutine
context). For these, the recipe is:

- Mark the spec `with SPARK_Mode => On` and add `Pre`/`Post`
  contracts on the public subprograms.
- Mark the body `with SPARK_Mode => Off` so gnatprove only checks
  caller-side preconditions, not the body's implementation.
- Add the unit name to `OPT_IN_UNITS` in `tools/prove.sh` exactly
  as for full opt-ins; gnatprove correctly handles the spec-only
  case.

The proof obligation transfers to *callers*: every call site must
prove it satisfies the precondition. That alone catches the "future
generated-code emit accidentally calls `Yield` outside a goroutine"
class of hazard at compile time.

### Recipe 1: lifecycle state machine (hazard #3)

Use a `Ghost` enum to model the lifecycle externally; mark
state-changing subprograms with the legal transitions.

```ada
--  gada-async-scheduler.ads
package Gada.Async.Scheduler with SPARK_Mode => On is

   --  Ghost type — exists only for proof, never at runtime.
   type Lifecycle_State is (Fresh, Running, Draining, Stopped)
     with Ghost;

   function Current_Lifecycle return Lifecycle_State with Ghost;

   procedure Init
     with Pre  => Current_Lifecycle = Fresh
                  or else Current_Lifecycle = Stopped,
          Post => Current_Lifecycle = Running;

   procedure Shutdown
     with Pre  => Current_Lifecycle = Running
                  or else Current_Lifecycle = Draining,
          Post => Current_Lifecycle = Stopped;

   --  ... other operations carry Pre => Current_Lifecycle = Running
   --  to forbid Spawn-after-Shutdown without an Init in between.

end Gada.Async.Scheduler;
```

```ada
--  gada-async-scheduler.adb
package body Gada.Async.Scheduler with SPARK_Mode => Off is
   --  ... regular Ada implementation, free to use libco, Ada tasks,
   --  raw addresses, finalisation, etc. The spec contracts above
   --  bind callers; the body's correctness is regression-tested via
   --  AUnit, not proven.
end Gada.Async.Scheduler;
```

The body aspect (`with SPARK_Mode => Off`) is **load-bearing**. A
spec marked `On` does **not** automatically force the body to `Off`
— in fact, a body with no annotation **inherits On** from the spec
and gnatprove will then attempt to verify the (unprovable) libco
calls inside it. `pragma SPARK_Mode (Off)` in the spec's `private`
part affects only private declarations of the spec; it does **not**
cascade to the body. The body file's own `with SPARK_Mode => Off`
aspect is the only mechanism that opts the body out.

What this catches: re-entrant `Init` after a half-Shutdown, `Spawn`
after `Shutdown`, double `Init` without intervening `Shutdown`. All
the shapes of hazard #3, by construction, at compile time. The
sticky `Shutting_Down` flag bug in the retro becomes impossible to
write because the precondition forbids the transition.

### Recipe 2: context-restricted operations (hazard #5)

Use a `Ghost` boolean function to track "are we in a goroutine
context"; require it as a precondition on operations that demand
it.

```ada
--  gada-async-scheduler.ads (extends Recipe 1's spec)
package Gada.Async.Scheduler with SPARK_Mode => On is

   function In_Goroutine_Context return Boolean with Ghost;

   procedure Yield
     with Pre => In_Goroutine_Context;

   --  ... other goroutine-only operations get the same Pre.
end Gada.Async.Scheduler;
```

The corresponding body file (`gada-async-scheduler.adb`) opens with
`package body Gada.Async.Scheduler with SPARK_Mode => Off is` for
the same reason as in Recipe 1.

What this catches: any future code path that calls `Yield` from
elaboration-time, from a non-goroutine task, or from the main
thread, fails to verify until the caller proves `In_Goroutine_Context`.
The "Yield is currently a no-op outside a goroutine" trap becomes a
compile-time error rather than silent dead code.

### Why "Mixed" is not just "Off"

A spec marked `SPARK_Mode => On` with body `Off` is **not** the
same as a fully-Off package: gnatprove still verifies that **callers
satisfy preconditions**. That is most of the value for packages whose
body legitimately can't be SPARK (libco bindings, controlled types,
non-Ravenscar tasking) but whose contract surface is the actual
hazard locus. The body's correctness is regression-tested via AUnit;
the call-site discipline is proven.

The trade-off: contracts on the spec must be **provable from the
caller's perspective alone**. They cannot reference the body's
internal state directly. `Ghost` functions and `Ghost` types are the
escape hatch — they can be redefined privately in the body to
return a useful value at proof time without leaking implementation
details.

### When a Mixed posture is *not* worth it

- The package has no public subprograms (utility-only with
  `private` API) — no caller surface to gate.
- The hazard is purely internal (race between two private
  threads of the same package) — Ravenscar is the only tool.
  See [[../docs/adr/0009-ravenscar-conditional-spark.md]].
- The contract would need to reference body state that has no
  meaningful Ghost shadow (e.g., a libgc-managed pointer table).
