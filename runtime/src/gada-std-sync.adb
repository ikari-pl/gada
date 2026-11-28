--  Body of Gada.Std.Sync — see spec for the Go-semantics contract.

package body Gada.Std.Sync is

   use type Scheduler.Goroutine_Id;

   --  Unpark every goroutine in W (outside any protected action).
   procedure Wake_All (W : Waiter_Lists.List) is
   begin
      for G of W loop
         Scheduler.Unpark (G);
      end loop;
   end Wake_All;

   ---------------------------------------------------------------
   --  Mutex
   ---------------------------------------------------------------

   protected body Mutex_Core is

      entry Lock_Blocking when not Locked is
      begin
         Locked := True;
      end Lock_Blocking;

      procedure Lock_Or_Enqueue (G : Scheduler.Goroutine_Id;
                                 Got : out Boolean) is
      begin
         Got := not Locked;
         if Got then
            Locked := True;
         else
            Waiters.Append (G);
         end if;
      end Lock_Or_Enqueue;

      procedure Unlock (Wake : out Scheduler.Goroutine_Id) is
      begin
         --  Go: Unlock of an unlocked mutex is a fatal error (panic).
         if not Locked then
            raise Constraint_Error with "sync: unlock of unlocked mutex";
         end if;
         Locked := False;
         Wake := Scheduler.No_Goroutine;
         if not Waiters.Is_Empty then
            Wake := Waiters.First_Element;
            Waiters.Delete_First;
         end if;
      end Unlock;

      procedure Try_Lock (Ok : out Boolean) is
      begin
         Ok := not Locked;
         if Ok then
            Locked := True;
         end if;
      end Try_Lock;

      function Is_Locked return Boolean is (Locked);

   end Mutex_Core;

   procedure Lock (M : in out Mutex) is
      Me  : constant Scheduler.Goroutine_Id := Scheduler.Current;
      Got : Boolean;
   begin
      if Me = Scheduler.No_Goroutine then
         M.Core.Lock_Blocking;
         return;
      end if;
      loop
         M.Core.Lock_Or_Enqueue (Me, Got);
         exit when Got;
         Scheduler.Park;  --  an Unlock Unparks us; re-check
      end loop;
   end Lock;

   procedure Unlock (M : in out Mutex) is
      Wake : Scheduler.Goroutine_Id;
   begin
      M.Core.Unlock (Wake);
      Scheduler.Unpark (Wake);  --  no-op for No_Goroutine
   end Unlock;

   function Try_Lock (M : in out Mutex) return Boolean is
      Ok : Boolean;
   begin
      M.Core.Try_Lock (Ok);
      return Ok;
   end Try_Lock;

   function Is_Locked (M : Mutex) return Boolean is (M.Core.Is_Locked);

   ---------------------------------------------------------------
   --  RWMutex
   ---------------------------------------------------------------

   protected body RW_Core is

      entry Lock_Blocking when not Writer and then Readers = 0 is
      begin
         Writer := True;
      end Lock_Blocking;

      entry R_Lock_Blocking when not Writer is
      begin
         Readers := Readers + 1;
      end R_Lock_Blocking;

      procedure Lock_Or_Enqueue (G : Scheduler.Goroutine_Id;
                                 Got : out Boolean) is
      begin
         Try_Lock (Got);
         if not Got then
            Waiters.Append (G);
         end if;
      end Lock_Or_Enqueue;

      procedure R_Lock_Or_Enqueue (G : Scheduler.Goroutine_Id;
                                   Got : out Boolean) is
      begin
         Try_R_Lock (Got);
         if not Got then
            Waiters.Append (G);
         end if;
      end R_Lock_Or_Enqueue;

      procedure Unlock (Wake : out Waiter_Lists.List) is
      begin
         --  Go: Unlock with no write lock held panics.
         if not Writer then
            raise Constraint_Error
              with "sync: unlock of unlocked RWMutex";
         end if;
         Writer := False;
         Wake.Move (Source => Waiters);
      end Unlock;

      procedure R_Unlock (Wake : out Waiter_Lists.List) is
      begin
         --  Go: RUnlock with no read lock held panics.
         if Readers = 0 then
            raise Constraint_Error
              with "sync: RUnlock of unlocked RWMutex";
         end if;
         Readers := Readers - 1;
         Wake.Clear;
         if Readers = 0 then
            --  Only a writer can be waiting on readers.
            Wake.Move (Source => Waiters);
         end if;
      end R_Unlock;

      procedure Try_Lock (Ok : out Boolean) is
      begin
         Ok := not Writer and then Readers = 0;
         if Ok then
            Writer := True;
         end if;
      end Try_Lock;

      procedure Try_R_Lock (Ok : out Boolean) is
      begin
         Ok := not Writer;
         if Ok then
            Readers := Readers + 1;
         end if;
      end Try_R_Lock;

   end RW_Core;

   procedure Lock (M : in out RW_Mutex) is
      Me  : constant Scheduler.Goroutine_Id := Scheduler.Current;
      Got : Boolean;
   begin
      if Me = Scheduler.No_Goroutine then
         M.Core.Lock_Blocking;
         return;
      end if;
      loop
         M.Core.Lock_Or_Enqueue (Me, Got);
         exit when Got;
         Scheduler.Park;
      end loop;
   end Lock;

   procedure R_Lock (M : in out RW_Mutex) is
      Me  : constant Scheduler.Goroutine_Id := Scheduler.Current;
      Got : Boolean;
   begin
      if Me = Scheduler.No_Goroutine then
         M.Core.R_Lock_Blocking;
         return;
      end if;
      loop
         M.Core.R_Lock_Or_Enqueue (Me, Got);
         exit when Got;
         Scheduler.Park;
      end loop;
   end R_Lock;

   procedure Unlock (M : in out RW_Mutex) is
      Wake : Waiter_Lists.List;
   begin
      M.Core.Unlock (Wake);
      Wake_All (Wake);
   end Unlock;

   procedure R_Unlock (M : in out RW_Mutex) is
      Wake : Waiter_Lists.List;
   begin
      M.Core.R_Unlock (Wake);
      Wake_All (Wake);
   end R_Unlock;

   function Try_Lock (M : in out RW_Mutex) return Boolean is
      Ok : Boolean;
   begin
      M.Core.Try_Lock (Ok);
      return Ok;
   end Try_Lock;

   function Try_R_Lock (M : in out RW_Mutex) return Boolean is
      Ok : Boolean;
   begin
      M.Core.Try_R_Lock (Ok);
      return Ok;
   end Try_R_Lock;

   ---------------------------------------------------------------
   --  WaitGroup
   ---------------------------------------------------------------

   protected body WG_Core is

      procedure Add (Amount : Integer; Wake : out Waiter_Lists.List) is
      begin
         --  Go: Add with a negative delta that would drive the counter
         --  below zero panics ("sync: negative WaitGroup counter").
         if Integer (N) + Amount < 0 then
            raise Constraint_Error
              with "sync: negative WaitGroup counter";
         end if;
         N := N + Amount;
         Wake.Clear;
         if N = 0 then
            Wake.Move (Source => Waiters);
         end if;
      end Add;

      entry Wait_Blocking when N = 0 is
      begin
         null;  --  the barrier did the work
      end Wait_Blocking;

      procedure Wait_Or_Enqueue (G : Scheduler.Goroutine_Id;
                                 Zero : out Boolean) is
      begin
         Zero := N = 0;
         if not Zero then
            Waiters.Append (G);
         end if;
      end Wait_Or_Enqueue;

      function Value return Natural is (N);

   end WG_Core;

   procedure Add (W : in out Wait_Group; Amount : Integer) is
      Wake : Waiter_Lists.List;
   begin
      W.Core.Add (Amount, Wake);
      Wake_All (Wake);
   end Add;

   procedure Done (W : in out Wait_Group) is
   begin
      Add (W, -1);
   end Done;

   procedure Wait (W : in out Wait_Group) is
      Me   : constant Scheduler.Goroutine_Id := Scheduler.Current;
      Zero : Boolean;
   begin
      if Me = Scheduler.No_Goroutine then
         W.Core.Wait_Blocking;
         return;
      end if;
      loop
         W.Core.Wait_Or_Enqueue (Me, Zero);
         exit when Zero;
         Scheduler.Park;
      end loop;
   end Wait;

   function Value (W : Wait_Group) return Natural is (W.Core.Value);

   ---------------------------------------------------------------
   --  Once
   ---------------------------------------------------------------

   protected body Once_Core is

      procedure Claim (G : Scheduler.Goroutine_Id;
                       Result : out Claim_Result) is
      begin
         case State is
            when Idle =>
               State  := Running;
               Result := Run;
            when Done =>
               Result := Finished;
            when Running =>
               Result := Wait;
               if G /= Scheduler.No_Goroutine then
                  Waiters.Append (G);
               end if;
         end case;
      end Claim;

      procedure Finish (Wake : out Waiter_Lists.List) is
      begin
         State := Done;
         Wake.Move (Source => Waiters);
      end Finish;

      entry Await_Blocking when State = Done is
      begin
         null;
      end Await_Blocking;

   end Once_Core;

   procedure Do_K (O : in out Once; F : not null access procedure) is
      Me     : constant Scheduler.Goroutine_Id := Scheduler.Current;
      Result : Claim_Result;
      Wake   : Waiter_Lists.List;
   begin
      loop
         O.Core.Claim (Me, Result);
         case Result is
            when Finished =>
               return;
            when Run =>
               begin
                  F.all;   --  outside any protected action
               exception
                  when others =>
                     --  Go marks done even when f panics.
                     O.Core.Finish (Wake);
                     Wake_All (Wake);
                     raise;
               end;
               O.Core.Finish (Wake);
               Wake_All (Wake);
               return;
            when Wait =>
               if Me = Scheduler.No_Goroutine then
                  O.Core.Await_Blocking;
                  return;
               end if;
               Scheduler.Park;  --  Finish Unparks us; Claim sees Done
         end case;
      end loop;
   end Do_K;

   ---------------------------------------------------------------
   --  Cond
   ---------------------------------------------------------------

   protected body Waiter_Count is

      procedure Inc is
      begin
         N := N + 1;
      end Inc;

      procedure Dec is
      begin
         if N > 0 then
            N := N - 1;
         end if;
      end Dec;

      function Value return Natural is (N);

   end Waiter_Count;

   function New_Cond (L : Mutex_Access) return Cond_Access is
   begin
      return new Cond'(L       => L,
                       Ch      => Unit_Channels.Make,
                       Waiters => <>);
   end New_Cond;

   procedure Wait (C : in out Cond) is
      V  : Boolean;
      OK : Boolean;
      pragma Unreferenced (V, OK);  --  the channel is never closed
   begin
      --  Go's contract: the caller holds C.L. Register as a waiter
      --  BEFORE releasing L so a Signal that fires between the Unlock
      --  and the park still leaves a token in the channel buffer.
      C.Waiters.Inc;
      Unlock (C.L.all);
      Unit_Channels.Receive (C.Ch, V, OK);
      Lock (C.L.all);
      C.Waiters.Dec;
   end Wait;

   procedure Signal (C : in out Cond) is
   begin
      --  Only wake when somebody is actually parked, so a Signal with
      --  no waiters leaves no stale token (Go: no-op).
      if C.Waiters.Value > 0 then
         Unit_Channels.Send (C.Ch, True);
      end if;
   end Signal;

   procedure Broadcast (C : in out Cond) is
      W : constant Natural := C.Waiters.Value;
   begin
      for I in 1 .. W loop
         Unit_Channels.Send (C.Ch, True);
      end loop;
   end Broadcast;

end Gada.Std.Sync;
