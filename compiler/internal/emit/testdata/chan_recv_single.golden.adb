with Gada.Async.Channels.Bounded;

package body P is

   package Channels_Of_Integer is new Gada.Async.Channels.Bounded (Element_Type => Integer);
   package Channels_Of_String is new Gada.Async.Channels.Bounded (Element_Type => String);

   procedure RecvInt (C : Channels_Of_Integer.Channel) is
      V : Integer;
   begin
      declare
         Discard_OK : Boolean;
      begin
         Channels_Of_Integer.Receive (C, V, Discard_OK);
      end;
      Channels_Of_Integer.Send (C, V + 1);
   end RecvInt;

   procedure RecvString (C : Channels_Of_String.Channel) is
      S : String;
   begin
      declare
         Discard_OK : Boolean;
      begin
         Channels_Of_String.Receive (C, S, Discard_OK);
      end;
      Channels_Of_String.Send (C, S);
   end RecvString;

end P;
