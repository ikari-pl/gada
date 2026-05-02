--  Maps_Bench body — exercises Gada.Core.Maps lookup/insert/delete
--  hot paths on a Fibonacci-hashed Integer→Integer map.

with Interfaces;

with Gada_Bench;
with Gada.Core.Maps;

package body Maps_Bench is

   use Interfaces;

   function Hash_Fib (K : Integer) return Unsigned_64;
   function Hash_Fib (K : Integer) return Unsigned_64 is
   begin
      return Unsigned_64 (K) * 16#9E37_79B9_7F4A_7C15#;
   end Hash_Fib;

   package Int_Map is new Gada.Core.Maps
     (Key_Type      => Integer,
      Value_Type    => Integer,
      Hash          => Hash_Fib,
      "="           => "=",
      Default_Value => 0);

   --  Same volatile-sink pattern Slices_Bench uses — defeats the
   --  optimiser's closed-form inline of inlinable lookups.
   Sink_Slot : Unsigned_64 := 0
     with Volatile;

   procedure Bench_Insert_Pre_Sized
     (B : in out Gada_Bench.Benchmark_State);
   procedure Bench_Lookup_Hit
     (B : in out Gada_Bench.Benchmark_State);
   procedure Bench_Lookup_Miss
     (B : in out Gada_Bench.Benchmark_State);
   procedure Bench_Delete_Reinsert
     (B : in out Gada_Bench.Benchmark_State);

   ---------------------------------------------------------------
   --  Insert into a fresh, pre-sized map. One Insert per outer
   --  iteration. Cap_Hint = N keeps the grow path off the timed
   --  region.
   ---------------------------------------------------------------
   procedure Bench_Insert_Pre_Sized
     (B : in out Gada_Bench.Benchmark_State)
   is
      N : constant Positive := Gada_Bench.Iter_Count (B);
      M : Int_Map.Map := Int_Map.Make_Map (N + N / 4);
   begin
      Gada_Bench.Reset_Timer (B);
      for I in 1 .. N loop
         Int_Map.Insert (M, I, I);
      end loop;
      --  Use Length to make the optimiser keep the inserts.
      Sink_Slot := Unsigned_64 (Int_Map.Length (M));
   end Bench_Insert_Pre_Sized;

   ---------------------------------------------------------------
   --  Lookup hit. Pre-fill 4096 entries; lookup a different key
   --  on each iter; report the typical present-key path.
   ---------------------------------------------------------------
   procedure Bench_Lookup_Hit
     (B : in out Gada_Bench.Benchmark_State)
   is
      N : constant Positive := Gada_Bench.Iter_Count (B);
      M : Int_Map.Map := Int_Map.Make_Map (4096);
   begin
      for I in 1 .. 4096 loop
         Int_Map.Insert (M, I, I * 2);
      end loop;
      Gada_Bench.Reset_Timer (B);
      for I in 1 .. N loop
         Sink_Slot :=
           Sink_Slot xor Unsigned_64
             (Int_Map.Get (M, ((I - 1) mod 4096) + 1));
      end loop;
   end Bench_Lookup_Hit;

   ---------------------------------------------------------------
   --  Lookup miss. Probe terminates at the first empty control
   --  byte; should be cheap and similar to the hit path.
   ---------------------------------------------------------------
   procedure Bench_Lookup_Miss
     (B : in out Gada_Bench.Benchmark_State)
   is
      N : constant Positive := Gada_Bench.Iter_Count (B);
      M : Int_Map.Map := Int_Map.Make_Map (4096);
   begin
      for I in 1 .. 4096 loop
         Int_Map.Insert (M, I, I * 2);
      end loop;
      Gada_Bench.Reset_Timer (B);
      for I in 1 .. N loop
         --  Keys 100_000+ are guaranteed absent.
         Sink_Slot :=
           Sink_Slot xor Unsigned_64
             (Int_Map.Get (M, 100_000 + ((I - 1) mod 4096)));
      end loop;
   end Bench_Lookup_Miss;

   ---------------------------------------------------------------
   --  Delete + reinsert cycle (tombstone path).
   ---------------------------------------------------------------
   procedure Bench_Delete_Reinsert
     (B : in out Gada_Bench.Benchmark_State)
   is
      N : constant Positive := Gada_Bench.Iter_Count (B);
      M : Int_Map.Map := Int_Map.Make_Map (256);
   begin
      for I in 1 .. 200 loop
         Int_Map.Insert (M, I, I);
      end loop;
      Gada_Bench.Reset_Timer (B);
      for I in 1 .. N loop
         declare
            K : constant Integer := ((I - 1) mod 200) + 1;
         begin
            Int_Map.Delete (M, K);
            Int_Map.Insert (M, K, I);
         end;
      end loop;
      Sink_Slot := Unsigned_64 (Int_Map.Length (M));
   end Bench_Delete_Reinsert;

   procedure Register_All is
   begin
      Gada_Bench.Register
        ("Maps_Insert_Pre_Sized", Bench_Insert_Pre_Sized'Access);
      Gada_Bench.Register
        ("Maps_Lookup_Hit",       Bench_Lookup_Hit'Access);
      Gada_Bench.Register
        ("Maps_Lookup_Miss",      Bench_Lookup_Miss'Access);
      Gada_Bench.Register
        ("Maps_Delete_Reinsert",  Bench_Delete_Reinsert'Access);
   end Register_All;

end Maps_Bench;
