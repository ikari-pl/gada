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
