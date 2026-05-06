with Gada.Async.Channels.Bounded;

package body P is

   package Channels_Of_Integer is new Gada.Async.Channels.Bounded (Element_Type => Integer);
   package Channels_Of_String is new Gada.Async.Channels.Bounded (Element_Type => String);

   procedure SendInts (C : Channels_Of_Integer.Channel) is
      X : Integer := 42;
   begin
      Channels_Of_Integer.Send (C, 1);
      Channels_Of_Integer.Send (C, X);
   end SendInts;

   procedure SendStrings (C : Channels_Of_String.Channel) is
   begin
      Channels_Of_String.Send (C, "hello");
   end SendStrings;

end P;
