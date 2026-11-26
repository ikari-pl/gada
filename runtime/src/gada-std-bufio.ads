--  Gada.Std.Bufio — the Go `bufio` package, ported (Phase 5 wave 1).
--
--  Reader/Writer buffer an IO.Reader / IO.Writer (the abstract tagged
--  interfaces from Gada.Std.IO) with a 4096-byte buffer, exactly like
--  Go's defaults. Scanner is Go's bufio.Scanner in ScanLines mode
--  (v1): one token per line, trailing CR/LF stripped, a final line
--  without a newline is still a token, clean EOF is not an error.
--
--  ReadLine's Is_Prefix is True when a line exceeds the buffer (Go's
--  contract); Scanner accumulates prefix pieces into one token.

with Ada.Strings.Unbounded;
with Gada.Std.Errors;
with Gada.Std.IO;

package Gada.Std.Bufio is

   ---------------------------------------------------------------
   --  Reader — buffered reader over an IO.Reader (Go's bufio.Reader)
   ---------------------------------------------------------------

   type Reader is tagged private;

   function New_Reader (Source : Gada.Std.IO.Reader_Access) return Reader;

   --  Go: Read(p []byte) (n int, err error) — buffered chunk read;
   --  (0, EOF) at end of stream.
   procedure Read (R : in out Reader; Data : out String;
                   N : out Natural;
                   Err : out Gada.Std.Errors.Error_Access);

   --  Go: ReadLine() (line []byte, isPrefix bool, err error) — line
   --  without the end-of-line bytes; (empty, false, EOF) at end.
   procedure Read_Line (R : in out Reader;
                        Line : out Ada.Strings.Unbounded.Unbounded_String;
                        Is_Prefix : out Boolean;
                        Err : out Gada.Std.Errors.Error_Access);

   --  Go: ReadString(delim byte) (string, error) — delim included;
   --  at EOF before the delim the data read so far comes back with EOF.
   procedure Read_String (R : in out Reader; Delim : Character;
                          S : out Ada.Strings.Unbounded.Unbounded_String;
                          Err : out Gada.Std.Errors.Error_Access);

   ---------------------------------------------------------------
   --  Writer — buffered writer over an IO.Writer (Go's bufio.Writer)
   ---------------------------------------------------------------

   type Writer is tagged private;

   function New_Writer (Dest : Gada.Std.IO.Writer_Access) return Writer;

   --  Go: Write(p []byte) (n int, err error) — buffered; auto-flushes
   --  when the buffer fills.
   procedure Write (W : in out Writer; Data : String; N : out Natural;
                    Err : out Gada.Std.Errors.Error_Access);
   procedure Write_String (W : in out Writer; S : String; N : out Natural;
                           Err : out Gada.Std.Errors.Error_Access);
   procedure Flush (W : in out Writer;
                    Err : out Gada.Std.Errors.Error_Access);
   function Len (W : Writer) return Natural;

   ---------------------------------------------------------------
   --  Scanner — Go's bufio.Scanner, ScanLines mode (v1)
   ---------------------------------------------------------------

   type Scanner is tagged private;

   function New_Scanner (Source : Gada.Std.IO.Reader_Access) return Scanner;
   function Scan (S : in out Scanner) return Boolean;
   function Text (S : Scanner) return String;
   function Err (S : Scanner) return Gada.Std.Errors.Error_Access;

private

   Buf_Size : constant := 4096;

   type Reader is tagged record
      Source : Gada.Std.IO.Reader_Access;
      Buf    : Ada.Strings.Unbounded.Unbounded_String;
      At_EOF : Boolean := False;
      --  Go's b.err: a hard read error from the source, delivered once
      --  (Go's readErr clears it) when the buffer drains.
      Saved_Err : Gada.Std.Errors.Error_Access := Gada.Std.Errors.No_Error;
   end record;

   type Writer is tagged record
      Dest : Gada.Std.IO.Writer_Access;
      Buf  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Scanner is tagged record
      R   : Reader;
      Cur : Ada.Strings.Unbounded.Unbounded_String;
      E   : Gada.Std.Errors.Error_Access;
   end record;

end Gada.Std.Bufio;
