--  Gada.Core.Defer body — see spec for design.
--
--  Whole module is one line of executable code: when the block
--  containing the Defer_Block exits, Ada calls Finalize, which
--  invokes the captured Op. That's it.

package body Gada.Core.Defer is

   overriding procedure Finalize (D : in out Defer_Block) is
   begin
      D.Op.all;
   end Finalize;

end Gada.Core.Defer;
