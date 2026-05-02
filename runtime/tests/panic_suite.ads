--  AUnit suite for `Gada.Core.Panic`.
--
--  Five tests cover the full panic/recover state machine:
--
--    1. Do_Panic raises `Panicking` and Recover (called from the
--       handler) returns the payload.
--    2. Recover with no panic in flight returns Default — Go's
--       `recover() == nil` outside-defer semantics.
--    3. Nested panics: outer panic, handler raises inner panic,
--       inner Recover returns inner payload, outer Recover then
--       returns outer payload. Verifies LIFO stack ordering.
--    4. Pending-stack overflow raises Constraint_Error rather
--       than silently truncating — defensive correctness contract
--       documented in the spec.
--    5. End-to-end Defer + Panic + Recover integration: a
--       Defer_Block whose Op calls Recover catches a Do_Panic
--       raised inside the same block. This is the shape the
--       compiler-emit layer (Phase 2 item 8) translates Go's
--       `defer func() { recover() }()` into.

with AUnit;
with AUnit.Test_Cases;

package Panic_Suite is

   type Panic_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Panic_Test);
   overriding function  Name (T : Panic_Test) return AUnit.Message_String;

   procedure Test_Panic_And_Recover
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Recover_When_Not_Panicking
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Nested_Panics_LIFO
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Pending_Stack_Overflow
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Defer_Recovers_Panic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Panic_Suite;
