with Gada.Reflect.Types;
with Gada.Reflect.Registry;
with Gada.Reflect.Interfaces;

package body P is

   type Reader is interface;
   function Read (Self : Reader) return Integer is abstract;
   procedure Close (Self : Reader) is abstract;
   type Writer is interface;
   procedure Write (Self : Writer; N : Integer) is abstract;
   procedure Close (Self : Writer) is abstract;

   type Buffer is new Reader and Writer with record
      Data : Integer;
   end record;
   overriding function Read (B : Buffer) return Integer;
   overriding procedure Close (B : Buffer);
   overriding procedure Write (B : Buffer; N : Integer);
   type Nop is new Reader with null record;
   overriding function Read (N : Nop) return Integer;
   overriding procedure Close (N : Nop);

   overriding function Read (B : Buffer) return Integer is
   begin
      return B.Data;
   end Read;

   overriding procedure Write (B : Buffer; N : Integer) is
   begin
      null;
   end Write;

   overriding procedure Close (B : Buffer) is
   begin
      null;
   end Close;

   overriding function Read (N : Nop) return Integer is
   begin
      return 0;
   end Read;

   overriding procedure Close (N : Nop) is
   begin
      null;
   end Close;

begin
   declare
      Meta : Gada.Reflect.Types.Type_Descriptor;
   begin
      --  Reader
      Meta := Gada.Reflect.Types.Make (Id => 1, Name => "Reader", Kind => Gada.Reflect.Types.Interface_Kind);
      Gada.Reflect.Types.Add_Method (Meta, "Read");
      Gada.Reflect.Types.Add_Method (Meta, "Close");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Writer
      Meta := Gada.Reflect.Types.Make (Id => 2, Name => "Writer", Kind => Gada.Reflect.Types.Interface_Kind);
      Gada.Reflect.Types.Add_Method (Meta, "Write");
      Gada.Reflect.Types.Add_Method (Meta, "Close");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Buffer
      Meta := Gada.Reflect.Types.Make (Id => 3, Name => "Buffer", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Field (Meta, "data", Field_Type => 5);
      Gada.Reflect.Types.Add_Method (Meta, "Read");
      Gada.Reflect.Types.Add_Method (Meta, "Write");
      Gada.Reflect.Types.Add_Method (Meta, "Close");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  Nop
      Meta := Gada.Reflect.Types.Make (Id => 4, Name => "Nop", Kind => Gada.Reflect.Types.Struct_Kind);
      Gada.Reflect.Types.Add_Method (Meta, "Read");
      Gada.Reflect.Types.Add_Method (Meta, "Close");
      Gada.Reflect.Registry.Register_Type (Meta);
      --  int
      Meta := Gada.Reflect.Types.Make (Id => 5, Name => "int", Kind => Gada.Reflect.Types.Int_Kind);
      Gada.Reflect.Registry.Register_Type (Meta);
   end;
   --  Buffer satisfies Reader
   Gada.Reflect.Interfaces.Register (Concrete => 3, Iface => 1);
   --  Buffer satisfies Writer
   Gada.Reflect.Interfaces.Register (Concrete => 3, Iface => 2);
   --  Nop satisfies Reader
   Gada.Reflect.Interfaces.Register (Concrete => 4, Iface => 1);
end P;
