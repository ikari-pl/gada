--  Gada.Std.Runtime — the Go `runtime` package, ported (Phase 6
--  wave 2). Introspection + control over the GADA scheduler, mapped
--  onto Gada.Async.Scheduler and Gada.Core.Memory.

package Gada.Std.Runtime is

   --  Go runtime.NumGoroutine: live goroutines, counting the main
   --  task as one (Go counts the main goroutine too).
   function Num_Goroutine return Natural;

   --  Go runtime.GOMAXPROCS(n): n = 0 queries the live worker count;
   --  n > 0 requests a resize and returns the previous count. v1
   --  applies the resize immediately only from a non-goroutine
   --  context (Shutdown would join every in-flight goroutine, which
   --  deadlocks when called from inside one); from inside a
   --  goroutine the call is a query and the old value is returned.
   function Go_Max_Procs (Set_To : Natural := 0) return Natural;

   --  Go runtime.Gosched: cooperative yield (no-op outside a
   --  goroutine, per Scheduler.Yield).
   procedure Go_Sched;

   --  Go runtime.GC: force a full Boehm collection cycle.
   procedure GC;

end Gada.Std.Runtime;
