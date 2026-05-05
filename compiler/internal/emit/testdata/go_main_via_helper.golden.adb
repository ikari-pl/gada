with Gada.Async.Scheduler;

procedure Main is

   procedure Worker is
   begin
      null;
   end Worker;

   procedure Helper is
      procedure Go_Closure_1 is
      begin
         Worker;
      end Go_Closure_1;
      Unused_G : Gada.Async.Scheduler.Goroutine_Id;
   begin
      Unused_G := Gada.Async.Scheduler.Spawn (Go_Closure_1'Unrestricted_Access);
   end Helper;

begin
   Gada.Async.Scheduler.Init;
   Helper;
   Gada.Async.Scheduler.Shutdown;
end Main;
