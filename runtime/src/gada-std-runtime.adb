--  Body of Gada.Std.Runtime — see spec for the Go-semantics contract.

with Gada.Async.Scheduler;
with Gada.Core.Memory;

package body Gada.Std.Runtime is

   package Scheduler renames Gada.Async.Scheduler;

   function Num_Goroutine return Natural is
   begin
      --  + 1 for the main task (Go counts the main goroutine).
      return Scheduler.Live_Goroutines + 1;
   end Num_Goroutine;

   function GOMAXPROCS (Set_To : Natural := 0) return Natural is
      Old : constant Natural :=
        (if Scheduler.Is_Running then Scheduler.Live_Workers
         else Scheduler.Default_Workers);
   begin
      if Set_To > 0 and then Set_To /= Old then
         if Scheduler.Is_Running and then Scheduler.Live_Goroutines = 0
         then
            --  Nothing in flight: Shutdown returns at once (it joins
            --  goroutines, none exist), so the pool resizes in place.
            --  Live_Goroutines = 0 also rules out a goroutine caller.
            Scheduler.Shutdown;
            Scheduler.Init (Set_To);
         else
            --  v1 limitation: a live pool cannot be resized without
            --  joining its goroutines (which may be waiting on this
            --  caller), so the request is recorded for the next Init.
            Scheduler.Set_Default_Workers (Set_To);
         end if;
      end if;
      return Old;
   end GOMAXPROCS;

   procedure Gosched is
   begin
      Scheduler.Yield;
   end Gosched;

   procedure GC is
   begin
      Gada.Core.Memory.Collect;
   end GC;

end Gada.Std.Runtime;
