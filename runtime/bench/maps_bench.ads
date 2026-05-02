--  Maps_Bench — Gada.Core.Maps Swiss-table micro-benchmarks.
--
--  Coverage:
--    - Insert into a pre-sized map (no grow / rehash on path).
--    - Lookup hit (key present).
--    - Lookup miss (key absent — exercises the empty-control-byte
--      probe-termination path).
--    - Delete + reinsert cycle (tombstone reuse).

package Maps_Bench is
   procedure Register_All;
end Maps_Bench;
