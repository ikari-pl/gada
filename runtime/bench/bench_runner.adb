--  Bench_Runner — entry point of the GADA bench harness.
--
--  Each per-package bench file calls Gada_Bench.Register from its
--  Register_All procedure; this main calls each suite's
--  Register_All in turn, then dispatches to Gada_Bench.Run_All.
--  Output: one benchstat-compatible line per benchmark on stdout.

pragma Warnings (Off, "use of an anonymous access type allocator");

with Gada_Bench;

with Memory_Bench;
with Slices_Bench;
with Maps_Bench;

procedure Bench_Runner is
begin
   Memory_Bench.Register_All;
   Slices_Bench.Register_All;
   Maps_Bench.Register_All;
   Gada_Bench.Run_All;
end Bench_Runner;
