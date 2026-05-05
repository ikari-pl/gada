with Gada.Async.Scheduler;

procedure Main is

   procedure Worker is
   begin
      null;
   end Worker;
   procedure Go_Closure_1 is
   begin
      Worker;
   end Go_Closure_1;
   Unused_G : Gada.Async.Scheduler.Goroutine_Id;

begin
   Gada.Async.Scheduler.Init;
   Unused_G := Gada.Async.Scheduler.Spawn (Go_Closure_1'Unrestricted_Access);
   Gada.Async.Scheduler.Shutdown;
end Main;
