with Gada.Async.Channels.Bounded;
with Gada.Async.Scheduler;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with System;

package body P is

   package Channels_Of_Integer is new Gada.Async.Channels.Bounded (Element_Type => Integer);

   procedure Relay (Ping : Channels_Of_Integer.Channel; Pong : Channels_Of_Integer.Channel) is
      V : Integer;
   begin
      declare
         Discard_OK : Boolean;
      begin
         Channels_Of_Integer.Receive (Ping, V, Discard_OK);
      end;
      Channels_Of_Integer.Send (Pong, V);
   end Relay;

   procedure Start is
      A : Channels_Of_Integer.Channel := Channels_Of_Integer.Make (1);
      B : Channels_Of_Integer.Channel := Channels_Of_Integer.Make (1);
      type Go_Closure_1 is record
         Ping : Channels_Of_Integer.Channel;
         Pong : Channels_Of_Integer.Channel;
      end record;
      type Go_Closure_1_Access is access Go_Closure_1;
      function To_Go_Closure_1 is new Ada.Unchecked_Conversion (System.Address, Go_Closure_1_Access);
      function Closure_Addr_1 is new Ada.Unchecked_Conversion (Go_Closure_1_Access, System.Address);
      procedure Free_Go_Closure_1 is new Ada.Unchecked_Deallocation (Go_Closure_1, Go_Closure_1_Access);
      function Allocate_Closure_1 (Ping : Channels_Of_Integer.Channel; Pong : Channels_Of_Integer.Channel) return System.Address is
      begin
         return Closure_Addr_1 (new Go_Closure_1'(Ping => Ping, Pong => Pong));
      end Allocate_Closure_1;
      procedure Go_Worker_1 is
         Go_Closure_1_Obj : Go_Closure_1_Access := To_Go_Closure_1 (Gada.Async.Scheduler.Closure (Gada.Async.Scheduler.Current));
         Ping : constant Channels_Of_Integer.Channel := Go_Closure_1_Obj.Ping;
         Pong : constant Channels_Of_Integer.Channel := Go_Closure_1_Obj.Pong;
      begin
         Free_Go_Closure_1 (Go_Closure_1_Obj);
         Relay (Ping, Pong);
      end Go_Worker_1;
      Unused_G : Gada.Async.Scheduler.Goroutine_Id;
   begin
      Unused_G := Gada.Async.Scheduler.Spawn (Go_Worker_1'Unrestricted_Access, Allocate_Closure_1 (A, B));
   end Start;

end P;
