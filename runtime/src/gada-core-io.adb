--  Gada.Core.IO body — implementation of the minimal Println surface.
--
--  See spec for the layering contract. The body delegates to
--  `Ada.Text_IO.Put_Line` against the *current* default output stream,
--  which means tests can redirect output via `Ada.Text_IO.Set_Output`
--  and the captured bytes will pass through this procedure unchanged.

with Ada.Text_IO;

package body Gada.Core.IO is

   procedure Println (Text : String) is
   begin
      Ada.Text_IO.Put_Line (Text);
   end Println;

end Gada.Core.IO;
