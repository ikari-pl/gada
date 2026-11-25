--  Body of Gada.Std.Bufio — see spec for the Go-semantics contract.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Gada.Std.Errors;
with Gada.Std.IO;

package body Gada.Std.Bufio is

   package Errors renames Gada.Std.Errors;
   package IO renames Gada.Std.IO;

   use type Errors.Error_Access;

   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);

   ---------------------------------------------------------------
   --  Reader
   ---------------------------------------------------------------

   function New_Reader (Source : IO.Reader_Access) return Reader is
     (Source => Source, Buf => Null_Unbounded_String, At_EOF => False);

   --  Pulls one chunk from the source into the buffer. Sets At_EOF on
   --  end of stream; hard errors come back in Err.
   procedure Fill (R : in out Reader; Err : out Errors.Error_Access) is
      Chunk : String (1 .. Buf_Size);
      N     : Natural;
      E     : Errors.Error_Access;
   begin
      Err := Errors.No_Error;
      E := IO.Read (R.Source.all, Chunk, N);
      if N > 0 then
         Append (R.Buf, Chunk (1 .. N));
      end if;
      if E /= Errors.No_Error then
         if Errors.Is_K (E, IO.EOF) then
            R.At_EOF := True;
         else
            Err := E;
         end if;
      end if;
   end Fill;

   procedure Read (R : in out Reader; Data : out String;
                   N : out Natural; Err : out Errors.Error_Access) is
      M : Natural;
   begin
      N := 0;
      Err := Errors.No_Error;
      if Length (R.Buf) = 0 and then not R.At_EOF then
         Fill (R, Err);
         if Err /= Errors.No_Error then
            return;
         end if;
      end if;
      M := Natural'Min (Data'Length, Length (R.Buf));
      if M > 0 then
         for I in 1 .. M loop
            Data (Data'First + I - 1) := Element (R.Buf, I);
         end loop;
         Delete (R.Buf, 1, M);
         N := M;
      end if;
      if N = 0 and then R.At_EOF then
         Err := IO.EOF;
      end if;
   end Read;

   procedure Read_Line (R : in out Reader;
                        Line : out Unbounded_String;
                        Is_Prefix : out Boolean;
                        Err : out Errors.Error_Access) is
      LF_Pos : Integer;
   begin
      Line := Null_Unbounded_String;
      Is_Prefix := False;
      Err := Errors.No_Error;
      loop
         --  Search the buffer for a line feed.
         LF_Pos := 0;
         declare
            B : constant String := To_String (R.Buf);
         begin
            for I in B'Range loop
               if B (I) = LF then
                  LF_Pos := I;
                  exit;
               end if;
            end loop;
            if LF_Pos > 0 then
               Append (Line, B (B'First .. LF_Pos - 1));
               Delete (R.Buf, 1, LF_Pos);
               --  Strip a trailing CR (Go strips CRLF).
               if Length (Line) > 0
                 and then Element (Line, Length (Line)) = CR
               then
                  Line := Head (Line, Length (Line) - 1);
               end if;
               return;
            end if;
         end;
         if R.At_EOF then
            if Length (R.Buf) > 0 then
               --  Final line without a newline: data, no error (the
               --  EOF surfaces on the next call).
               Line := R.Buf;
               R.Buf := Null_Unbounded_String;
            else
               Err := IO.EOF;
            end if;
            return;
         end if;
         if Length (R.Buf) >= Buf_Size then
            --  Line longer than the buffer: hand back a prefix chunk.
            Line := R.Buf;
            R.Buf := Null_Unbounded_String;
            Is_Prefix := True;
            return;
         end if;
         declare
            FE : Errors.Error_Access;
         begin
            Fill (R, FE);
            if FE /= Errors.No_Error then
               Err := FE;
               return;
            end if;
         end;
      end loop;
   end Read_Line;

   procedure Read_String (R : in out Reader; Delim : Character;
                          S : out Unbounded_String;
                          Err : out Errors.Error_Access) is
      P : Integer;
   begin
      S := Null_Unbounded_String;
      Err := Errors.No_Error;
      loop
         P := 0;
         declare
            B : constant String := To_String (R.Buf);
         begin
            for I in B'Range loop
               if B (I) = Delim then
                  P := I;
                  exit;
               end if;
            end loop;
            if P > 0 then
               Append (S, B (B'First .. P));  --  delim included (Go)
               Delete (R.Buf, 1, P);
               return;
            end if;
         end;
         if R.At_EOF then
            --  EOF before the delim: data so far comes back with EOF.
            Append (S, R.Buf);
            R.Buf := Null_Unbounded_String;
            Err := IO.EOF;
            return;
         end if;
         declare
            FE : Errors.Error_Access;
         begin
            Fill (R, FE);
            if FE /= Errors.No_Error then
               Err := FE;
               return;
            end if;
         end;
      end loop;
   end Read_String;

   ---------------------------------------------------------------
   --  Writer
   ---------------------------------------------------------------

   function New_Writer (Dest : IO.Writer_Access) return Writer is
     (Dest => Dest, Buf => Null_Unbounded_String);

   procedure Write_String (W : in out Writer; S : String; N : out Natural;
                           Err : out Errors.Error_Access) is
   begin
      Append (W.Buf, S);
      N := S'Length;
      Err := Errors.No_Error;
      if Length (W.Buf) >= Buf_Size then
         Flush (W, Err);
      end if;
   end Write_String;

   procedure Write (W : in out Writer; Data : String; N : out Natural;
                    Err : out Errors.Error_Access) is
   begin
      Write_String (W, Data, N, Err);
   end Write;

   procedure Flush (W : in out Writer; Err : out Errors.Error_Access) is
      N  : Natural;
      WE : Errors.Error_Access;
   begin
      Err := Errors.No_Error;
      if Length (W.Buf) > 0 then
         WE := IO.Write (W.Dest.all, To_String (W.Buf), N);
         if WE /= Errors.No_Error and then not Errors.Is_K (WE, IO.EOF) then
            Err := WE;
            return;  --  keep the unwritten data buffered
         end if;
         W.Buf := Null_Unbounded_String;
      end if;
   end Flush;

   function Len (W : Writer) return Natural is
     (Length (W.Buf));

   ---------------------------------------------------------------
   --  Scanner (ScanLines)
   ---------------------------------------------------------------

   function New_Scanner (Source : IO.Reader_Access) return Scanner is
     (R   => New_Reader (Source),
      Cur => Null_Unbounded_String,
      E   => Errors.No_Error);

   function Scan (S : in out Scanner) return Boolean is
      Line   : Unbounded_String;
      Prefix : Boolean;
      E      : Errors.Error_Access;
   begin
      S.Cur := Null_Unbounded_String;
      loop
         Read_Line (S.R, Line, Prefix, E);
         Append (S.Cur, Line);
         exit when not Prefix;
      end loop;
      if E /= Errors.No_Error then
         if Errors.Is_K (E, IO.EOF) then
            if Length (S.Cur) = 0 then
               --  Clean end of input: no token, no error (Go's
               --  Scanner.Err() is nil at EOF).
               return False;
            end if;
            return True;  --  final line without a newline
         end if;
         S.E := E;
         return False;
      end if;
      return True;
   end Scan;

   function Text (S : Scanner) return String is
     (To_String (S.Cur));

   function Err (S : Scanner) return Errors.Error_Access is
     (S.E);

end Gada.Std.Bufio;
