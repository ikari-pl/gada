--  Body of Gada.Std.OS — see spec for the port rationale.

with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;

package body Gada.Std.OS is

   use Ada.Streams;

   procedure Read_File (Path : String;
                        Data : out Bytes.Byte_Slice;
                        Err  : out Errors.Error_Access) is
      package SIO renames Ada.Streams.Stream_IO;
      F : SIO.File_Type;
   begin
      Data := Bytes.Byte_Vectors.Empty_Vector;
      Err  := Errors.No_Error;
      begin
         SIO.Open (F, SIO.In_File, Path);
      exception
         when E : Ada.IO_Exceptions.Name_Error
            | Ada.IO_Exceptions.Use_Error =>
            Err := Errors.New_K
              ("open " & Path & ": "
               & Ada.Exceptions.Exception_Message (E));
            return;
      end;
      declare
         N    : constant Stream_Element_Offset :=
           Stream_Element_Offset (SIO.Size (F));
         Buf  : Stream_Element_Array (1 .. N);
         Last : Stream_Element_Offset;
      begin
         begin
            SIO.Read (F, Buf, Last);
            for I in Buf'First .. Last loop
               Bytes.Byte_Vectors.Append
                 (Data, Character'Val (Buf (I)));
            end loop;
         exception
            --  Go returns an error value; a raw Ada exception from
            --  the stream read must not escape (and must not leak F).
            when E : Ada.IO_Exceptions.Device_Error
               | Ada.IO_Exceptions.End_Error
               | Ada.IO_Exceptions.Data_Error =>
               Err := Errors.New_K
                 ("read " & Path & ": "
                  & Ada.Exceptions.Exception_Message (E));
         end;
         SIO.Close (F);
      end;
   end Read_File;

end Gada.Std.OS;
