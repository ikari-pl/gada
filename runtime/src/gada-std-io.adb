--  Body of Gada.Std.IO — see spec for the Go-semantics contract.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Gada.Std.Errors;

package body Gada.Std.IO is

   package Errors renames Gada.Std.Errors;

   use type Errors.Error_Access;

   procedure Copy (Dst : Writer_Access; Src : Reader_Access;
                   N : out Natural;
                   Err : out Errors.Error_Access) is
      Buf   : String (1 .. 4096);
      Chunk : Natural;
      Total : Natural := 0;
      E     : Errors.Error_Access;
   begin
      Err := Errors.No_Error;
      loop
         E := Read (Src.all, Buf, Chunk);
         if Chunk > 0 then
            declare
               WN : Natural;
               WE : constant Errors.Error_Access :=
                 Write (Dst.all, Buf (1 .. Chunk), WN);
            begin
               Total := Total + WN;
               if WE /= Errors.No_Error
                 and then not Errors.Is_K (WE, EOF)
               then
                  Err := WE;
                  N := Total;
                  return;
               end if;
            end;
         end if;
         if E /= Errors.No_Error then
            --  EOF ends the copy successfully (Go's Copy contract);
            --  any other error is returned.
            if not Errors.Is_K (E, EOF) then
               Err := E;
            end if;
            exit;
         end if;
         exit when Chunk = 0;
      end loop;
      N := Total;
   end Copy;

   procedure Read_All (R : Reader_Access;
                       Data : out Unbounded_String;
                       Err : out Errors.Error_Access) is
      Buf   : String (1 .. 4096);
      Chunk : Natural;
      E     : Errors.Error_Access;
   begin
      Data := Null_Unbounded_String;
      Err := Errors.No_Error;
      loop
         E := Read (R.all, Buf, Chunk);
         if Chunk > 0 then
            Append (Data, Buf (1 .. Chunk));
         end if;
         if E /= Errors.No_Error then
            if not Errors.Is_K (E, EOF) then
               Err := E;
            end if;
            return;
         end if;
         exit when Chunk = 0;
      end loop;
   end Read_All;

begin
   --  Go: var EOF = errors.New("EOF")
   EOF := Errors.New_K ("EOF");
end Gada.Std.IO;
