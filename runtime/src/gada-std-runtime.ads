--  Gada.Std.Runtime — the Go `runtime` package, ported (Phase 6
--  wave 2). Introspection + control over the GADA scheduler, mapped
--  onto Gada.Async.Scheduler and Gada.Core.Memory.

package Gada.Std.Runtime is

   --  Go runtime.NumGoroutine: live goroutines, counting the main
   --  task as one (Go counts the main goroutine too).
   function Num_Goroutine return Natural;

   --  Go runtime.GOMAXPROCS(n): returns the previous setting (the
   --  live worker count, or the count the next Init would start when
   --  the scheduler is not running); n = 0 only queries. n > 0 resizes
   --  the pool immediately when no goroutine is live; otherwise (v1
   --  limitation — resizing means Shutdown, which would join live
   --  goroutines and deadlock if they wait on the caller) the value is
   --  recorded and takes effect at the next Scheduler.Init. Before
   --  Init it is likewise recorded, so a generated main's Init picks
   --  it up. Never blocks.
   function GOMAXPROCS (Set_To : Natural := 0) return Natural;

   --  Go runtime.Gosched: cooperative yield (no-op outside a
   --  goroutine, per Scheduler.Yield).
   procedure Gosched;

   --  Go runtime.GC: force a full Boehm collection cycle.
   procedure GC;

end Gada.Std.Runtime;
