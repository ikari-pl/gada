--  Gada.Core.Memory.Libgc — thin C bindings to Boehm-Demers-Weiser
--  (https://www.hboehm.info/gc/), the v1 GADA garbage collector.
--
--  This is a *private child* of Gada.Core.Memory: only the parent
--  body and other private siblings can `with` it. Higher layers
--  (Gada.Async, Gada.Std, transpiled user code) reach the GC via
--  the GC-agnostic public surface in `gada-core-memory.ads`. The
--  private-child kind enforces that contract at compile time —
--  Ada rejects an external `with Gada.Core.Memory.Libgc;`.
--
--  No body. The pragma Import declarations *are* the body — each
--  subprogram is implemented by the foreign C function libgc
--  exports. The link path is set up in `runtime/gada_core.gpr`
--  via pkg-config; see docs/adr/0005-libgc-binding-via-pkgconfig.md.
--
--  Bindings are intentionally narrow: only the libgc entry points
--  the v1 GADA runtime currently consumes. Adding more (finalizer
--  registration, alternate roots for libco coroutine stacks,
--  per-thread registration) is a follow-on task as Phase 2 +
--  Phase 3 work them in.

with Interfaces.C;
with System;

private package Gada.Core.Memory.Libgc is

   --  Initialize the collector. Must be called once at runtime
   --  startup, before any allocation. libgc's `GC_init` is
   --  documented as idempotent — a second call is a no-op.
   procedure GC_Init;
   pragma Import (C, GC_Init, "GC_init");

   --  Allocate Size bytes of GC-traced memory. The returned
   --  region is conservatively scanned: pointers it contains
   --  keep their referents alive across collections. libgc
   --  raises a fatal handler on out-of-memory rather than
   --  returning null, so the address is always valid on return.
   function GC_Malloc
     (Size : Interfaces.C.size_t) return System.Address;
   pragma Import (C, GC_Malloc, "GC_malloc");

   --  Allocate Size bytes of pointer-free memory. Faster than
   --  GC_Malloc because the region is excluded from scanning.
   --  Use only when the allocated type's static layout is
   --  guaranteed to contain no pointers (Go int / float64 /
   --  byte and arrays/structs of those).
   function GC_Malloc_Atomic
     (Size : Interfaces.C.size_t) return System.Address;
   pragma Import (C, GC_Malloc_Atomic, "GC_malloc_atomic");

   --  Force a full collection cycle. Returns when the cycle
   --  completes. Tests use this to make collection observable;
   --  production code rarely needs it because libgc collects
   --  automatically as the heap grows.
   procedure GC_Gcollect;
   pragma Import (C, GC_Gcollect, "GC_gcollect");

   --  Current heap size in bytes (live + dead + free-list, not
   --  just live). Useful as a coarse progress signal in tests;
   --  not a precise live-set measurement.
   function GC_Get_Heap_Size return Interfaces.C.size_t;
   pragma Import (C, GC_Get_Heap_Size, "GC_get_heap_size");

end Gada.Core.Memory.Libgc;
