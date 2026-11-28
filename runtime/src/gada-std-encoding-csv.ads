with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Gada.Std.Strings;

--  encoding/csv: a focused port of Go's csv.Reader/Writer semantics.
--  Read_All parses a whole document; Write_All renders records the way
--  Go's csv.Writer does (fields quoted only when they contain ',', '"',
--  '\n' or '\r', embedded quotes doubled, records terminated by '\n').
package Gada.Std.Encoding.Csv is

   subtype Record is Gada.Std.Strings.String_Slice;

   package Record_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Record,
      "="          => Gada.Std.Strings.String_Vectors."=");

   subtype Record_List is Record_Vectors.Vector;

   --  Parse all records. Raises Constraint_Error on malformed quoting or
   --  on a record whose field count differs from the first record's
   --  (Go's FieldsPerRecord enforcement).
   function Read_All (S : String) return Record_List;

   --  Render records Go csv.Writer style: '\n' after every record,
   --  minimal quoting, doubled quotes inside quoted fields.
   function Write_All (Records : Record_List) return String;

end Gada.Std.Encoding.Csv;
