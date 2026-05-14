--  Body of Context_Suite — see spec for property list.
--
--  Suppress GNAT 15's `-gnatw_a` warning on AUnit's `new …_Test`
--  registration pattern (file-scope), same trade-off as
--  `tests/test_runner.adb` and `stress_gc_suite.adb`.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Real_Time;
with Ada.Text_IO;

with Gada.Async.Context; use Gada.Async.Context;

package body Context_Suite is

   --  Package-level globals shared between the test driver and the
   --  trampolined Ping/Pong procedures. Each test resets them before
   --  use; the order of registered routines does not matter because
   --  each routine zeroes the counter and creates fresh contexts.
   --
   --  Globals (rather than test-procedure locals) because libco's
   --  entry signature is parameterless: there is no way to pass a
   --  closure pointer to the cothread, so the routines must reach
   --  through file-scope state. The Phase 3 scheduler (item 3) will
   --  hide this via the goroutine struct; here we deliberately keep
   --  the test plumbing thin so a regression points at the failing
   --  property, not a layer of indirection.
   Iter_Count : Natural := 0;
   Target_Iter : Natural := 0;

   Main_Ctx : Context := Null_Context;
   Ping_Ctx : Context := Null_Context;
   Pong_Ctx : Context := Null_Context;

   procedure Ping;
   procedure Pong;
   procedure Two_Context_Hello;
   procedure Quiet_Entry;
   Two_Context_Ran : Boolean := False;
   Quiet_Entry_Ran : Boolean := False;

   --  Quiet_Entry is the canary for the trampoline tail-stub: it sets
   --  a flag and *returns* (no Switch_To). Under the previous "fall
   --  off into libco UB" design this either crashed or hung; under
   --  the current No_Return Trampoline + Exits-table design control
   --  bounces back to the test driver via the recorded exit context.
   procedure Quiet_Entry is
   begin
      Quiet_Entry_Ran := True;
   end Quiet_Entry;

   procedure Ping is
   begin
      while Iter_Count < Target_Iter loop
         Iter_Count := @ + 1;
         Switch_To (Pong_Ctx);
      end loop;
      --  Done — yield back to the test driver. After this Switch_To
      --  the cothread's stack frame is suspended at this exact PC;
      --  Free in the test driver releases the stack cleanly because
      --  the cothread is no longer Active by the time Free runs.
      Switch_To (Main_Ctx);
   end Ping;

   procedure Pong is
   begin
      loop
         Switch_To (Ping_Ctx);
         --  Pong runs forever from its own perspective. Control
         --  reaches here only when Ping yields to it; Ping yields
         --  back to Main_Ctx after Target_Iter rounds, so Pong's
         --  stack frame is suspended at this Switch_To when the
         --  test ends. Free reclaims it.
      end loop;
   end Pong;

   procedure Two_Context_Hello is
   begin
      Two_Context_Ran := True;
      Switch_To (Main_Ctx);
   end Two_Context_Hello;

   overriding function Name
     (T : Context_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Async.Context suite (PKG=async.context)"));

   overriding procedure Register_Tests (T : in out Context_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Make_Free_Round_Trip'Access,
         "Make/Free is balanced — 1000 cycles complete without "
         & "raising and yield non-null contexts");
      Register_Routine
        (T, Test_Two_Context_Switch'Access,
         "Switch_To dispatches into the trampoline'd entry "
         & "procedure and returns to the caller");
      Register_Routine
        (T, Test_Ping_Pong_1M_Iterations'Access,
         "1M ping-pong iterations complete in < 1 s wall-clock");
      Register_Routine
        (T, Test_Free_Null_Context'Access,
         "Free (Null_Context) is a no-op and leaves the handle "
         & "as Null_Context (idempotent half-init / half-teardown)");
      Register_Routine
        (T, Test_Entry_Returns_Tail_Yields'Access,
         "Trampoline tail-stub yields control back to the spawner "
         & "when the user's entry returns without an explicit "
         & "Switch_To (rather than falling off the end of the "
         & "cothread, which is libco-undefined)");
   end Register_Tests;

   procedure Test_Make_Free_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Context;
   begin
      --  Reset shared state so a prior test's leftover doesn't
      --  bleed into this one (test order is not contractual under
      --  AUnit, but defensive resets keep failures localised).
      Two_Context_Ran := False;

      for I in 1 .. 1_000 loop
         Make (C, Two_Context_Hello'Access);
         Assert (C /= Null_Context,
                 "Make returned Null_Context on iteration "
                 & I'Image);
         Free (C);
         Assert (C = Null_Context,
                 "Free did not zero the handle on iteration "
                 & I'Image);
      end loop;
   end Test_Make_Free_Round_Trip;

   procedure Test_Two_Context_Switch
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Hello_Ctx : Context;
   begin
      Two_Context_Ran := False;
      Main_Ctx := Active;
      Make (Hello_Ctx, Two_Context_Hello'Access);
      Switch_To (Hello_Ctx);

      --  Control resumes here only after Two_Context_Hello yields
      --  back via Switch_To (Main_Ctx). If the trampoline never
      --  ran, Two_Context_Ran is still False; if Hello_Ctx leaked
      --  control somewhere else, we never reach this line at all
      --  (the test would hang and CI's harness time-out would fire).
      Assert (Two_Context_Ran,
              "Two_Context_Hello did not run inside the cothread");

      Free (Hello_Ctx);
   end Test_Two_Context_Switch;

   procedure Test_Ping_Pong_1M_Iterations
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Ada.Real_Time.Time, Ada.Real_Time.Time_Span;

      Started, Finished : Ada.Real_Time.Time;
      Elapsed_Ms        : Duration;

      Wall_Clock_Budget_Ms : constant := 1_000;  --  1 s ceiling.
   begin
      Iter_Count  := 0;
      Target_Iter := 1_000_000;
      Main_Ctx    := Active;

      Make (Ping_Ctx, Ping'Access);
      Make (Pong_Ctx, Pong'Access);

      Started := Ada.Real_Time.Clock;
      Switch_To (Ping_Ctx);
      Finished := Ada.Real_Time.Clock;

      Elapsed_Ms := Ada.Real_Time.To_Duration (Finished - Started)
                    * 1_000.0;

      Assert (Iter_Count = Target_Iter,
              "ping-pong stopped early: Iter_Count="
              & Iter_Count'Image
              & " Target_Iter=" & Target_Iter'Image);

      Assert (Elapsed_Ms < Duration (Wall_Clock_Budget_Ms),
              "ping-pong wall-clock"
              & Elapsed_Ms'Image & " ms exceeded budget"
              & Integer'Image (Wall_Clock_Budget_Ms) & " ms");

      --  Surface the actual time into the AUnit log. Useful for
      --  watching the trend over libco / libgc / GCC version
      --  bumps; not asserted because the contract is "< 1 s",
      --  not "= constant".
      Ada.Text_IO.Put_Line
        ("    [info] ping-pong" & Elapsed_Ms'Image & " ms / "
         & Target_Iter'Image & " iterations");

      Free (Ping_Ctx);
      Free (Pong_Ctx);
   end Test_Ping_Pong_1M_Iterations;

   procedure Test_Free_Null_Context
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Context := Null_Context;
   begin
      --  Documented no-op; mostly checks we don't dereference Null,
      --  don't raise, and leave the handle in its Null state.
      Free (C);
      Assert (C = Null_Context,
              "Free (Null_Context) altered the handle");
   end Test_Free_Null_Context;

   procedure Test_Entry_Returns_Tail_Yields
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Context;
   begin
      Quiet_Entry_Ran := False;
      Make (C, Quiet_Entry'Access);
      --  Switch_To records the test driver's address as Quiet_Entry's
      --  exit context. Quiet_Entry sets the flag and returns; the
      --  Trampoline's tail loop then Co_Switches back here. If the
      --  tail-stub regressed, this test would hang (CI harness
      --  time-out fires) or crash inside libco's "fell off the end"
      --  undefined-behaviour territory.
      Switch_To (C);
      Assert (Quiet_Entry_Ran,
              "Quiet_Entry did not run inside the cothread");
      Free (C);
   end Test_Entry_Returns_Tail_Yields;

end Context_Suite;
