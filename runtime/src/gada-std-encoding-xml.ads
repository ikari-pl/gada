with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  encoding/xml: a small tree-model XML reader/writer. Unmarshal parses a
--  document into a Node tree (elements and text nodes in document order);
--  Marshal renders a tree back to text with Go-compatible escaping:
--  double-quoted attributes, <x></x> for empty elements, and Escape_Text
--  semantics for character data and attribute values. Malformed input
--  raises Constraint_Error.
package Gada.Std.Encoding.Xml is

   use Ada.Strings.Unbounded;

   type Attr is record
      Name  : Unbounded_String;
      Value : Unbounded_String;
   end record;

   package Attr_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Attr);

   subtype Attr_List is Attr_Vectors.Vector;

   type Node;
   type Node_Access is access Node;

   package Node_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Node_Access);

   subtype Node_List is Node_Vectors.Vector;

   type Node_Kind is (Element, Text_Node);

   type Node is record
      Kind     : Node_Kind := Text_Node;
      Name     : Unbounded_String;  --  Element only
      Attrs    : Attr_List;         --  Element only
      Children : Node_List;         --  Element only
      Text     : Unbounded_String;  --  Text_Node only
   end record;

   --  Go xml.EscapeText: & < > ' " become &amp; &lt; &gt; &#39; &#34; and
   --  tab/LF/CR become &#x9; &#xA; &#xD;; everything else passes through.
   function Escape_Text (S : String) return String;

   function Unmarshal (S : String) return Node;

   function Marshal (N : Node) return String;

end Gada.Std.Encoding.Xml;
