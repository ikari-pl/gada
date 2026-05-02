--  Slices_Bench — Gada.Core.Slices micro-benchmarks.
--
--  Coverage:
--    - In-place Append (Cap available)
--    - Grow Append (Cap exhausted, doubling phase)
--    - Set_Element + Element round-trip (address-overlay cost)
--    - Slice_Of (header copy, no allocation)
--
--  Each row pasted into runtime/PERF.md.
--
--  Per docs/adr/0006-runtime-performance-bar.md: 2x of Go reference
--  on the same workload shape.

package Slices_Bench is
   procedure Register_All;
end Slices_Bench;
