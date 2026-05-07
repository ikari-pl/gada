with Gada.Async.Channels.Bounded;

package body P is

   package Channels_Of_Integer is new Gada.Async.Channels.Bounded (Element_Type => Integer);
   package Channels_Of_String is new Gada.Async.Channels.Bounded (Element_Type => String);

   procedure Produce (C : Channels_Of_Integer.Channel) is
   begin
      Channels_Of_Integer.Send (C, 1);
      Channels_Of_Integer.Send (C, 2);
      Channels_Of_Integer.Close (C);
   end Produce;

   procedure Drain (C : Channels_Of_Integer.Channel) is
      V : Integer;
      Ok : Boolean;
   begin
      Channels_Of_Integer.Receive (C, V, Ok);
      if not Ok then
         return;
      end if;
      Channels_Of_Integer.Send (C, V);
      Channels_Of_Integer.Close (C);
   end Drain;

   procedure CloseString (C : Channels_Of_String.Channel) is
   begin
      Channels_Of_String.Close (C);
   end CloseString;

end P;
