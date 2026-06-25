--  Gada.Reflect.Interfaces body — see spec.
--
--  A protected object wraps a hashed set of (Concrete, Iface) pairs.
--  Register (write) uses Include, so a repeated pair is a no-op; Satisfies
--  (read) is a protected function, so concurrent goroutine queries run in
--  parallel. The hash combines the two Type_Ids; Hashed_Sets gives O(1)
--  Contains.

with Ada.Containers; use Ada.Containers;
with Ada.Containers.Hashed_Sets;

package body Gada.Reflect.Interfaces is

   use Gada.Reflect.Types;

   type Pair is record
      Concrete : Type_Id;
      Iface    : Type_Id;
   end record;

   --  Mix the two Ids. A repeatable, order-sensitive combine — (C, I)
   --  and (I, C) are different satisfaction facts, so the hash must
   --  distinguish them.
   function Hash (P : Pair) return Hash_Type is
     (Hash_Type (Natural (P.Concrete)) * 65_599
      + Hash_Type (Natural (P.Iface)));

   package Pair_Sets is new Ada.Containers.Hashed_Sets
     (Element_Type        => Pair,
      Hash                => Hash,
      Equivalent_Elements => "=");

   protected Store is
      procedure Add (P : Pair);
      function Has (P : Pair) return Boolean;
   private
      Table : Pair_Sets.Set;
   end Store;

   protected body Store is

      procedure Add (P : Pair) is
      begin
         --  Include = insert, no-op if already present (idempotent).
         Table.Include (P);
      end Add;

      function Has (P : Pair) return Boolean is
        (Table.Contains (P));

   end Store;

   procedure Register
     (Concrete : Type_Id;
      Iface    : Type_Id) is
   begin
      if Concrete = No_Type or else Iface = No_Type then
         raise Constraint_Error
           with "Gada.Reflect.Interfaces: cannot register a satisfaction "
                & "pair involving the No_Type (0) sentinel";
      end if;
      Store.Add ((Concrete => Concrete, Iface => Iface));
   end Register;

   function Satisfies
     (Concrete : Type_Id;
      Iface    : Type_Id) return Boolean is
     (Store.Has ((Concrete => Concrete, Iface => Iface)));

end Gada.Reflect.Interfaces;
