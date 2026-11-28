--  Body of Std_Encoding_Text_Suite — see spec. All expected values
--  pinned from Go 1.27 via `go run` (JSON vectors in the commit history
--  of the generator script used to produce them).

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Ada.Containers; use type Ada.Containers.Count_Type;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Gada.Std.Strings; use Gada.Std.Strings;
with Gada.Std.Encoding.Csv; use Gada.Std.Encoding.Csv;
with Gada.Std.Encoding.Xml; use Gada.Std.Encoding.Xml;

package body Std_Encoding_Text_Suite is

   overriding function Name
     (T : Std_Encoding_Text_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Encoding.Csv/Xml suite (PKG=stdlib.encoding.text)"));

   overriding procedure Register_Tests (T : in out Std_Encoding_Text_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Csv_Read'Access, "csv read vectors");
      Register_Routine (T, Test_Csv_Write'Access, "csv write vectors");
      Register_Routine (T, Test_Csv_Errors'Access, "csv field-count error");
      Register_Routine (T, Test_Xml_Escape'Access, "xml EscapeText vectors");
      Register_Routine (T, Test_Xml_Unmarshal'Access, "xml tree shape");
      Register_Routine (T, Test_Xml_Marshal'Access, "xml canonical marshal");
      Register_Routine (T, Test_Xml_Errors'Access, "xml malformed docs raise");
   end Register_Tests;

   --  Row / Row_List builders (arity overloads).
   function Rec (A : String) return Row is
      R : Row;
   begin
      String_Vectors.Append (R, To_Unbounded_String (A));
      return R;
   end Rec;

   function Rec (A, B : String) return Row is
      R : Row;
   begin
      String_Vectors.Append (R, To_Unbounded_String (A));
      String_Vectors.Append (R, To_Unbounded_String (B));
      return R;
   end Rec;

   function Rec (A, B, C : String) return Row is
      R : Row;
   begin
      String_Vectors.Append (R, To_Unbounded_String (A));
      String_Vectors.Append (R, To_Unbounded_String (B));
      String_Vectors.Append (R, To_Unbounded_String (C));
      return R;
   end Rec;

   function Rec (A, B, C, D : String) return Row is
      R : Row;
   begin
      String_Vectors.Append (R, To_Unbounded_String (A));
      String_Vectors.Append (R, To_Unbounded_String (B));
      String_Vectors.Append (R, To_Unbounded_String (C));
      String_Vectors.Append (R, To_Unbounded_String (D));
      return R;
   end Rec;

   function Rec (A, B, C, D, E : String) return Row is
      R : Row;
   begin
      String_Vectors.Append (R, To_Unbounded_String (A));
      String_Vectors.Append (R, To_Unbounded_String (B));
      String_Vectors.Append (R, To_Unbounded_String (C));
      String_Vectors.Append (R, To_Unbounded_String (D));
      String_Vectors.Append (R, To_Unbounded_String (E));
      return R;
   end Rec;

   function Recs (R1 : Row) return Row_List is
      L : Row_List;
   begin
      Row_Vectors.Append (L, R1);
      return L;
   end Recs;

   function Recs (R1, R2 : Row) return Row_List is
      L : Row_List;
   begin
      Row_Vectors.Append (L, R1);
      Row_Vectors.Append (L, R2);
      return L;
   end Recs;

   procedure Assert_Rec (Got, Want : Row; Msg : String) is
   begin
      Assert (String_Vectors.Length (Got) = String_Vectors.Length (Want),
              Msg & ": field count");
      for I in 1 .. Natural (String_Vectors.Length (Want)) loop
         Assert (String_Vectors.Element (Got, I) = String_Vectors.Element (Want, I),
                 Msg & ": field" & Integer'Image (I));
      end loop;
   end Assert_Rec;


   procedure Test_Csv_Read (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin

      --  CSV doc 0
      declare
         L : constant Row_List := Read_All ("a,b,c" & LF & "1,2,3" & LF & "");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 2, "csv0: record count");
         Assert_Rec (Row_Vectors.Element (L, 1), Rec ("a", "b", "c"), "csv0 rec1");
         Assert_Rec (Row_Vectors.Element (L, 2), Rec ("1", "2", "3"), "csv0 rec2");
      end;
      --  CSV doc 1
      declare
         L : constant Row_List := Read_All ("name,quote,note" & LF &
         """Doe, John"",""say """"hi"""""",""li" & "ne1" & LF & "line2""" & LF & "");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 2, "csv1: record count");
         Assert_Rec (Row_Vectors.Element (L, 1), Rec ("name", "quote", "note"), "csv1 rec1");
         Assert_Rec (Row_Vectors.Element (L, 2), Rec ("Doe, John", "say ""hi""", "line1" & LF &
         "line2"), "csv1 rec2");
      end;
      --  CSV doc 2
      declare
         L : constant Row_List := Read_All ("a,,c" & LF & ",," & LF & "");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 2, "csv2: record count");
         Assert_Rec (Row_Vectors.Element (L, 1), Rec ("a", "", "c"), "csv2 rec1");
         Assert_Rec (Row_Vectors.Element (L, 2), Rec ("", "", ""), "csv2 rec2");
      end;
      --  CSV doc 3
      declare
         L : constant Row_List := Read_All ("""""" & LF & "");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 1, "csv3: record count");
         Assert_Rec (Row_Vectors.Element (L, 1), Rec (""), "csv3 rec1");
      end;
      --  CSV doc 4
      declare
         L : constant Row_List := Read_All ("single" & LF & "");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 1, "csv4: record count");
         Assert_Rec (Row_Vectors.Element (L, 1), Rec ("single"), "csv4 rec1");
      end;
      --  CSV doc 5
      declare
         L : constant Row_List := Read_All ("a,b" & CR & "" & LF & "c,d" & CR & "" & LF & "");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 2, "csv5: record count");
         Assert_Rec (Row_Vectors.Element (L, 1), Rec ("a", "b"), "csv5 rec1");
         Assert_Rec (Row_Vectors.Element (L, 2), Rec ("c", "d"), "csv5 rec2");
      end;
      --  CSV doc 6
      declare
         L : constant Row_List := Read_All ("""multi" & LF & "line"",x" & LF & "");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 1, "csv6: record count");
         Assert_Rec (Row_Vectors.Element (L, 1), Rec ("multi" & LF & "line", "x"), "csv6 rec1");
      end;
      --  CSV doc 8
      declare
         L : constant Row_List := Read_All ("");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 0, "csv8: record count");
      end;
      --  CSV doc 9
      declare
         L : constant Row_List := Read_All ("a,b");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 1, "csv9: record count");
         Assert_Rec (Row_Vectors.Element (L, 1), Rec ("a", "b"), "csv9 rec1");
      end;
      --  CSV doc 10
      declare
         L : constant Row_List := Read_All ("a,b" & LF & "" & LF & "c,d" & LF & "");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 2, "csv10: record count");
         Assert_Rec (Row_Vectors.Element (L, 1), Rec ("a", "b"), "csv10 rec1");
         Assert_Rec (Row_Vectors.Element (L, 2), Rec ("c", "d"), "csv10 rec2");
      end;
      --  CSV doc 11
      declare
         L : constant Row_List := Read_All ("" & CR & "" & LF & "");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 0, "csv11: record count");
      end;
      --  CSV doc 14
      declare
         L : constant Row_List := Read_All ("""q"",x" & CR & "" & LF & "z,w" & LF & "");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 2, "csv14: record count");
         Assert_Rec (Row_Vectors.Element (L, 1), Rec ("q", "x"), "csv14 rec1");
         Assert_Rec (Row_Vectors.Element (L, 2), Rec ("z", "w"), "csv14 rec2");
      end;
      --  CSV doc 15
      declare
         L : constant Row_List := Read_All ("""a""" & CR & "" & LF & "b" & LF & "");
      begin
         Assert (Natural (Row_Vectors.Length (L)) = 2, "csv15: record count");
         Assert_Rec (Row_Vectors.Element (L, 1), Rec ("a"), "csv15 rec1");
         Assert_Rec (Row_Vectors.Element (L, 2), Rec ("b"), "csv15 rec2");
      end;
   end Test_Csv_Read;


   procedure Test_Csv_Write (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin

      Assert (Write_All (Read_All ("a,b,c" & LF & "1,2,3" & LF & "")) = "a,b,c" & LF & "1,2,3" & LF
         & "", "csv0: write round-trip");
      Assert (Write_All (Read_All ("name,quote,note" & LF & """Doe, John"",""say """"hi"""""",""li"
         & "ne1" & LF & "line2""" & LF & "")) = "name,quote,note" & LF &
         """Doe, John"",""say """"hi"""""",""li" & "ne1" & LF & "line2""" & LF & "",
         "csv1: write round-trip");
      Assert (Write_All (Read_All ("a,,c" & LF & ",," & LF & "")) = "a,,c" & LF & ",," & LF & "",
         "csv2: write round-trip");
      Assert (Write_All (Read_All ("""""" & LF & "")) = "" & LF & "", "csv3: write round-trip");
      Assert (Write_All (Read_All ("single" & LF & "")) = "single" & LF & "",
         "csv4: write round-trip");
      Assert (Write_All (Read_All ("a,b" & CR & "" & LF & "c,d" & CR & "" & LF & "")) = "a,b" & LF &
         "c,d" & LF & "", "csv5: write round-trip");
      Assert (Write_All (Read_All ("""multi" & LF & "line"",x" & LF & "")) = """multi" & LF &
         "line"",x" & LF & "", "csv6: write round-trip");
      Assert (Write_All (Read_All ("")) = "", "csv8: write round-trip");
      Assert (Write_All (Read_All ("a,b")) = "a,b" & LF & "", "csv9: write round-trip");
      Assert (Write_All (Read_All ("a,b" & LF & "" & LF & "c,d" & LF & "")) = "a,b" & LF & "c,d" &
         LF & "", "csv10: write round-trip");
      Assert (Write_All (Read_All ("" & CR & "" & LF & "")) = "", "csv11: write round-trip");
      Assert (Write_All (Read_All ("""q"",x" & CR & "" & LF & "z,w" & LF & "")) = "q,x" & LF & "z,w"
         & LF & "", "csv14: write round-trip");
      Assert (Write_All (Read_All ("""a""" & CR & "" & LF & "b" & LF & "")) = "a" & LF & "b" & LF &
         "", "csv15: write round-trip");

      --  Tricky fields (comma, quote, newline, empty) pinned from Go.
      Assert (Write_All (Recs (Rec ("plain", "with,comma", "with""quote",
                                     "with" & LF & "newline", ""),
                               Rec ("", "x", "y", "z", "w"))) =
         "plain,""with,comma"",""with""""quote"",""with" & LF & "newli" & "ne""," & LF & ",x,y,z,w"
         & LF & "",
              "csvw: tricky write");
   end Test_Csv_Write;


   procedure Test_Csv_Errors (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin

      --  CSV doc 7: field-count mismatch must raise
      begin
         declare
            L : constant Row_List := Read_All ("a,b" & LF & "1,2,extra" & LF & "");
         begin
            Assert (Row_Vectors.Length (L) = 0, "csv7: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  CSV doc 12: field-count mismatch must raise
      begin
         declare
            L : constant Row_List := Read_All ("""a""x" & LF & "");
         begin
            Assert (Row_Vectors.Length (L) = 0, "csv12: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  CSV doc 13: field-count mismatch must raise
      begin
         declare
            L : constant Row_List := Read_All ("""abc");
         begin
            Assert (Row_Vectors.Length (L) = 0, "csv13: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  CSV doc 16: field-count mismatch must raise
      begin
         declare
            L : constant Row_List := Read_All ("""a""" & CR & "b" & LF & "");
         begin
            Assert (Row_Vectors.Length (L) = 0, "csv16: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
   end Test_Csv_Errors;


   procedure Test_Xml_Escape (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin

      Assert (Escape_Text ("a<b>&""'" & HT & "" & LF & "" & CR & "") =
         "a&lt;b&gt;&amp;&#34;&#39;&#x9;&#xA;&#xD;", "esc0");
      Assert (Escape_Text ("plain") = "plain", "esc1");
      Assert (Escape_Text ("") = "", "esc2");
   end Test_Xml_Escape;


   procedure Test_Xml_Unmarshal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  Doc 0: <root a="1" b="x&amp;y"><child>hello</child><child/></root>
      declare
         N : constant Node := Unmarshal
           ("<root a=""1"" b=""x&amp;y""><child>hello</child><child/></root>");
      begin
         Assert (N.Kind = Element, "x0: root element");
         Assert (To_String (N.Name) = "root", "x0: root name");
         Assert (Natural (Attr_Vectors.Length (N.Attrs)) = 2, "x0: attr count");
         Assert (To_String (Attr_Vectors.Element (N.Attrs, 1).Name) = "a"
                 and then To_String (Attr_Vectors.Element (N.Attrs, 1).Value) = "1",
                 "x0: attr a");
         Assert (To_String (Attr_Vectors.Element (N.Attrs, 2).Name) = "b"
                 and then To_String (Attr_Vectors.Element (N.Attrs, 2).Value) = "x&y",
                 "x0: attr b decoded");
         Assert (Natural (Node_Vectors.Length (N.Children)) = 2, "x0: children");
         declare
            C1 : constant Node_Access := Node_Vectors.Element (N.Children, 1);
            C2 : constant Node_Access := Node_Vectors.Element (N.Children, 2);
         begin
            Assert (To_String (C1.Name) = "child", "x0: child1 name");
            Assert (Natural (Node_Vectors.Length (C1.Children)) = 1, "x0: child1 text");
            Assert (C1.Children (1).Kind = Text_Node
                    and then To_String (C1.Children (1).Text) = "hello",
                    "x0: child1 text value");
            Assert (To_String (C2.Name) = "child"
                    and then Node_Vectors.Length (C2.Children) = 0,
                    "x0: child2 empty");
         end;
      end;

      --  Doc 1: prolog + comment skipped, single-quoted attr, entity in text.
      declare
         N : constant Node := Unmarshal
           ("<?xml version=""1.0"" encoding=""UTF-8""?><!-- comment -->"
            & "<a><b>text</b><c attr='single'>x&lt;y</c></a>");
      begin
         Assert (To_String (N.Name) = "a", "x1: root name");
         Assert (Natural (Node_Vectors.Length (N.Children)) = 2, "x1: children");
         declare
            B : constant Node_Access := Node_Vectors.Element (N.Children, 1);
            C : constant Node_Access := Node_Vectors.Element (N.Children, 2);
         begin
            Assert (To_String (B.Name) = "b"
                    and then To_String (B.Children (1).Text) = "text",
                    "x1: <b>text</b>");
            Assert (To_String (C.Name) = "c"
                    and then To_String (Attr_Vectors.Element (C.Attrs, 1).Value)
                      = "single"
                    and then To_String (C.Children (1).Text) = "x<y",
                    "x1: <c attr='single'>x&lt;y</c>");
         end;
      end;

      --  Doc 5: entity decoding incl. numeric refs.
      declare
         N : constant Node := Unmarshal
           ("<a>&lt;&gt;&amp;&quot;&apos;&#65;&#x42;</a>");
      begin
         Assert (Natural (Node_Vectors.Length (N.Children)) = 1, "x5: one text");
         Assert (To_String (N.Children (1).Text) = "<>&""'AB", "x5: decoded");
      end;
   end Test_Xml_Unmarshal;


   procedure Test_Xml_Marshal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin

      Assert (Marshal (Unmarshal ("<root a=""1"" b=""x&amp;y""><child>hello</child>" &
         "<child/></root>")) = "<root a=""1"" b=""x&amp;y""><child>hello</child>" &
         "<child></child></root>", "xml0: marshal");
      Assert (Marshal (Unmarshal ("<?xml version=""1.0"" encoding=""UTF-8""?><!-- c" &
         "omment --><a><b>text</b><c attr='single'>x&l" & "t;y</c></a>")) =
         "<a><b>text</b><c attr=""single"">x&lt;y</c></a>", "xml1: marshal");
      Assert (Marshal (Unmarshal ("<empty></empty>")) = "<empty></empty>", "xml2: marshal");
      Assert (Marshal (Unmarshal ("<self/>")) = "<self></self>", "xml3: marshal");
      Assert (Marshal (Unmarshal ("<a>1<b>2</b>3</a>")) = "<a>1<b>2</b>3</a>", "xml4: marshal");
      Assert (Marshal (Unmarshal ("<a>&lt;&gt;&amp;&quot;&apos;&#65;&#x42;</a>")) =
         "<a>&lt;&gt;&amp;&#34;&#39;AB</a>", "xml5: marshal");
      Assert (Marshal (Unmarshal ("<a><![CDATA[x<y & z]]></a>")) = "<a>x&lt;y &amp; z</a>",
         "xml6: marshal");
      Assert (Marshal (Unmarshal ("<a><!-- c --><b/></a>")) = "<a><b></b></a>", "xml7: marshal");
      Assert (Marshal (Unmarshal ("<a x=""1"" y='two'>t</a>")) = "<a x=""1"" y=""two"">t</a>",
         "xml8: marshal");
      Assert (Marshal (Unmarshal ("<!DOCTYPE g><a/>")) = "<a></a>", "xml9: marshal");
      Assert (Marshal (Unmarshal ("<a><?pi x?></a>")) = "<a></a>", "xml10: marshal");
      Assert (Marshal (Unmarshal ("<a>&#x41;&#x4a;&#x61;</a>")) = "<a>AJa</a>", "xml11: marshal");
      Assert (Marshal (Unmarshal ("<a><!DOCTYPE x></a>")) = "<a></a>", "xml12: marshal");
   end Test_Xml_Marshal;


   procedure Test_Xml_Errors (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin

      --  Bad doc 0
      begin
         declare
            N : constant Node := Unmarshal ("<a><b></a>");
         begin
            Assert (N.Kind = Text_Node, "bad0: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 1
      begin
         declare
            N : constant Node := Unmarshal ("<a>");
         begin
            Assert (N.Kind = Text_Node, "bad1: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 2
      begin
         declare
            N : constant Node := Unmarshal ("<a x=""1></a>");
         begin
            Assert (N.Kind = Text_Node, "bad2: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 3
      begin
         declare
            N : constant Node := Unmarshal ("<a>&bad;</a>");
         begin
            Assert (N.Kind = Text_Node, "bad3: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 4
      begin
         declare
            N : constant Node := Unmarshal ("<a>text");
         begin
            Assert (N.Kind = Text_Node, "bad4: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 5
      begin
         declare
            N : constant Node := Unmarshal ("<a x=1></a>");
         begin
            Assert (N.Kind = Text_Node, "bad5: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 6
      begin
         declare
            N : constant Node := Unmarshal ("</a>");
         begin
            Assert (N.Kind = Text_Node, "bad6: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 7
      begin
         declare
            N : constant Node := Unmarshal ("<a><?pi");
         begin
            Assert (N.Kind = Text_Node, "bad7: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 8
      begin
         declare
            N : constant Node := Unmarshal ("<a><!-- c");
         begin
            Assert (N.Kind = Text_Node, "bad8: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 10
      begin
         declare
            N : constant Node := Unmarshal ("<a>&#xZZ;</a>");
         begin
            Assert (N.Kind = Text_Node, "bad10: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 11
      begin
         declare
            N : constant Node := Unmarshal ("<a>&#;</a>");
         begin
            Assert (N.Kind = Text_Node, "bad11: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 13
      begin
         declare
            N : constant Node := Unmarshal ("<a>&");
         begin
            Assert (N.Kind = Text_Node, "bad13: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 15
      begin
         declare
            N : constant Node := Unmarshal ("");
         begin
            Assert (N.Kind = Text_Node, "bad15: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 16
      begin
         declare
            N : constant Node := Unmarshal ("<a><![CDATA[x</a>");
         begin
            Assert (N.Kind = Text_Node, "bad16: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 17
      begin
         declare
            N : constant Node := Unmarshal ("<a>&#65");
         begin
            Assert (N.Kind = Text_Node, "bad17: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 18
      begin
         declare
            N : constant Node := Unmarshal ("<!-- x");
         begin
            Assert (N.Kind = Text_Node, "bad18: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 19
      begin
         declare
            N : constant Node := Unmarshal ("<?xml");
         begin
            Assert (N.Kind = Text_Node, "bad19: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 20
      begin
         declare
            N : constant Node := Unmarshal ("<>");
         begin
            Assert (N.Kind = Text_Node, "bad20: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
      --  Bad doc 21
      begin
         declare
            N : constant Node := Unmarshal ("<a");
         begin
            Assert (N.Kind = Text_Node, "bad21: must raise");
         end;
      exception
         when Constraint_Error => null;  --  expected
      end;
   end Test_Xml_Errors;

end Std_Encoding_Text_Suite;

