with Ada.Characters.Handling;

package body Gada.Std.Encoding.Xml is

   use Ada.Strings.Unbounded;

   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);
   TAB : constant Character := Character'Val (9);

   function Is_Name_Char (C : Character) return Boolean is
     (Ada.Characters.Handling.Is_Alphanumeric (C)
      or C = '_' or C = '-' or C = '.' or C = ':');

   function Escape_Text (S : String) return String is
      Out_S : Unbounded_String;
   begin
      for C of S loop
         case C is
            when '&' => Append (Out_S, "&amp;");
            when '<' => Append (Out_S, "&lt;");
            when '>' => Append (Out_S, "&gt;");
            when ''' => Append (Out_S, "&#39;");
            when '"' => Append (Out_S, "&#34;");
            when TAB => Append (Out_S, "&#x9;");
            when LF => Append (Out_S, "&#xA;");
            when CR => Append (Out_S, "&#xD;");
            when others => Append (Out_S, C);
         end case;
      end loop;
      return To_String (Out_S);
   end Escape_Text;

   --  Parser state -------------------------------------------------------

   type Parser is record
      S   : Unbounded_String;
      Pos : Integer := 1;  --  1-based index into To_String (S)
   end record;

   procedure Skip_Whitespace (P : in out Parser) is
      T : constant String := To_String (P.S);
   begin
      while P.Pos <= T'Last
        and then (T (P.Pos) = ' ' or T (P.Pos) = TAB
                  or T (P.Pos) = LF or T (P.Pos) = CR)
      loop
         P.Pos := P.Pos + 1;
      end loop;
   end Skip_Whitespace;

   function At_End (P : Parser) return Boolean is
     (P.Pos > To_String (P.S)'Last);

   function Peek (P : Parser) return Character is
     (To_String (P.S) (P.Pos));

   procedure Expect (P : in out Parser; C : Character; Msg : String) is
   begin
      if At_End (P) or else Peek (P) /= C then
         raise Constraint_Error with "xml: expected '" & C & "': " & Msg;
      end if;
      P.Pos := P.Pos + 1;
   end Expect;

   --  Skip <?...?>, <!--...--> and <!DOCTYPE ...> / <!...> misc markup.
   procedure Skip_Misc (P : in out Parser) is
      T : constant String := To_String (P.S);
   begin
      loop
         Skip_Whitespace (P);
         if P.Pos + 1 <= T'Last and then T (P.Pos .. P.Pos + 1) = "<?" then
            while P.Pos <= T'Last
              and then not (P.Pos + 1 <= T'Last
                            and then T (P.Pos .. P.Pos + 1) = "?>")
            loop
               P.Pos := P.Pos + 1;
            end loop;
            if P.Pos > T'Last then
               raise Constraint_Error with "xml: unterminated <?...?>";
            end if;
            P.Pos := P.Pos + 2;
         elsif P.Pos + 3 <= T'Last
           and then T (P.Pos .. P.Pos + 3) = "<!--"
         then
            while P.Pos <= T'Last
              and then not (P.Pos + 2 <= T'Last
                            and then T (P.Pos .. P.Pos + 2) = "-->")
            loop
               P.Pos := P.Pos + 1;
            end loop;
            if P.Pos > T'Last then
               raise Constraint_Error with "xml: unterminated comment";
            end if;
            P.Pos := P.Pos + 3;
         elsif not At_End (P) and then Peek (P) = '<'
           and then P.Pos + 1 <= T'Last
           and then (T (P.Pos + 1) = '!' or T (P.Pos + 1) = '?')
           and then not (P.Pos + 3 <= T'Last
                         and then T (P.Pos .. P.Pos + 3) = "<!--")
         then
            --  <!DOCTYPE ...> or other <!...>: skip to '>'.
            while P.Pos <= T'Last and then Peek (P) /= '>' loop
               P.Pos := P.Pos + 1;
            end loop;
            if P.Pos > T'Last then
               raise Constraint_Error with "xml: unterminated <!...>";
            end if;
            P.Pos := P.Pos + 1;
         else
            exit;
         end if;
      end loop;
   end Skip_Misc;

   function Parse_Name (P : in out Parser) return Unbounded_String is
      T    : constant String := To_String (P.S);
      First : Integer := P.Pos;
   begin
      while P.Pos <= T'Last and then Is_Name_Char (T (P.Pos)) loop
         P.Pos := P.Pos + 1;
      end loop;
      if P.Pos = First then
         raise Constraint_Error with "xml: expected name";
      end if;
      return To_Unbounded_String (T (First .. P.Pos - 1));
   end Parse_Name;

   --  Decode one entity reference at P (which points at '&').
   procedure Parse_Entity (P : in out Parser; Out_S : in out Unbounded_String) is
      T : constant String := To_String (P.S);
      J : Integer := P.Pos + 1;
      V : Natural := 0;
      Hex : Boolean := False;
   begin
      if J <= T'Last and then T (J) = '#' then
         J := J + 1;
         if J <= T'Last and then (T (J) = 'x' or T (J) = 'X') then
            Hex := True;
            J := J + 1;
         end if;
         while J <= T'Last and then T (J) /= ';' loop
            if T (J) in '0' .. '9' then
               V := V * (if Hex then 16 else 10) + (Character'Pos (T (J)) - 48);
            elsif Hex and T (J) in 'a' .. 'f' then
               V := V * 16 + (Character'Pos (T (J)) - 87);
            elsif Hex and T (J) in 'A' .. 'F' then
               V := V * 16 + (Character'Pos (T (J)) - 55);
            else
               raise Constraint_Error with "xml: bad character reference";
            end if;
            J := J + 1;
         end loop;
         if J > T'Last then
            raise Constraint_Error with "xml: unterminated reference";
         end if;
         P.Pos := J + 1;
         Append (Out_S, Character'Val (V));
      elsif T'Length >= J + 2 and then T (J .. J + 2) = "lt;" then
         Append (Out_S, '<'); P.Pos := J + 3;
      elsif T'Length >= J + 2 and then T (J .. J + 2) = "gt;" then
         Append (Out_S, '>'); P.Pos := J + 3;
      elsif T'Length >= J + 3 and then T (J .. J + 3) = "amp;" then
         Append (Out_S, '&'); P.Pos := J + 4;
      elsif T'Length >= J + 4 and then T (J .. J + 4) = "quot;" then
         Append (Out_S, '"'); P.Pos := J + 5;
      elsif T'Length >= J + 4 and then T (J .. J + 4) = "apos;" then
         Append (Out_S, '''); P.Pos := J + 5;
      else
         raise Constraint_Error with "xml: unknown entity";
      end if;
   end Parse_Entity;

   --  Read character data until '<' or end; entities decoded.
   function Parse_Text (P : in out Parser) return Unbounded_String is
      T     : constant String := To_String (P.S);
      Out_S : Unbounded_String;
   begin
      while P.Pos <= T'Last and then T (P.Pos) /= '<' loop
         if T (P.Pos) = '&' then
            Parse_Entity (P, Out_S);
         else
            Append (Out_S, T (P.Pos));
            P.Pos := P.Pos + 1;
         end if;
      end loop;
      return Out_S;
   end Parse_Text;

   procedure Parse_Element (P : in out Parser; N : out Node);

   procedure Parse_Attrs (P : in out Parser; N : in out Node) is
      T : constant String := To_String (P.S);
   begin
      loop
         Skip_Whitespace (P);
         exit when At_End (P)
           or else Peek (P) = '>'
           or else (P.Pos + 1 <= T'Last
                    and then T (P.Pos .. P.Pos + 1) = "/>");
         declare
            A : Attr;
            Q : Character;
            V : Unbounded_String;
         begin
            A.Name := Parse_Name (P);
            Skip_Whitespace (P);
            Expect (P, '=', "attribute value");
            Skip_Whitespace (P);
            if At_End (P) or else (Peek (P) /= '"' and Peek (P) /= ''') then
               raise Constraint_Error with "xml: attribute value must be quoted";
            end if;
            Q := Peek (P);
            P.Pos := P.Pos + 1;
            while P.Pos <= T'Last and then T (P.Pos) /= Q loop
               if T (P.Pos) = '&' then
                  Parse_Entity (P, V);
               else
                  Append (V, T (P.Pos));
                  P.Pos := P.Pos + 1;
               end if;
            end loop;
            if P.Pos > T'Last then
               raise Constraint_Error with "xml: unterminated attribute value";
            end if;
            P.Pos := P.Pos + 1;  --  closing quote
            A.Value := V;
            Attr_Vectors.Append (N.Attrs, A);
         end;
      end loop;
   end Parse_Attrs;

   procedure Parse_Element (P : in out Parser; N : out Node) is
      T      : constant String := To_String (P.S);
      Name   : Unbounded_String;
      Closed : Boolean := False;
   begin
      Expect (P, '<', "element start");
      if not At_End (P) and then Peek (P) = '/' then
         raise Constraint_Error with "xml: unexpected </";
      end if;
      Name := Parse_Name (P);
      N := (Kind => Element, Name => Name, Attrs => <>, Children => <>,
            Text => Null_Unbounded_String);
      Parse_Attrs (P, N);
      if P.Pos + 1 <= T'Last and then T (P.Pos .. P.Pos + 1) = "/>" then
         P.Pos := P.Pos + 2;
         return;  --  self-closing
      end if;
      Expect (P, '>', "element content");
      --  Content: text nodes, child elements, comments, CDATA.
      loop
         exit when At_End (P);
         if T (P.Pos) = '<' then
            if P.Pos + 1 <= T'Last
              and then T (P.Pos .. P.Pos + 1) = "</"
            then
               P.Pos := P.Pos + 2;
               declare
                  Close_Name : constant Unbounded_String := Parse_Name (P);
               begin
                  Skip_Whitespace (P);
                  Expect (P, '>', "close tag");
                  if Close_Name /= N.Name then
                     raise Constraint_Error
                       with "xml: mismatched close tag </"
                       & To_String (Close_Name) & "> for <"
                       & To_String (N.Name) & ">";
                  end if;
               end;
               Closed := True;
               exit;
            elsif P.Pos + 3 <= T'Last
              and then T (P.Pos .. P.Pos + 3) = "<!--"
            then
               while P.Pos <= T'Last
                 and then not (P.Pos + 2 <= T'Last
                               and then T (P.Pos .. P.Pos + 2) = "-->")
               loop
                  P.Pos := P.Pos + 1;
               end loop;
               if P.Pos > T'Last then
                  raise Constraint_Error with "xml: unterminated comment";
               end if;
               P.Pos := P.Pos + 3;
            elsif P.Pos + 8 <= T'Last
              and then T (P.Pos .. P.Pos + 8) = "<![CDATA["
            then
               P.Pos := P.Pos + 9;
               declare
                  Cdata : Unbounded_String;
               begin
                  while P.Pos <= T'Last
                    and then not (P.Pos + 2 <= T'Last
                                  and then T (P.Pos .. P.Pos + 2) = "]]>")
                  loop
                     Append (Cdata, T (P.Pos));
                     P.Pos := P.Pos + 1;
                  end loop;
                  if P.Pos > T'Last then
                     raise Constraint_Error with "xml: unterminated CDATA";
                  end if;
                  P.Pos := P.Pos + 3;
                  if Length (Cdata) > 0 then
                     declare
                        Tn : constant Node_Access := new Node;
                     begin
                        Tn.all := (Kind => Text_Node, Name => Null_Unbounded_String,
                                   Attrs => <>, Children => <>,
                                   Text => Cdata);
                        Node_Vectors.Append (N.Children, Tn);
                     end;
                  end if;
               end;
            elsif P.Pos + 1 <= T'Last and then T (P.Pos .. P.Pos + 1) = "<?" then
               while P.Pos <= T'Last
                 and then not (P.Pos + 1 <= T'Last
                               and then T (P.Pos .. P.Pos + 1) = "?>")
               loop
                  P.Pos := P.Pos + 1;
               end loop;
               if P.Pos > T'Last then
                  raise Constraint_Error with "xml: unterminated <?...?>";
               end if;
               P.Pos := P.Pos + 2;
            elsif P.Pos + 1 <= T'Last
              and then T (P.Pos .. P.Pos + 1) = "<!"
            then
               raise Constraint_Error with "xml: markup not allowed inside element";
            else
               declare
                  Child : Node_Access := new Node;
               begin
                  Parse_Element (P, Child.all);
                  Node_Vectors.Append (N.Children, Child);
               end;
            end if;
         else
            declare
               Txt   : constant Unbounded_String := Parse_Text (P);
               Has_T : Boolean := False;
            begin
               for C of To_String (Txt) loop
                  if C /= ' ' and C /= TAB and C /= LF and C /= CR then
                     Has_T := True;
                     exit;
                  end if;
               end loop;
               if Has_T then
                  declare
                     Tn : constant Node_Access := new Node;
                  begin
                     Tn.all := (Kind => Text_Node, Name => Null_Unbounded_String,
                                Attrs => <>, Children => <>,
                                Text => Txt);
                     Node_Vectors.Append (N.Children, Tn);
                  end;
               end if;
            end;
         end if;
      end loop;
      if not Closed then
         raise Constraint_Error
           with "xml: unterminated element <" & To_String (N.Name) & ">";
      end if;
   end Parse_Element;

   function Unmarshal (S : String) return Node is
      P : Parser := (S => To_Unbounded_String (S), Pos => 1);
      Root : Node_Access := new Node;
   begin
      Skip_Misc (P);
      if At_End (P) then
         raise Constraint_Error with "xml: empty document";
      end if;
      if Peek (P) /= '<' then
         raise Constraint_Error with "xml: text outside root element";
      end if;
      Parse_Element (P, Root.all);
      Skip_Misc (P);
      if not At_End (P) then
         raise Constraint_Error with "xml: trailing content after root";
      end if;
      return Root.all;
   end Unmarshal;

   procedure Marshal_Into (N : Node; Out_S : in out Unbounded_String);

   procedure Marshal_Into (N : Node; Out_S : in out Unbounded_String) is
   begin
      case N.Kind is
         when Text_Node =>
            Append (Out_S, Escape_Text (To_String (N.Text)));
         when Element =>
            Append (Out_S, '<');
            Append (Out_S, To_String (N.Name));
            for A of N.Attrs loop
               Append (Out_S, ' ');
               Append (Out_S, To_String (A.Name));
               Append (Out_S, "=""");
               Append (Out_S, Escape_Text (To_String (A.Value)));
               Append (Out_S, '"');
            end loop;
            Append (Out_S, '>');
            for C of N.Children loop
               Marshal_Into (C.all, Out_S);
            end loop;
            Append (Out_S, "</");
            Append (Out_S, To_String (N.Name));
            Append (Out_S, '>');
      end case;
   end Marshal_Into;

   function Marshal (N : Node) return String is
      Out_S : Unbounded_String;
   begin
      Marshal_Into (N, Out_S);
      return To_String (Out_S);
   end Marshal;

end Gada.Std.Encoding.Xml;
