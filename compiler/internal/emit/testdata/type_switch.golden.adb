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
   type Cat is new Speaker with record
      Lives : Integer;
   end record;
   overriding procedure Speak (C : Cat);

   overriding procedure Speak (D : Dog) is
   begin
      null;
   end Speak;

   overriding procedure Speak (C : Cat) is
   begin
      null;
   end Speak;

   function Describe (S : Speaker'Class) return Integer is
   begin
      if S in Dog'Class then
         declare
            D : Dog := Dog (S);
         begin
            return D.Legs;
         end;
      elsif S in Cat'Class then
         declare
            D : Cat := Cat (S);
         begin
            return D.Lives;
         end;
      else
         return 0;
      end if;
   end Describe;

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
      Gada.Reflect.Types.Add_Field (Meta, "Legs", Field_Type => 4);
      Gada.Reflect.Types.Add_Method (Meta, "Speak");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Cat
      Meta := Gada.Reflect.Types.Make (Id => 3, Name => "Cat", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "Lives", Field_Type => 4);
      Gada.Reflect.Types.Add_Method (Meta, "Speak");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 4, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
   --  Dog satisfies Speaker
   Gada.Reflect.Interfaces.Register (Concrete => 2, Iface => 1);
   --  Cat satisfies Speaker
   Gada.Reflect.Interfaces.Register (Concrete => 3, Iface => 1);
end P;
