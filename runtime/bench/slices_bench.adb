--  Slices_Bench body — Gada.Core.Slices micro-benchmarks.
--
--  Each Bench_* procedure follows the testing.B-style contract:
--  loop B.Iter_Count times calling the unit under test, with any
--  one-time setup billed *before* a Reset_Timer call so the harness
--  measures only the steady-state per-op cost.

with Interfaces;

with Gada_Bench;
with Gada.Core.Slices;

package body Slices_Bench is

   --  Atomic instantiation — Integer is pointer-free, libgc-atomic.
   package Int_Slices is new Gada.Core.Slices
     (Element_Type      => Integer,
      Element_Is_Atomic => True);

   --  Volatile sink. The optimiser cannot prove a Volatile store
   --  has no observable effect, so it has to emit the inner-loop
   --  read+write+xor sequence verbatim. Without this, the Element
   --  and Slice_Of benches inline to a closed-form arithmetic
   --  expression and report < 1 ns/op (which truncates to 0).
   Sink_Slot : Interfaces.Unsigned_64 := 0
     with Volatile;

   procedure Bench_Append_In_Place
     (B : in out Gada_Bench.Benchmark_State);
   procedure Bench_Append_Grow
     (B : in out Gada_Bench.Benchmark_State);
   procedure Bench_Element_Roundtrip
     (B : in out Gada_Bench.Benchmark_State);
   procedure Bench_Slice_Of
     (B : in out Gada_Bench.Benchmark_State);

   ---------------------------------------------------------------
   --  In-place Append: pre-allocate Cap = Iters, reset timer,
   --  measure pure write cost.
   ---------------------------------------------------------------
   procedure Bench_Append_In_Place
     (B : in out Gada_Bench.Benchmark_State)
   is
      N : constant Positive := Gada_Bench.Iter_Count (B);
      S : Int_Slices.Slice :=
        Int_Slices.Make_Slice (Length => 0, Capacity => N);
   begin
      Gada_Bench.Reset_Timer (B);
      for I in 1 .. N loop
         S := Int_Slices.Append (S, I);
      end loop;
   end Bench_Append_In_Place;

   ---------------------------------------------------------------
   --  Grow Append: cycle of "start from Empty, append Cycle_Size
   --  times, drop". Each outer iter forces one full growth schedule
   --  through the doubling phase (Cycle_Size = 128 → 7 grows + writes
   --  inside the spare capacity left by the last doubling). This
   --  keeps the backing under ~1 KB per cycle, so libgc never has
   --  to scan a multi-megabyte arena, and the dropped slice goes
   --  through the same allocation lifecycle real Go programs see.
   ---------------------------------------------------------------
   Cycle_Size : constant := 128;

   procedure Bench_Append_Grow
     (B : in out Gada_Bench.Benchmark_State)
   is
      N : constant Positive := Gada_Bench.Iter_Count (B);
   begin
      Gada_Bench.Reset_Timer (B);
      for I in 1 .. N loop
         declare
            S : Int_Slices.Slice := Int_Slices.Empty;
         begin
            for J in 1 .. Cycle_Size loop
               S := Int_Slices.Append (S, J);
            end loop;
         end;
      end loop;
   end Bench_Append_Grow;

   ---------------------------------------------------------------
   --  Element round-trip: address-overlay read + write per op.
   ---------------------------------------------------------------
   procedure Bench_Element_Roundtrip
     (B : in out Gada_Bench.Benchmark_State)
   is
      use Interfaces;
      N    : constant Positive := Gada_Bench.Iter_Count (B);
      S    : constant Int_Slices.Slice := Int_Slices.Make_Slice (1024);
      Sink : Unsigned_64 := 0;
   begin
      Gada_Bench.Reset_Timer (B);
      for I in 1 .. N loop
         declare
            --  Index modulo 1024, kept 1-based for Ada.
            Idx : constant Positive := ((I - 1) mod 1024) + 1;
         begin
            Int_Slices.Set_Element (S, Idx, I);
            --  XOR into a 64-bit sink — never overflows. Volatile
            --  store on every iteration prevents the optimiser
            --  from collapsing the loop into a closed form.
            Sink := Sink xor Unsigned_64 (Int_Slices.Element (S, Idx));
            Sink_Slot := Sink;
         end;
      end loop;
   end Bench_Element_Roundtrip;

   ---------------------------------------------------------------
   --  Slice_Of: pure header arithmetic (3 field assignments + 1
   --  address add). No allocation. Should hit a few cycles per op.
   ---------------------------------------------------------------
   procedure Bench_Slice_Of
     (B : in out Gada_Bench.Benchmark_State)
   is
      use Interfaces;
      N    : constant Positive := Gada_Bench.Iter_Count (B);
      S    : constant Int_Slices.Slice := Int_Slices.Make_Slice (1024);
      Sink : Unsigned_64 := 0;
   begin
      Gada_Bench.Reset_Timer (B);
      for I in 1 .. N loop
         declare
            V : constant Int_Slices.Slice :=
              Int_Slices.Slice_Of
                (S,
                 Low  => 1 + ((I - 1) mod 512),
                 High => 1 + ((I - 1) mod 512) + 256);
         begin
            Sink := Sink + Unsigned_64 (Int_Slices.Len (V));
            Sink_Slot := Sink;
         end;
      end loop;
   end Bench_Slice_Of;

   ---------------------------------------------------------------
   --  Registration — wired into bench_runner.adb sequence.
   ---------------------------------------------------------------
   procedure Register_All is
   begin
      Gada_Bench.Register
        ("Slices_Append_In_Place", Bench_Append_In_Place'Access);
      Gada_Bench.Register
        ("Slices_Append_Grow", Bench_Append_Grow'Access);
      Gada_Bench.Register
        ("Slices_Element_Roundtrip", Bench_Element_Roundtrip'Access);
      Gada_Bench.Register
        ("Slices_Slice_Of", Bench_Slice_Of'Access);
   end Register_All;

end Slices_Bench;
