--  Gada.Core.Memory body — delegates to the libgc-backed
--  implementation in the private child Gada.Core.Memory.Libgc.
--
--  Replacing the v1 GC means swapping this body and (optionally)
--  the private-child set; the public spec in `gada-core-memory.ads`
--  is the contract higher layers depend on. See
--  docs/adr/0005-libgc-binding-via-pkgconfig.md for the four-criterion
--  parity bar any future replacement must clear.

with Interfaces.C;

with Gada.Core.Memory.Libgc;

package body Gada.Core.Memory is

   procedure Initialize is
   begin
      Libgc.GC_Init;
   end Initialize;

   function Allocate
     (Size : System.Storage_Elements.Storage_Count) return System.Address
   is
   begin
      return Libgc.GC_Malloc (Interfaces.C.size_t (Size));
   end Allocate;

   function Allocate_Atomic
     (Size : System.Storage_Elements.Storage_Count) return System.Address
   is
   begin
      return Libgc.GC_Malloc_Atomic (Interfaces.C.size_t (Size));
   end Allocate_Atomic;

   procedure Collect is
   begin
      Libgc.GC_Gcollect;
   end Collect;

   function Heap_Size
     return System.Storage_Elements.Storage_Count
   is
   begin
      return System.Storage_Elements.Storage_Count
        (Libgc.GC_Get_Heap_Size);
   end Heap_Size;

   function Total_Bytes_Allocated
     return System.Storage_Elements.Storage_Count
   is
   begin
      return System.Storage_Elements.Storage_Count
        (Libgc.GC_Get_Total_Bytes);
   end Total_Bytes_Allocated;

end Gada.Core.Memory;
