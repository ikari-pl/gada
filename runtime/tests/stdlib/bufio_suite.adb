--  Body of Bufio_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Gada.Std.Errors;
with Gada.Std.IO;
with Gada.Std.Bufio; use Gada.Std.Bufio;

package body Bufio_Suite is

   package Errors renames Gada.Std.Errors;
   package IO renames Gada.Std.IO;

   use type Errors.Error_Access;

   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);

   --  Same in-memory doubles as IO_Suite (each suite is standalone).
   type Mem_Reader is new IO.Reader with record
      Data : Unbounded_String;
      Pos  : Natural := 1;
   end record;

   overriding function Read (R : in out Mem_Reader; Data : out String;
                             N : out Natural) return Errors.Error_Access is
      Remaining : constant Natural := Length (R.Data) - R.Pos + 1;
      M         : constant Natural :=
        Natural'Min (Data'Length, Remaining);
   begin
      if Remaining <= 0 then
         N := 0;
         return IO.EOF;
      end if;
      for I in 1 .. M loop
         Data (Data'First + I - 1) := Element (R.Data, R.Pos + I - 1);
      end loop;
      R.Pos := R.Pos + M;
      N := M;
      return Errors.No_Error;
   end Read;

   type Mem_Writer is new IO.Writer with record
      Data : Unbounded_String;
   end record;

   overriding function Write (W : in out Mem_Writer; Data : String;
                              N : out Natural) return Errors.Error_Access is
   begin
      Append (W.Data, Data);
      N := Data'Length;
      return Errors.No_Error;
   end Write;

   type Fail_Reader is new IO.Reader with null record;

   overriding function Read (R : in out Fail_Reader; Data : out String;
                             N : out Natural) return Errors.Error_Access is
      pragma Unreferenced (R, Data);
   begin
      N := 0;
      return Errors.New_K ("read failed");
   end Read;

   type Fail_Writer is new IO.Writer with null record;

   overriding function Write (W : in out Fail_Writer; Data : String;
                              N : out Natural) return Errors.Error_Access is
      pragma Unreferenced (W, Data);
   begin
      N := 0;
      return Errors.New_K ("write failed");
   end Write;

   --  Returns (data, hard error) together once, then clean EOF.
   --  Go: the buffered data comes back with nil error first; the
   --  stored error is delivered once when the buffer drains.
   type Flaky_Reader is new IO.Reader with record
      Data : Unbounded_String;
      Pos  : Natural := 1;
      Boom : Boolean := True;
   end record;

   overriding function Read (R : in out Flaky_Reader; Data : out String;
                             N : out Natural) return Errors.Error_Access is
      Remaining : constant Natural := Length (R.Data) - R.Pos + 1;
      M         : constant Natural :=
        Natural'Min (Data'Length, Remaining);
   begin
      if Remaining <= 0 then
         N := 0;
         return IO.EOF;
      end if;
      for I in 1 .. M loop
         Data (Data'First + I - 1) := Element (R.Data, R.Pos + I - 1);
      end loop;
      R.Pos := R.Pos + M;
      N := M;
      if R.Boom then
         R.Boom := False;
         return Errors.New_K ("boom");
      end if;
      return Errors.No_Error;
   end Read;

   --  Short writer: claims success but writes only half.
   type Short_Writer is new IO.Writer with null record;

   overriding function Write (W : in out Short_Writer; Data : String;
                              N : out Natural) return Errors.Error_Access is
      pragma Unreferenced (W);
   begin
      N := Data'Length / 2;
      return Errors.No_Error;
   end Write;

   --  Fixed-capacity sink: accepts half the bytes and reports io.EOF
   --  (a closed pipe / full device).
   type Eof_Writer is new IO.Writer with record
      Data : Unbounded_String;
   end record;

   overriding function Write (W : in out Eof_Writer; Data : String;
                              N : out Natural) return Errors.Error_Access is
   begin
      N := Data'Length / 2;
      Append (W.Data, Data (Data'First .. Data'First + N - 1));
      return IO.EOF;
   end Write;

   function Buf_Src (S : String) return IO.Reader_Access is
     (new Mem_Reader'(IO.Reader with Data => To_Unbounded_String (S),
                      Pos => 1));

   function Long_Xs (N : Natural) return String is
      R : String (1 .. N);
   begin
      for I in R'Range loop
         R (I) := 'x';
      end loop;
      return R;
   end Long_Xs;

   overriding function Name
     (T : Bufio_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Bufio suite"));

   overriding procedure Register_Tests (T : in out Bufio_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Reader_Read'Access, "Reader chunk reads");
      Register_Routine (T, Test_Read_Line'Access, "ReadLine/CR/EOF");
      Register_Routine (T, Test_Read_Line_Long'Access, "ReadLine prefix");
      Register_Routine (T, Test_Read_String'Access, "ReadString delim/EOF");
      Register_Routine (T, Test_Read_Hard_Error'Access, "hard read error");
      Register_Routine (T, Test_Read_Stored_Error'Access,
                        "stored error delivered once (Go readErr)");
      Register_Routine (T, Test_Read_Line_CRLF_Straddle'Access,
                        "CRLF straddling the buffer boundary");
      Register_Routine (T, Test_Flush_Short_Write'Access,
                        "Flush short write = ErrShortWrite, tail kept");
      Register_Routine (T, Test_Read_Line_Stored_Error'Access,
                        "ReadLine returns buffered data + stored error");
      Register_Routine (T, Test_Read_String_Hard_Error'Access,
                        "ReadString fill error on first call");
      Register_Routine (T, Test_Scanner'Access, "Scanner lines");
      Register_Routine (T, Test_Scanner_Long_And_Error'Access,
                        "Scanner long line + error");
      Register_Routine (T, Test_Writer'Access, "Writer buffer/flush");
   end Register_Tests;

   procedure Test_Reader_Read (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      R   : Reader := New_Reader (Buf_Src ("hello"));
      Buf : String (1 .. 2);
      N   : Natural;
      E   : Errors.Error_Access;
   begin
      Read (R, Buf, N, E);
      Assert (N = 2 and Buf = "he" and E = Errors.No_Error, "chunk 1");
      Read (R, Buf, N, E);
      Assert (N = 2 and Buf = "ll" and E = Errors.No_Error, "chunk 2");
      Read (R, Buf, N, E);
      Assert (N = 1 and Buf (1) = 'o' and E = Errors.No_Error, "chunk 3");
      Read (R, Buf, N, E);
      Assert (N = 0 and Errors.Is_K (E, IO.EOF), "EOF at end");
   end Test_Reader_Read;

   procedure Test_Read_Line (T : in out AUnit.Test_Cases.Test_Case'Class) is
      R    : Reader := New_Reader
        (Buf_Src ("ab" & LF & "cd" & CR & LF & "ef"));
      Line : Unbounded_String;
      Pre  : Boolean;
      E    : Errors.Error_Access;
   begin
      Read_Line (R, Line, Pre, E);
      Assert (To_String (Line) = "ab" and not Pre and E = Errors.No_Error,
              "line 1");
      Read_Line (R, Line, Pre, E);
      Assert (To_String (Line) = "cd" and E = Errors.No_Error,
              "CRLF stripped");
      Read_Line (R, Line, Pre, E);
      Assert (To_String (Line) = "ef" and E = Errors.No_Error,
              "final line without LF");
      Read_Line (R, Line, Pre, E);
      Assert (Length (Line) = 0 and Errors.Is_K (E, IO.EOF),
              "EOF with empty line");
   end Test_Read_Line;

   procedure Test_Read_Line_Long (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      R    : Reader := New_Reader (Buf_Src (Long_Xs (5000) & LF));
      Line : Unbounded_String;
      Pre  : Boolean;
      E    : Errors.Error_Access;
   begin
      Read_Line (R, Line, Pre, E);
      Assert (Pre and Length (Line) = 4096, "prefix chunk of 4096");
      Read_Line (R, Line, Pre, E);
      Assert (not Pre and Length (Line) = 904 and E = Errors.No_Error,
              "rest of the long line");
   end Test_Read_Line_Long;

   procedure Test_Read_String (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      R : Reader := New_Reader (Buf_Src ("key:value;rest"));
      S : Unbounded_String;
      E : Errors.Error_Access;
   begin
      Read_String (R, ':', S, E);
      Assert (To_String (S) = "key:" and E = Errors.No_Error,
              "delim included");
      Read_String (R, ':', S, E);
      Assert (To_String (S) = "value;rest" and Errors.Is_K (E, IO.EOF),
              "EOF before delim returns data + EOF");
      Read_String (R, ':', S, E);
      Assert (Length (S) = 0 and Errors.Is_K (E, IO.EOF), "empty at EOF");
   end Test_Read_String;

   procedure Test_Read_Hard_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      R    : Reader := New_Reader (new Fail_Reader);
      Buf  : String (1 .. 4);
      N    : Natural;
      E    : Errors.Error_Access;
      Line : Unbounded_String;
      Pre  : Boolean;
      S    : Unbounded_String;
   begin
      Read (R, Buf, N, E);
      Assert (N = 0 and E /= Errors.No_Error
              and not Errors.Is_K (E, IO.EOF), "Read hard error");
      Read_Line (R, Line, Pre, E);
      Assert (E /= Errors.No_Error and not Errors.Is_K (E, IO.EOF),
              "ReadLine hard error");
      Read_String (R, ':', S, E);
      Assert (E /= Errors.No_Error and not Errors.Is_K (E, IO.EOF),
              "ReadString hard error");
   end Test_Read_Hard_Error;

   procedure Test_Read_Stored_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      R   : Reader := New_Reader
        (new Flaky_Reader'(IO.Reader with Data => To_Unbounded_String
                             ("abc"),
                           Pos => 1, Boom => True));
      Buf : String (1 .. 8);
      N   : Natural;
      E   : Errors.Error_Access;
   begin
      --  Go: buffered data first with nil error, then the stored hard
      --  error exactly once, then the source's own EOF.
      Read (R, Buf, N, E);
      Assert (N = 3 and E = Errors.No_Error and Buf (1 .. 3) = "abc",
              "data comes back with nil error");
      Read (R, Buf, N, E);
      Assert (N = 0 and then E /= Errors.No_Error
              and then not Errors.Is_K (E, IO.EOF),
              "stored hard error delivered once");
      Read (R, Buf, N, E);
      Assert (N = 0 and Errors.Is_K (E, IO.EOF),
              "then the source's EOF (error was not sticky)");
   end Test_Read_Stored_Error;

   procedure Test_Read_Line_CRLF_Straddle (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      --  4095 x's + CR fill the 4096 buffer exactly; the LF straddles.
      R    : Reader := New_Reader
        (Buf_Src (Long_Xs (4095) & CR & LF));
      Line : Unbounded_String;
      Pre  : Boolean;
      E    : Errors.Error_Access;
   begin
      Read_Line (R, Line, Pre, E);
      Assert (Pre and Length (Line) = 4095 and E = Errors.No_Error,
              "prefix chunk drops the trailing CR");
      Read_Line (R, Line, Pre, E);
      Assert (not Pre and Length (Line) = 0 and E = Errors.No_Error,
              "CRLF pair consumed, no CR leaks into the line");
   end Test_Read_Line_CRLF_Straddle;

   procedure Test_Flush_Short_Write (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Dst : constant IO.Writer_Access := new Short_Writer;
      B   : Writer := New_Writer (Dst);
      N   : Natural;
      E   : Errors.Error_Access;
   begin
      Write_String (B, "hello", N, E);
      Assert (E = Errors.No_Error and Len (B) = 5, "buffered");
      Flush (B, E);
      --  Go: Flush reports io.ErrShortWrite and keeps the unwritten
      --  tail buffered.
      Assert (Errors.Is_K (E, IO.Err_Short_Write),
              "short write = ErrShortWrite");
      Assert (Len (B) = 3, "unwritten tail stays buffered, got"
              & Integer'Image (Len (B)));
      --  Regression (PR #45 review #12): io.EOF from the destination is
      --  a write error too; Flush used to report success and keep the
      --  tail buffered silently.
      declare
         Sink : constant IO.Writer_Access := new Eof_Writer;
         B2   : Writer := New_Writer (Sink);
      begin
         Write_String (B2, "hello", N, E);
         Flush (B2, E);
         Assert (Errors.Is_K (E, IO.EOF), "Flush returns the writer's EOF");
         Assert (Len (B2) = 3, "unwritten tail stays buffered");
         Assert (To_String (Eof_Writer (Sink.all).Data) = "he",
                 "written prefix reached the sink");
      end;
   end Test_Flush_Short_Write;

   procedure Test_Read_Line_Stored_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      --  Flaky_Reader delivers ("abc", boom) together: the fill stores
      --  the error AND buffers the data, so Read_Line returns the data
      --  with the stored error (Go's ReadSlice returns buffer+readErr).
      R    : Reader := New_Reader
        (new Flaky_Reader'(IO.Reader with Data => To_Unbounded_String
                             ("abc"),
                           Pos => 1, Boom => True));
      Line : Unbounded_String;
      Pre  : Boolean;
      E    : Errors.Error_Access;
   begin
      Read_Line (R, Line, Pre, E);
      Assert (To_String (Line) = "abc" and then not Pre
              and then E /= Errors.No_Error
              and then not Errors.Is_K (E, IO.EOF),
              "buffered data + stored hard error");
      Read_Line (R, Line, Pre, E);
      Assert (Length (Line) = 0 and then Errors.Is_K (E, IO.EOF),
              "then clean EOF");
   end Test_Read_Line_Stored_Error;

   procedure Test_Read_String_Hard_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      R : Reader := New_Reader (new Fail_Reader);
      S : Unbounded_String;
      E : Errors.Error_Access;
   begin
      Read_String (R, ':', S, E);
      Assert (E /= Errors.No_Error and then not Errors.Is_K (E, IO.EOF),
              "ReadString first-call fill error");
   end Test_Read_String_Hard_Error;

   procedure Test_Scanner (T : in out AUnit.Test_Cases.Test_Case'Class) is
      S : Scanner := New_Scanner
        (Buf_Src ("one" & LF & "two" & LF & "three"));
   begin
      Assert (Scan (S) and Text (S) = "one", "token 1");
      Assert (Scan (S) and Text (S) = "two", "token 2");
      Assert (Scan (S) and Text (S) = "three", "final token w/o LF");
      Assert (not Scan (S), "clean EOF");
      Assert (Err (S) = Errors.No_Error, "Err nil at clean EOF");
      --  Regression (PR #45 review #16): Go drops one trailing CR from
      --  a final line ended by EOF ("a\r\nb\r" -> "a", "b"); only one
      --  ("a\r\r\nb\r\r" -> "a\r", "b\r"). Go-verified.
      declare
         C : Scanner := New_Scanner (Buf_Src ("a" & CR & LF & "b" & CR));
      begin
         Assert (Scan (C) and then Text (C) = "a", "CRLF line");
         Assert (Scan (C) and then Text (C) = "b", "CR dropped at EOF");
         Assert (not Scan (C), "then EOF");
      end;
      declare
         C : Scanner := New_Scanner
           (Buf_Src ("a" & CR & CR & LF & "b" & CR & CR));
      begin
         Assert (Scan (C) and then Text (C) = "a" & CR, "one CR kept");
         Assert (Scan (C) and then Text (C) = "b" & CR,
                 "only one CR dropped at EOF");
      end;
      --  ReadLine itself keeps a final CR that has no LF (Go).
      declare
         R    : Reader := New_Reader (Buf_Src ("b" & CR));
         Line : Unbounded_String;
         Pre  : Boolean;
         E    : Errors.Error_Access;
      begin
         Read_Line (R, Line, Pre, E);
         Assert (To_String (Line) = "b" & CR, "ReadLine keeps lone CR");
      end;
   end Test_Scanner;

   procedure Test_Scanner_Long_And_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      S : Scanner := New_Scanner (Buf_Src (Long_Xs (5000) & LF));
   begin
      Assert (Scan (S) and then Text (S)'Length = 5000,
              "long line reassembled from prefixes");
      Assert (not Scan (S), "then EOF");
      declare
         F : Scanner := New_Scanner (new Fail_Reader);
      begin
         Assert (not Scan (F), "hard error stops Scan");
         Assert (Err (F) /= Errors.No_Error, "Err set");
      end;
   end Test_Scanner_Long_And_Error;

   procedure Test_Writer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Dst : constant IO.Writer_Access := new Mem_Writer;
      B   : Writer := New_Writer (Dst);
      N   : Natural;
      E   : Errors.Error_Access;
   begin
      Write_String (B, "abc", N, E);
      Assert (N = 3 and E = Errors.No_Error and Len (B) = 3,
              "buffered write");
      Assert (Length (Mem_Writer (Dst.all).Data) = 0,
              "nothing flushed yet");
      Flush (B, E);
      Assert (E = Errors.No_Error and Len (B) = 0, "flush clears");
      Assert (To_String (Mem_Writer (Dst.all).Data) = "abc",
              "flushed content");
      Flush (B, E);
      Assert (E = Errors.No_Error, "flush of empty buffer is a no-op");
      --  Auto-flush when the buffer fills.
      Write (B, Long_Xs (5000), N, E);
      Assert (N = 5000 and E = Errors.No_Error, "big write ok");
      Assert (Length (Mem_Writer (Dst.all).Data) = 3 + 5000,
              "auto-flushed at 4096");
      --  Flush error keeps the data buffered and reports the error.
      declare
         F  : constant IO.Writer_Access := new Fail_Writer;
         B2 : Writer := New_Writer (F);
      begin
         Write_String (B2, Long_Xs (5000), N, E);
         Assert (E /= Errors.No_Error and not Errors.Is_K (E, IO.EOF),
                 "flush error reported");
         Assert (Len (B2) = 5000, "unwritten data stays buffered");
      end;
   end Test_Writer;

end Bufio_Suite;
