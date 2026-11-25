with Gada.Reflect.Types;
with Gada.Reflect.Registry;
with Gada.Reflect.Interfaces;

package body P is

   type Speaker is interface;
   procedure Speak (Self : Speaker) is abstract;

   type Dog is new Speaker with record
      Legs : Integer;
   end record;
   overriding procedure Speak (D : Dog);

   overriding procedure Speak (D : Dog) is
   begin
      null;
   end Speak;

   function Check (S : Speaker'Class) return Integer is
      D : Dog := Dog (S);
   begin
      return D.Legs;
   end Check;

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Speaker
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Speaker", Kind => Gada.Reflect.Types.Interface_Kind);
      Gada.Reflect.Types.Add_Method (Meta, "Speak");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Dog
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "Dog", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "Legs", Field_Type => 3);
      Gada.Reflect.Types.Add_Method (Meta, "Speak");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 3, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
   --  Dog satisfies Speaker
   Gada.Reflect.Interfaces.Register (Concrete => 2, Iface => 1);
end P;
