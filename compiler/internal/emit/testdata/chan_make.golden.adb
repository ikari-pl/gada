with Gada.Async.Channels.Bounded;

package body P is

   package Channels_Of_Integer is new Gada.Async.Channels.Bounded (Element_Type => Integer);
   package Channels_Of_String is new Gada.Async.Channels.Bounded (Element_Type => String);

   procedure ConsumeInt (C : Channels_Of_Integer.Channel) is
   begin
      null;
   end ConsumeInt;

   procedure ConsumeString (C : Channels_Of_String.Channel) is
   begin
      null;
   end ConsumeString;

   procedure MakeBuffered is
   begin
      ConsumeInt (Channels_Of_Integer.Make (8));
      ConsumeInt (Channels_Of_Integer.Make (1));
      ConsumeString (Channels_Of_String.Make (4));
   end MakeBuffered;

end P;
