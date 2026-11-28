with Ada.Strings.Unbounded;

package body Gada.Std.Encoding.Csv is

   use Ada.Strings.Unbounded;

   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);

   --  Parse one record starting at Pos; on return Pos is just past the
   --  record terminator (or S'Last + 1 at end of input). Raises
   --  Constraint_Error on malformed input.
   procedure Parse_Record
     (S : String; Pos : in out Integer; Rec : in out Row);

   function Needs_Quote (Field : String) return Boolean is
     (for some C of Field => C = ',' or C = '"' or C = LF or C = CR);

   procedure Parse_Record
     (S : String; Pos : in out Integer; Rec : in out Row)
   is
      Buf    : Unbounded_String;
      Done   : Boolean := False;
      Quoted : Boolean;
   begin
      Gada.Std.Strings.String_Vectors.Clear (Rec);
      loop
         --  One field.
         Buf := Null_Unbounded_String;
         Quoted := True;
         if Pos <= S'Last and then S (Pos) = '"' then
            --  Quoted field.
            Pos := Pos + 1;
            loop
               if Pos > S'Last then
                  raise Constraint_Error with "csv: unterminated quoted field";
               end if;
               if S (Pos) = '"' then
                  if Pos + 1 <= S'Last and then S (Pos + 1) = '"' then
                     Append (Buf, '"');
                     Pos := Pos + 2;
                  else
                     Pos := Pos + 1;
                     exit;  --  closing quote
                  end if;
               else
                  Append (Buf, S (Pos));
                  Pos := Pos + 1;
               end if;
            end loop;
            --  After the closing quote only ',', a line end or EOF is legal.
            if Pos <= S'Last
              and then S (Pos) /= ','
              and then S (Pos) /= LF
              and then S (Pos) /= CR
            then
               raise Constraint_Error with "csv: extraneous data after quote";
            end if;
         else
            --  Unquoted field: runs to ',', LF or EOF. A CR is kept in
            --  the field (Go semantics); a CR directly before the LF
            --  terminator is stripped below.
            Quoted := False;  --  (declared above; unquoted field)
            while Pos <= S'Last
              and then S (Pos) /= ','
              and then S (Pos) /= LF
            loop
               Append (Buf, S (Pos));
               Pos := Pos + 1;
            end loop;
         end if;
         Gada.Std.Strings.String_Vectors.Append (Rec, Buf);

         if Pos > S'Last then
            Done := True;  --  EOF terminates the record
         elsif S (Pos) = ',' then
            Pos := Pos + 1;  --  another field follows
         elsif S (Pos) = LF then
            Pos := Pos + 1;
            if not Quoted
              and then Ada.Strings.Unbounded.Length (Buf) > 0
              and then Ada.Strings.Unbounded.Element
                (Buf, Ada.Strings.Unbounded.Length (Buf)) = CR
            then
               Ada.Strings.Unbounded.Delete_Last (Buf);
               Gada.Std.Strings.String_Vectors.Replace_Element
                 (Rec,
                  Positive (Gada.Std.Strings.String_Vectors.Length (Rec)),
                  Buf);
            end if;
            Done := True;
         elsif S (Pos) = CR then
            if Pos + 1 <= S'Last and then S (Pos + 1) = LF then
               Pos := Pos + 2;
            else
               Pos := Pos + 1;
            end if;
            Done := True;
         end if;
         exit when Done;
      end loop;
   end Parse_Record;

   function Read_All (S : String) return Row_List is
      Result  : Row_List;
      Pos     : Integer := S'First;
      Rec     : Row;
      N_Fields : Natural := 0;
   begin
      if S'Length = 0 then
         return Result;
      end if;
      loop
         --  Go's reader ignores blank lines.
         if Pos <= S'Last and then S (Pos) = LF then
            Pos := Pos + 1;
         elsif Pos + 1 <= S'Last
           and then S (Pos) = CR and then S (Pos + 1) = LF
         then
            Pos := Pos + 2;
         else
            Parse_Record (S, Pos, Rec);
            declare
               N : constant Natural :=
                 Natural (Gada.Std.Strings.String_Vectors.Length (Rec));
            begin
               if N_Fields = 0 then
                  N_Fields := N;
               elsif N /= N_Fields then
                  raise Constraint_Error
                    with "csv: record field count mismatch";
               end if;
            end;
            Row_Vectors.Append (Result, Rec);
         end if;
         exit when Pos > S'Last;
      end loop;
      return Result;
   end Read_All;

   function Write_All (Records : Row_List) return String is
      Out_S : Unbounded_String;
   begin
      for Rec of Records loop
         for I in
           1 .. Natural (Gada.Std.Strings.String_Vectors.Length (Rec))
         loop
            if I > 1 then
               Append (Out_S, ',');
            end if;
            declare
               F : constant String :=
                 To_String (Gada.Std.Strings.String_Vectors.Element (Rec, I));
            begin
               if Needs_Quote (F) then
                  Append (Out_S, '"');
                  for C of F loop
                     if C = '"' then
                        Append (Out_S, '"');
                     end if;
                     Append (Out_S, C);
                  end loop;
                  Append (Out_S, '"');
               else
                  Append (Out_S, F);
               end if;
            end;
         end loop;
         Append (Out_S, LF);
      end loop;
      return To_String (Out_S);
   end Write_All;

end Gada.Std.Encoding.Csv;
