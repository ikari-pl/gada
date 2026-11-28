--  Body of Process_Suite — see spec for test rationale.

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Core.Process;

package body Process_Suite is

   package Process renames Gada.Core.Process;

   Exit_Called : exception;
   Last_Code   : Integer := -1;

   procedure Record_Exit (Code : Integer) is
   begin
      Last_Code := Code;
      raise Exit_Called;
   end Record_Exit;

   --  A handler that returns: Finish and Exit_Main then return too
   --  (only the OS_Exit default never returns).
   procedure Record_Only (Code : Integer) is
   begin
      Last_Code := Code;
   end Record_Only;

   overriding function Name
     (T : Process_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Core.Process suite"));

   overriding procedure Register_Tests (T : in out Process_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Exit_Main'Access, "Exit_Main exits 0");
      Register_Routine
        (T, Test_Unhandled'Access, "Unhandled reports and exits 2");
      Register_Routine (T, Test_Finish_Code'Access, "Finish passes code");
   end Register_Tests;

   procedure Test_Exit_Main (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Process.Set_Exit_Handler (Record_Exit'Access);
      Last_Code := -1;
      begin
         Process.Exit_Main;
         Assert (False, "Exit_Main must not return");
      exception
         when Exit_Called =>
            null;
      end;
      Process.Set_Exit_Handler (Record_Only'Access);
      Last_Code := -1;
      Process.Exit_Main;
      Process.Set_Exit_Handler (null);
      Assert (Last_Code = 0, "main return exits 0");
   end Test_Exit_Main;

   procedure Test_Unhandled (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Process.Set_Exit_Handler (Record_Exit'Access);
      for With_Message in Boolean loop
         Last_Code := -1;
         begin
            begin
               if With_Message then
                  raise Constraint_Error with "process_suite: expected";
               else
                  raise Constraint_Error with "";
               end if;
            exception
               when E : Constraint_Error =>
                  Process.Unhandled (E);
            end;
            Assert (False, "Unhandled must not return");
         exception
            when Exit_Called =>
               null;
         end;
         Assert (Last_Code = Process.Panic_Exit_Status,
                 "unrecovered panic exits 2");
      end loop;
      Process.Set_Exit_Handler (null);
   end Test_Unhandled;

   procedure Test_Finish_Code (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Process.Set_Exit_Handler (Record_Exit'Access);
      begin
         Process.Finish (7);
      exception
         when Exit_Called =>
            null;
      end;
      Process.Set_Exit_Handler (null);
      Assert (Last_Code = 7, "Finish forwards the status");
   end Test_Finish_Code;

end Process_Suite;
