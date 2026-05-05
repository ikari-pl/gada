with Gada.Async.Scheduler;

package body P is

   procedure F is
      procedure Go_Closure_1 is
      begin
         Worker;
      end Go_Closure_1;
      Unused_G : Gada.Async.Scheduler.Goroutine_Id;
   begin
      Unused_G := Gada.Async.Scheduler.Spawn (Go_Closure_1'Unrestricted_Access);
   end F;

end P;
