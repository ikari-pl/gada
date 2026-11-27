--  Body of Gada.Std.Runtime — see spec for the Go-semantics contract.

with Gada.Async.Scheduler;
with Gada.Core.Memory;

package body Gada.Std.Runtime is

   package Scheduler renames Gada.Async.Scheduler;

   use type Scheduler.Goroutine_Id;

   function Num_Goroutine return Natural is
   begin
      --  + 1 for the main task (Go counts the main goroutine).
      return Scheduler.Live_Goroutines + 1;
   end Num_Goroutine;

   function GOMAXPROCS (Set_To : Natural := 0) return Natural is
      Old : constant Natural := Scheduler.Live_Workers;
   begin
      if Set_To > 0 and then Set_To /= Old
        and then Scheduler.Current = Scheduler.No_Goroutine
      then
         --  Only from the main task / a non-goroutine context:
         --  Shutdown joins all in-flight goroutines, so doing this
         --  from inside a goroutine would self-deadlock.
         Scheduler.Shutdown;
         Scheduler.Init (Set_To);
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
