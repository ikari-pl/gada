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

   function Capture (Op : access procedure) return String;
   --  Run Op with the default output redirected to a temp file, restore
   --  the original output, and return the captured bytes. Op is an
   --  anonymous access-to-procedure so a test's nested print sequence
   --  can be passed by 'Access; it is invoked directly (no libco), so
   --  the static link is valid. The temp file is deleted before return.

   function Capture (Op : access procedure) return String is
      Tmp_Path : constant String := Ada.Directories.Compose
        (Containing_Directory => Ada.Directories.Current_Directory,
         Name                 => "gada_io_capture",
         Extension            => "out");

      File  : Ada.Text_IO.File_Type;
      Saved : constant Ada.Text_IO.File_Access :=
        Ada.Text_IO.Current_Output;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Tmp_Path);
      Ada.Text_IO.Set_Output (File);

      --  If Op raises, restore the default output *before* propagating —
      --  otherwise Current_Output is left pointing at this (closing)
      --  file and every later test fails with Status_Error. (PR #24
      --  review.)
      begin
         Op.all;
      exception
         when others =>
            Ada.Text_IO.Set_Output (Saved.all);
            Ada.Text_IO.Close (File);
            raise;
      end;

      Ada.Text_IO.Flush (File);
      Ada.Text_IO.Set_Output (Saved.all);
      Ada.Text_IO.Close (File);

      return Result : constant String := Read_File_Contents (Tmp_Path) do
         begin
            Ada.Directories.Delete_File (Tmp_Path);
         exception
            when others =>
               null;
         end;
      end return;
   end Capture;

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

   --  NOTE on capture: Ada.Text_IO appends a line terminator when a
   --  file is closed on an unterminated line, so a bare Print (no
   --  New_Line) cannot be distinguished from Print+LF through the
   --  file-capture path. Every sequence below therefore ends in
   --  New_Line — which collapses to exactly one LF on close (the same
   --  property Test_Println_Hello relies on) — and asserts the content
   --  plus that single LF. Adjacency of two Prints proves Print adds no
   --  terminator of its own; this is also exactly how the compiler
   --  emits multi-arg fmt.Println (a run of Print ending in New_Line).
   procedure Test_Print_String_No_Newline
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      procedure Op;
      procedure Op is
      begin
         Gada.Core.IO.Print ("a");
         Gada.Core.IO.Print ("b");
         Gada.Core.IO.New_Line;
      end Op;
   begin
      --  "ab" & LF, not "a\nb\n": Print writes its text and nothing more.
      AUnit.Assertions.Assert
        (Capture (Op'Access) = "ab" & Ada.Characters.Latin_1.LF,
         "Print (String) must emit just the text, no terminator");
   end Test_Print_String_No_Newline;

   procedure Test_Print_Integer_Trims_Leading_Blank
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      procedure Op;
      procedure Op is
      begin
         Gada.Core.IO.Print (1_000_000);
         Gada.Core.IO.New_Line;
      end Op;
   begin
      --  Integer'Image (1_000_000) is " 1000000"; Print must drop the
      --  leading blank so the bytes are Go's bare "1000000".
      AUnit.Assertions.Assert
        (Capture (Op'Access) = "1000000" & Ada.Characters.Latin_1.LF,
         "Print (Integer) must drop Image's leading sign-position blank");
   end Test_Print_Integer_Trims_Leading_Blank;

   procedure Test_Print_Integer_Negative
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      procedure Op;
      procedure Op is
      begin
         Gada.Core.IO.Print (-42);
         Gada.Core.IO.New_Line;
      end Op;
   begin
      --  Negative values have no leading blank to trim; the '-' stays.
      AUnit.Assertions.Assert
        (Capture (Op'Access) = "-42" & Ada.Characters.Latin_1.LF,
         "Print (Integer) keeps the minus sign on negative values");
   end Test_Print_Integer_Negative;

   procedure Test_New_Line_Emits_LF
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      procedure Op;
      procedure Op is
      begin
         Gada.Core.IO.New_Line;
      end Op;
   begin
      AUnit.Assertions.Assert
        (Capture (Op'Access) = (1 => Ada.Characters.Latin_1.LF),
         "New_Line must emit exactly one LF");
   end Test_New_Line_Emits_LF;

   --------------------------------------------------------------------
   --  AUnit registration plumbing
   --------------------------------------------------------------------

   overriding procedure Register_Tests (T : in out IO_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Println_Hello'Access,
         "Gada.Core.IO.Println emits 'hello, GADA' + LF");
      Register_Routine
        (T, Test_Print_String_No_Newline'Access,
         "Gada.Core.IO.Print (String) writes text with no terminator");
      Register_Routine
        (T, Test_Print_Integer_Trims_Leading_Blank'Access,
         "Gada.Core.IO.Print (Integer) renders bare digits (no leading "
         & "blank)");
      Register_Routine
        (T, Test_Print_Integer_Negative'Access,
         "Gada.Core.IO.Print (Integer) keeps the minus sign on negatives");
      Register_Routine
        (T, Test_New_Line_Emits_LF'Access,
         "Gada.Core.IO.New_Line emits exactly one LF");
   end Register_Tests;

   overriding function Name (T : IO_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Gada.Core.IO suite");
   end Name;

end IO_Suite;
