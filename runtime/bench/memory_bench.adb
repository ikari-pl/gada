with System;

with Gada.Core.Memory;

package body Memory_Bench is

   procedure Bench_Allocate_64
     (B : in out Gada_Bench.Benchmark_State)
   is
      Addr : System.Address;
      pragma Unreferenced (Addr);
   begin
      for I in 1 .. Gada_Bench.Iter_Count (B) loop
         Addr := Gada.Core.Memory.Allocate (64);
      end loop;
   end Bench_Allocate_64;

   procedure Bench_Allocate_Atomic_64
     (B : in out Gada_Bench.Benchmark_State)
   is
      Addr : System.Address;
      pragma Unreferenced (Addr);
   begin
      for I in 1 .. Gada_Bench.Iter_Count (B) loop
         Addr := Gada.Core.Memory.Allocate_Atomic (64);
      end loop;
   end Bench_Allocate_Atomic_64;

   procedure Bench_Allocate_Atomic_4K
     (B : in out Gada_Bench.Benchmark_State)
   is
      Addr : System.Address;
      pragma Unreferenced (Addr);
   begin
      for I in 1 .. Gada_Bench.Iter_Count (B) loop
         Addr := Gada.Core.Memory.Allocate_Atomic (4096);
      end loop;
   end Bench_Allocate_Atomic_4K;

   procedure Register_All is
   begin
      Gada_Bench.Register
        ("Memory_Allocate_64", Bench_Allocate_64'Access);
      Gada_Bench.Register
        ("Memory_Allocate_Atomic_64", Bench_Allocate_Atomic_64'Access);
      Gada_Bench.Register
        ("Memory_Allocate_Atomic_4K", Bench_Allocate_Atomic_4K'Access);
   end Register_All;

end Memory_Bench;
