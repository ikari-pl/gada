--  Scheduler_Bench — Gada.Async.Scheduler micro-benchmarks.
--
--  Phase 3 baseline rows for runtime/PERF.md. Captures the per-op
--  cost of Spawn (single-worker and multi-worker), the libco round-
--  trip cost via a yield-heavy ping-pong, and the multi-worker
--  speedup ratio. Sub-item 3c will measure the deque change against
--  these numbers.

package Scheduler_Bench is

   procedure Register_All;

end Scheduler_Bench;
