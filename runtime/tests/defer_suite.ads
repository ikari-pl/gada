--  AUnit suite for Gada.Core.Defer.
--
--  Covers the four properties Go's `defer` semantics commit to:
--    1. Single defer fires at scope exit.
--    2. Multiple defers fire in LIFO order.
--    3. Defer fires under exception unwind (panic-clean-up
--       contract, exercised here directly via `raise` so the suite
--       does not yet depend on Phase 2 item 4 — Gada.Core.Panic).
--    4. Defer is zero-alloc — Total_Bytes_Allocated does not move
--       across declaration and finalisation of a Defer_Block.

with AUnit;
with AUnit.Test_Cases;

package Defer_Suite is

   type Defer_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Defer_Test);
   overriding function  Name (T : Defer_Test) return AUnit.Message_String;

   procedure Test_Single_Defer_Fires
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Multiple_Defers_LIFO
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Defer_Fires_Under_Exception
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Defer_Is_Zero_Alloc
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Defer_Suite;
