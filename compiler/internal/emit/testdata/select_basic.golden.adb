with Gada.Async.Channels.Bounded;
with Gada.Async.Selector;

package body P is

   package Channels_Of_Integer is new Gada.Async.Channels.Bounded (Element_Type => Integer);

   package Selectors_Of_Integer is new Gada.Async.Selector
     (Element_Type    => Integer,
      Default_Element => 0,
      Bnd             => Channels_Of_Integer);

   procedure SelectAll (C1 : Channels_Of_Integer.Channel; C2 : Channels_Of_Integer.Channel) is
   begin
      declare
         V_1_1 : constant Selectors_Of_Integer.Element_Ptr := new Integer'(0);
         V_1_2 : constant Selectors_Of_Integer.Element_Ptr := new Integer'(0);
         OK_1_2 : constant Selectors_Of_Integer.Boolean_Ptr := new Boolean'(False);
         Sel_Cases_1 : Selectors_Of_Integer.Case_Array (1 .. 5);
         Sel_Idx_1 : Positive;
      begin
         Sel_Cases_1 (1) := (Kind             => Selectors_Of_Integer.Recv_Op,
                         Chan             => C1,
                         Send_V           => 0,
                         Recv_V_Out       => V_1_1,
                         Recv_OK_Out      => null,
                         Timeout_Duration => 0.0);
         Sel_Cases_1 (2) := (Kind             => Selectors_Of_Integer.Recv_Op,
                         Chan             => C1,
                         Send_V           => 0,
                         Recv_V_Out       => V_1_2,
                         Recv_OK_Out      => OK_1_2,
                         Timeout_Duration => 0.0);
         Sel_Cases_1 (3) := (Kind             => Selectors_Of_Integer.Recv_Op,
                         Chan             => C1,
                         Send_V           => 0,
                         Recv_V_Out       => null,
                         Recv_OK_Out      => null,
                         Timeout_Duration => 0.0);
         Sel_Cases_1 (4) := (Kind             => Selectors_Of_Integer.Send_Op,
                         Chan             => C2,
                         Send_V           => 42,
                         Recv_V_Out       => null,
                         Recv_OK_Out      => null,
                         Timeout_Duration => 0.0);
         Sel_Cases_1 (5) := (Kind             => Selectors_Of_Integer.Default_Op,
                         Chan             => Channels_Of_Integer.No_Channel,
                         Send_V           => 0,
                         Recv_V_Out       => null,
                         Recv_OK_Out      => null,
                         Timeout_Duration => 0.0);
         Sel_Idx_1 := Selectors_Of_Integer.Select_One (Sel_Cases_1);
         case Sel_Idx_1 is
            when 1 =>
               declare
                  V : Integer := V_1_1.all;
               begin
                  Channels_Of_Integer.Send (C2, V);
               end;
            when 2 =>
               declare
                  V : Integer := V_1_2.all;
                  Ok : Boolean := OK_1_2.all;
               begin
                  if Ok then
                     Channels_Of_Integer.Send (C2, V);
                  end if;
               end;
            when 3 =>
               Channels_Of_Integer.Send (C2, 0);
            when 4 =>
               null;
            when 5 =>
               null;
         end case;
      end;
   end SelectAll;

end P;
