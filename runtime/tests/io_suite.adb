--  IO_Suite body — captures stdout via Ada.Text_IO.Set_Output and
--  asserts that `Gada.Core.IO.Println` emits the expected bytes.
--
--  Capture strategy: we open a temp file for write, point
--  `Ada.Text_IO`'s default output at it, run the unit under test, flush,
--  restore the original default output, then read the temp file back as
--  a `String` and compare. This is intentionally low-tech - building
--  an in-memory `Root_Stream_Type` would work but adds machinery that
--  obscures what is otherwise a 30-line smoke test.

with Ada.Characters.Latin_1;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;

with AUnit.Assertions;
--  AUnit.Test_Cases is already withed transitively through the spec; the
--  nested package AUnit.Test_Cases.Registration becomes visible via the
--  `use` clause inside Register_Tests below.

with Gada.Core.IO;

package body IO_Suite is

   --------------------------------------------------------------------
   --  Helpers
   --------------------------------------------------------------------

   function Read_File_Contents (Path : String) return String;
   --  Read the entire byte contents of `Path` and return them as a String.
   --  Implemented via Stream_IO so the trailing LF written by `Put_Line`
   --  is preserved (Ada.Text_IO collapses the final line+file-terminator
   --  pair, which loses the LF).

   function Read_File_Contents (Path : String) return String is
      use Ada.Streams;
      use Ada.Streams.Stream_IO;

      F      : File_Type;
      Buffer : Stream_Element_Array (1 .. 4096);
      Last   : Stream_Element_Offset;
      Result : String (1 .. 4096);
   begin
      Open (F, In_File, Path);
      Read (F, Buffer, Last);
      Close (F);

      for I in 1 .. Last loop
         Result (Natural (I)) := Character'Val (Buffer (I));
      end loop;
      return Result (1 .. Natural (Last));
   end Read_File_Contents;

   --------------------------------------------------------------------
   --  Tests
   --------------------------------------------------------------------

   procedure Test_Println_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Tmp_Path : constant String := Ada.Directories.Compose
        (Containing_Directory => Ada.Directories.Current_Directory,
         Name                 => "gada_println_hello",
         Extension            => "out");

      Capture : Ada.Text_IO.File_Type;
      Saved   : constant Ada.Text_IO.File_Access :=
        Ada.Text_IO.Current_Output;

      Expected : constant String :=
        "hello, GADA" & Ada.Characters.Latin_1.LF;
   begin
      --  Redirect default output to a temp file.
      Ada.Text_IO.Create (Capture, Ada.Text_IO.Out_File, Tmp_Path);
      Ada.Text_IO.Set_Output (Capture);

      --  Unit under test.
      Gada.Core.IO.Println ("hello, GADA");

      --  Flush and restore default output BEFORE asserting, so a failed
      --  assertion message is not itself swallowed by the redirect.
      Ada.Text_IO.Flush (Capture);
      Ada.Text_IO.Set_Output (Saved.all);
      Ada.Text_IO.Close (Capture);

      declare
         Got : constant String := Read_File_Contents (Tmp_Path);
      begin
         AUnit.Assertions.Assert
           (Got = Expected,
            "Gada.Core.IO.Println output mismatch: expected ["
            & Expected & "] got [" & Got & "]");
      end;

      --  Cleanup; ignore failure.
      begin
         Ada.Directories.Delete_File (Tmp_Path);
      exception
         when others => null;
      end;
   end Test_Println_Hello;

   --------------------------------------------------------------------
   --  AUnit registration plumbing
   --------------------------------------------------------------------

   overriding procedure Register_Tests (T : in out IO_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Println_Hello'Access,
         "Gada.Core.IO.Println emits 'hello, GADA' + LF");
   end Register_Tests;

   overriding function Name (T : IO_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Gada.Core.IO suite");
   end Name;

end IO_Suite;
