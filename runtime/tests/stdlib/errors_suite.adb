--  Body of Errors_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Tags;
with Gada.Std.Errors; use Gada.Std.Errors;

use type Ada.Tags.Tag;

package body Errors_Suite is

   --  A distinct dynamic type for the As tag-mismatch test. Default-
   --  initialised, so its tag is Special_Error even though the record
   --  components are private to Gada.Std.Errors.
   type Special_Error is new Error with null record;

   overriding function Name
     (T : Errors_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Errors suite"));

   overriding procedure Register_Tests (T : in out Errors_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_New_Error_Message'Access, "New_K + Message round-trip");
      Register_Routine
        (T, Test_Unwrap_No_Cause'Access, "Unwrap of a fresh error is No_Error");
      Register_Routine
        (T, Test_Unwrap_Chain'Access, "Unwrap walks to the root cause");
      Register_Routine
        (T, Test_Is_Sentinel'Access, "Is matches a sentinel by identity");
      Register_Routine
        (T, Test_Is_Deep_Chain'Access, "Is finds a target deep in the chain");
      Register_Routine
        (T, Test_Is_Nil_Cases'Access, "Is nil/nil, err/nil, nil/x");
      Register_Routine
        (T, Test_Is_Distinct_Values'Access, "Is false for distinct New values");
      Register_Routine
        (T, Test_As_Head_Match'Access, "As matches the head and assigns it");
      Register_Routine
        (T, Test_As_Chain_Match'Access, "As finds and assigns a chain member");
      Register_Routine
        (T, Test_As_Tag_Mismatch'Access, "As false on tag mismatch");
      Register_Routine
        (T, Test_As_Null_Err'Access, "As false on No_Error");
   end Register_Tests;

   procedure Test_New_Error_Message (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      E : constant Error_Access := New_K ("boom");
   begin
      Assert (E /= No_Error, "New_K must not return No_Error");
      Assert (Message (E.all) = "boom",
              "Message() must return the message, got: " & Message (E.all));
   end Test_New_Error_Message;

   procedure Test_Unwrap_No_Cause (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      E : constant Error_Access := New_K ("boom");
   begin
      Assert (Unwrap (E.all) = No_Error,
              "Unwrap of a causeless error must be No_Error");
      --  Go's Unwrap(nil) = nil; with Unwrap a tagged primitive the
      --  null case is handled by Is_K's nil matrix (tested above).
   end Test_Unwrap_No_Cause;

   procedure Test_Unwrap_Chain (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Root : constant Error_Access := New_K ("root");
      Mid  : constant Error_Access := With_Cause ("mid", Root);
      Top  : constant Error_Access := With_Cause ("top", Mid);
   begin
      Assert (Message (Unwrap (Top.all).all) = "mid", "Top unwraps to Mid");
      Assert (Message (Unwrap (Unwrap (Top.all).all).all) = "root",
              "Top unwraps twice to Root");
      Assert (Unwrap (Unwrap (Unwrap (Top.all).all).all) = No_Error,
              "chain ends at No_Error");
   end Test_Unwrap_Chain;

   procedure Test_Is_Sentinel (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Err_Sentinel : constant Error_Access := New_K ("sentinel");
      Wrapped      : constant Error_Access :=
        With_Cause ("ctx", Err_Sentinel);
   begin
      Assert (Is_K (Err_Sentinel, Err_Sentinel), "sentinel Is itself");
      Assert (Is_K (Wrapped, Err_Sentinel), "wrapped Is sentinel");
   end Test_Is_Sentinel;

   procedure Test_Is_Deep_Chain (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Target : constant Error_Access := New_K ("deep");
      E      : constant Error_Access :=
        With_Cause ("a", With_Cause ("b", With_Cause ("c", Target)));
   begin
      Assert (Is_K (E, Target), "Is finds a target three links deep");
   end Test_Is_Deep_Chain;

   procedure Test_Is_Nil_Cases (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      E : constant Error_Access := New_K ("x");
   begin
      Assert (Is_K (No_Error, No_Error), "Is(nil, nil) = true (Go semantics)");
      Assert (not Is_K (E, No_Error), "Is(err, nil) = false");
      Assert (not Is_K (No_Error, E), "Is(nil, err) = false");
   end Test_Is_Nil_Cases;

   procedure Test_Is_Distinct_Values (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      --  Go compares interface values: two errors.New("same") are
      --  distinct pointers, so Is is false. Our access identity matches.
      Assert (not Is_K (New_K ("same"), New_K ("same")),
              "distinct New values must not be Is-equal");
   end Test_Is_Distinct_Values;

   procedure Test_As_Head_Match (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      E   : constant Error_Access := New_K ("head");
      Tgt : aliased Error;
      TA  : constant access Error'Class := Tgt'Access;
   begin
      Assert (As (E, TA), "As must match the head");
      Assert (Message (Tgt) = "head", "As must assign the matched value");
   end Test_As_Head_Match;

   procedure Test_As_Chain_Match (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      --  Target has a distinct tag so the base-Error head does not
      --  match and As must walk the chain to the Special_Error member.
      Inner : constant Error_Access := new Special_Error;
      E     : constant Error_Access := With_Cause ("outer", Inner);
      Tgt   : aliased Special_Error;
      TA    : constant access Error'Class := Tgt'Access;
   begin
      Assert (As (E, TA), "As must walk to the chain member");
      declare
         CW : constant Error'Class := Tgt;
      begin
         Assert (CW'Tag = Special_Error'Tag, "As assigned the wrong node");
      end;
   end Test_As_Chain_Match;

   procedure Test_As_Tag_Mismatch (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      S  : aliased Special_Error;  --  default-init: tag Special_Error
      TA : constant access Error'Class := S'Access;
   begin
      Assert (not As (New_K ("x"), TA),
              "As must be false when no chain member has the target tag");
   end Test_As_Tag_Mismatch;

   procedure Test_As_Null_Err (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Tgt : aliased Error;
      TA  : constant access Error'Class := Tgt'Access;
   begin
      Assert (not As (No_Error, TA), "As(No_Error, _) = false");
   end Test_As_Null_Err;

end Errors_Suite;
