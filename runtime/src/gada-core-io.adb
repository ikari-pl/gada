--  Gada.Core.IO body — implementation of the print surface.
--
--  See spec for the layering contract. Every primitive delegates to
--  `Ada.Text_IO` against the *current* default output stream, which
--  means tests can redirect output via `Ada.Text_IO.Set_Output` and the
--  captured bytes will pass through unchanged.

with Ada.Text_IO;
with Ada.Strings;
with Ada.Strings.Fixed;

package body Gada.Core.IO is

   procedure Print (Text : String) is
   begin
      Ada.Text_IO.Put (Text);
   end Print;

   procedure Print (Item : Integer) is
   begin
      --  `Item'Image` keeps Ada's leading blank in the sign position
      --  for non-negative values; Trim (…, Left) drops it so the output
      --  is Go's bare digits. A negative value's `-` is not a blank, so
      --  Trim leaves it intact.
      Ada.Text_IO.Put
        (Ada.Strings.Fixed.Trim (Item'Image, Ada.Strings.Left));
   end Print;

   procedure New_Line is
   begin
      Ada.Text_IO.New_Line;
   end New_Line;

   procedure Println (Text : String) is
   begin
      Print (Text);
      New_Line;
   end Println;

end Gada.Core.IO;
