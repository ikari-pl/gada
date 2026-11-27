--  Body of Gada.Core.Process — see spec for the Go-semantics contract.

with Ada.Text_IO;
with GNAT.OS_Lib;

package body Gada.Core.Process is

   Handler : Exit_Handler := null;

   procedure Set_Exit_Handler (H : Exit_Handler) is
   begin
      Handler := H;
   end Set_Exit_Handler;

   procedure Finish (Code : Integer) is
   begin
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Output);
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);
      if Handler /= null then
         Handler (Code);
      else
         GNAT.OS_Lib.OS_Exit (Code);
      end if;
   end Finish;

   procedure Exit_Main is
   begin
      Finish (0);
   end Exit_Main;

   procedure Unhandled (E : Ada.Exceptions.Exception_Occurrence) is
      Msg : constant String := Ada.Exceptions.Exception_Message (E);
   begin
      --  Standard output first so the report follows whatever main
      --  printed, as with GNAT's last-chance handler.
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Output);
      Ada.Text_IO.New_Line (Ada.Text_IO.Standard_Error);
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "raised " & Ada.Exceptions.Exception_Name (E)
         & (if Msg = "" then "" else " : " & Msg));
      Finish (Panic_Exit_Status);
   end Unhandled;

end Gada.Core.Process;
