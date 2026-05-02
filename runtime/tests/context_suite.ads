--  AUnit suite for Gada.Async.Context.
--
--  Covers the public API's behavioural commitments:
--    1. Make + Free is allocation-balanced — repeated Make/Free
--       cycles do not leak heap (proxy: stable heap_size delta).
--    2. Two-context Switch_To round-trips correctly — control
--       lands inside the entry procedure, yields back, and returns
--       to the caller of the initial Switch_To.
--    3. 1M ping-pong iterations complete in well under 1 s
--       wall-clock — the Phase 3 item 2 exit-criterion contract.
--    4. Free (Null_Context) is a documented no-op (idempotent
--       half-init / half-teardown) — the spec contract bears it
--       out and a regression here would silently corrupt cleanup
--       paths in higher layers.
--    5. When the user's entry procedure returns naturally without
--       yielding, the trampoline tail-stub bounces control back to
--       whoever first switched into the cothread — instead of
--       falling off the end into libco's undefined-behaviour
--       territory. (See gada-async-context.adb's Trampoline body.)

with AUnit;
with AUnit.Test_Cases;

package Context_Suite is

   type Context_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Context_Test);
   overriding function  Name (T : Context_Test) return AUnit.Message_String;

   procedure Test_Make_Free_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Two_Context_Switch
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Ping_Pong_1M_Iterations
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Free_Null_Context
     (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Entry_Returns_Tail_Yields
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Context_Suite;
