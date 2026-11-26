--  Body of Gada.Std.Sync — see spec for the Go-semantics contract.

package body Gada.Std.Sync is

   ---------------------------------------------------------------
   --  Mutex
   ---------------------------------------------------------------

   protected body Mutex is

      entry Lock when not Locked is
      begin
         Locked := True;
      end Lock;

      procedure Unlock is
      begin
         --  Go: Unlock of an unlocked mutex is a fatal error (panic).
         if not Locked then
            raise Constraint_Error with "sync: unlock of unlocked mutex";
         end if;
         Locked := False;
      end Unlock;

      procedure Try_Lock (Ok : out Boolean) is
      begin
         --  A protected procedure call already has exclusive access, so
         --  this never blocks on the mutex itself: it only waits out
         --  any in-flight protected operation (a nanoseconds-wide
         --  window, same shape as Go's futex fast path).
         Ok := not Locked;
         if Ok then
            Locked := True;
         end if;
      end Try_Lock;

      function Is_Locked return Boolean is (Locked);

   end Mutex;

   ---------------------------------------------------------------
   --  RWMutex
   ---------------------------------------------------------------

   protected body RW_Mutex is

      entry Lock when not Writer and then Readers = 0 is
      begin
         Writer := True;
      end Lock;

      entry R_Lock when not Writer is
      begin
         Readers := Readers + 1;
      end R_Lock;

      procedure Unlock is
      begin
         --  Go: Unlock with no write lock held panics.
         if not Writer then
            raise Constraint_Error
              with "sync: unlock of unlocked RWMutex";
         end if;
         Writer := False;
      end Unlock;

      procedure R_Unlock is
      begin
         --  Go: RUnlock with no read lock held panics.
         if Readers = 0 then
            raise Constraint_Error
              with "sync: RUnlock of unlocked RWMutex";
         end if;
         Readers := Readers - 1;
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

   end RW_Mutex;

   ---------------------------------------------------------------
   --  WaitGroup
   ---------------------------------------------------------------

   protected body Wait_Group is

      procedure Add (Amount : Integer) is
      begin
         --  Go: Add with a negative delta that would drive the counter
         --  below zero panics ("sync: negative WaitGroup counter").
         if Amount < 0 and then Integer (N) + Amount < 0 then
            raise Constraint_Error
              with "sync: negative WaitGroup counter";
         end if;
         N := N + Amount;
      end Add;

      procedure Done is
      begin
         --  Go: Done() == Add(-1), same underflow panic.
         if N = 0 then
            raise Constraint_Error
              with "sync: negative WaitGroup counter";
         end if;
         N := N - 1;
      end Done;

      entry Wait when N = 0 is
      begin
         null;  --  the barrier did the work
      end Wait;

      function Value return Natural is (N);

   end Wait_Group;

   ---------------------------------------------------------------
   --  Once
   ---------------------------------------------------------------

   protected body Once is

      procedure Do_K (F : Procedure_Access) is
      begin
         if not Done_Flag then
            begin
               F.all;
            exception
               --  Go marks done even when f panics (defer in once.Do).
               when others =>
                  Done_Flag := True;
                  raise;
            end;
            Done_Flag := True;
         end if;
      end Do_K;

   end Once;

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
      C.L.all.Unlock;
      Unit_Channels.Receive (C.Ch, V, OK);
      C.L.all.Lock;
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
