--  Gada.Core.Memory — GC-managed allocator interface for the GADA
--  runtime.
--
--  This is the public, GC-agnostic surface that higher layers
--  (Gada.Async, Gada.Std, transpiled Go user code) call into. The
--  current v1 implementation delegates to the Boehm-Demers-Weiser
--  conservative collector via the private child
--  Gada.Core.Memory.Libgc; the implementation is replaceable behind
--  this interface per ADRs 0003 + 0005.
--
--  Layering contract: per ADR-0002, no upward `with` and no sibling
--  `with` from `Gada.Async` / `Gada.Reflect`. This package is in
--  `Gada.Core` and may be imported by everyone above.

with System;
with System.Storage_Elements;

package Gada.Core.Memory is

   --  Initialize the collector. Must be called exactly once, at
   --  runtime startup, before any allocation. Idempotent: a second
   --  call is a no-op, matching libgc's `GC_init` contract.
   procedure Initialize;

   --  Allocate Size bytes of GC-traced memory. Pointers in the
   --  returned region keep their referents alive across collections.
   --  libgc raises a fatal on out-of-memory rather than returning
   --  null, so the address is always valid on return. Callers
   --  type-pun the address to the appropriate access type.
   function Allocate
     (Size : System.Storage_Elements.Storage_Count) return System.Address;

   --  Allocate Size bytes of pointer-free memory. Faster than
   --  Allocate because the region is excluded from scanning.
   --  Use only for objects whose static type guarantees no pointers
   --  (Go int / float64 / byte arrays / structs of those).
   --  Misuse is a memory-safety bug: a pointer stored in an atomic
   --  region will not keep its referent alive.
   function Allocate_Atomic
     (Size : System.Storage_Elements.Storage_Count) return System.Address;

   --  Force a full collection cycle. Returns when the cycle completes.
   --  Tests use this to make collection observable; production code
   --  rarely needs it because libgc collects automatically as the
   --  heap grows.
   procedure Collect;

   --  Current heap size in bytes (live + dead + free-list, not just
   --  live). Useful as a coarse progress signal in tests; not a
   --  precise live-set measurement.
   function Heap_Size
     return System.Storage_Elements.Storage_Count;

end Gada.Core.Memory;
