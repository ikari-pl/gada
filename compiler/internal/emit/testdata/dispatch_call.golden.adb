with Gada.Reflect.Types;
with Gada.Reflect.Registry;

package body P is

   type Speaker is interface;
   procedure Speak (Self : Speaker) is abstract;

   procedure Describe (S : Speaker'Class) is
   begin
      S.Speak;
   end Describe;

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Speaker
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Speaker", Kind => Gada.Reflect.Types.Interface_Kind);
      Gada.Reflect.Types.Add_Method (Meta, "Speak");
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
end P;
