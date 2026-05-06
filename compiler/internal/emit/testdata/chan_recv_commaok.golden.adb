with Gada.Async.Channels.Bounded;

package body P is

   package Channels_Of_Integer is new Gada.Async.Channels.Bounded (Element_Type => Integer);
   package Channels_Of_String is new Gada.Async.Channels.Bounded (Element_Type => String);

   procedure RecvCommaOk (C : Channels_Of_Integer.Channel) is
      V : Integer;
      Ok : Boolean;
   begin
      Channels_Of_Integer.Receive (C, V, Ok);
      if Ok then
         Channels_Of_Integer.Send (C, V + 1);
      end if;
   end RecvCommaOk;

   procedure RecvCommaOkString (C : Channels_Of_String.Channel) is
      S : String;
      Ok : Boolean;
   begin
      Channels_Of_String.Receive (C, S, Ok);
      if Ok then
         Channels_Of_String.Send (C, S);
      end if;
   end RecvCommaOkString;

end P;
