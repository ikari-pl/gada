--  Gada.Reflect.Registry body — see spec.
--
--  A protected object wraps an ordered map keyed by Type_Id. Register
--  is a protected procedure (write); Lookup is a protected function
--  (read) so concurrent TypeOf calls from goroutines proceed in
--  parallel. Ordered_Maps (not Hashed_Maps) so no hash function is
--  needed — Type_Id derives from Natural and already has "<" and "=".
--  Include gives last-wins on a duplicate Id.

with Ada.Containers.Ordered_Maps;

package body Gada.Reflect.Registry is

   use Gada.Reflect.Types;

   package Type_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type     => Type_Id,
      Element_Type => Type_Descriptor);

   protected Store is
      procedure Register (T : Type_Descriptor);
      function Get (Id : Type_Id) return Type_Descriptor;
   private
      Table : Type_Maps.Map;
   end Store;

   protected body Store is

      procedure Register (T : Type_Descriptor) is
      begin
         --  Include = insert, or replace if the Id is already present
         --  (last-wins on a duplicate registration).
         Table.Include (Id (T), T);
      end Register;

      function Get (Id : Type_Id) return Type_Descriptor is
         C : constant Type_Maps.Cursor := Table.Find (Id);
      begin
         if Type_Maps.Has_Element (C) then
            return Type_Maps.Element (C);
         else
            --  Unregistered: the zero reflect.Type (Invalid_Kind).
            return Make (Id => No_Type, Name => "", Kind => Invalid_Kind);
         end if;
      end Get;

   end Store;

   procedure Register_Type (T : Type_Descriptor) is
   begin
      Store.Register (T);
   end Register_Type;

   function Lookup (Id : Type_Id) return Type_Descriptor is
     (Store.Get (Id));

end Gada.Reflect.Registry;
