--  Body of Gada.Std.OS — see spec for the port rationale.

with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Gada.Std.Strings;

package body Gada.Std.OS is

   use Ada.Streams;
   use type Ada.Directories.File_Kind;

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

   ---------------------------------------------------------------
   --  Args
   ---------------------------------------------------------------

   function Args return Strings.String_Slice is
      use Ada.Command_Line;
      V : Strings.String_Slice;
   begin
      V.Append (To_Unbounded_String (Command_Name));
      for I in 1 .. Argument_Count loop
         V.Append (To_Unbounded_String (Argument (I)));
      end loop;
      return V;
   end Args;

   ---------------------------------------------------------------
   --  Environment
   ---------------------------------------------------------------

   function Lookup_Env
     (Key   : String;
      Value : out Unbounded_String) return Boolean is
   begin
      if Ada.Environment_Variables.Exists (Key) then
         Value := To_Unbounded_String
           (Ada.Environment_Variables.Value (Key));
         return True;
      end if;
      Value := Null_Unbounded_String;
      return False;
   end Lookup_Env;

   function Get_Env (Key : String) return String is
      V : Unbounded_String;
   begin
      if Lookup_Env (Key, V) then
         return To_String (V);
      end if;
      return "";
   end Get_Env;

   function Set_Env (Key, Value : String) return Errors.Error_Access is
   begin
      if Key'Length = 0 or else (for some C of Key => C = '=') then
         return Errors.New_K ("setenv: invalid argument");
      end if;
      Ada.Environment_Variables.Set (Key, Value);
      return Errors.No_Error;
   end Set_Env;

   ---------------------------------------------------------------
   --  Files
   ---------------------------------------------------------------

   procedure Open (Path : String;
                   F    : out File_Access;
                   Err  : out Errors.Error_Access) is
      package SIO renames Ada.Streams.Stream_IO;
   begin
      F := new File;
      begin
         SIO.Open (F.F, SIO.In_File, Path);
         Err := Errors.No_Error;
      exception
         when E : Ada.IO_Exceptions.Name_Error
            | Ada.IO_Exceptions.Use_Error =>
            F   := null;
            Err := Errors.New_K
              ("open " & Path & ": "
               & Ada.Exceptions.Exception_Message (E));
      end;
   end Open;

   procedure Create (Path : String;
                     F    : out File_Access;
                     Err  : out Errors.Error_Access) is
      package SIO renames Ada.Streams.Stream_IO;
   begin
      F := new File;
      begin
         SIO.Create (F.F, SIO.Out_File, Path);
         Err := Errors.No_Error;
      exception
         when E : Ada.IO_Exceptions.Name_Error
            | Ada.IO_Exceptions.Use_Error =>
            F   := null;
            Err := Errors.New_K
              ("create " & Path & ": "
               & Ada.Exceptions.Exception_Message (E));
      end;
   end Create;

   procedure Write (F : File_Access; Data : Bytes.Byte_Slice) is
      package SIO renames Ada.Streams.Stream_IO;
      N   : Natural := 0;
      Buf : Stream_Element_Array
        (1 .. Stream_Element_Offset (Bytes.Byte_Vectors.Length (Data)));
   begin
      if F = null or else not SIO.Is_Open (F.all.F) then
         raise Ada.IO_Exceptions.Use_Error;
      end if;
      for C of Data loop
         N := N + 1;
         Buf (Stream_Element_Offset (N)) :=
           Stream_Element (Character'Pos (C));
      end loop;
      SIO.Write (F.all.F, Buf (1 .. Stream_Element_Offset (N)));
   end Write;

   procedure Close (F : in out File_Access) is
      package SIO renames Ada.Streams.Stream_IO;
   begin
      if F /= null then
         if SIO.Is_Open (F.all.F) then
            SIO.Close (F.all.F);
         end if;
         F := null;
      end if;
   end Close;

   ---------------------------------------------------------------
   --  Stat / Mkdir
   ---------------------------------------------------------------

   procedure Stat (Path   : String;
                   Size   : out Long_Integer;
                   Is_Dir : out Boolean;
                   Err    : out Errors.Error_Access) is
   begin
      Size   := 0;
      Is_Dir := False;
      Err    := Errors.No_Error;
      begin
         Is_Dir := Ada.Directories.Kind (Path) = Ada.Directories.Directory;
         if not Is_Dir then
            Size := Long_Integer (Ada.Directories.Size (Path));
         end if;
      exception
         when E : Ada.Directories.Name_Error
            | Ada.Directories.Use_Error =>
            Err := Errors.New_K
              ("stat " & Path & ": "
               & Ada.Exceptions.Exception_Message (E));
      end;
   end Stat;

   procedure Mkdir (Path : String; Err : out Errors.Error_Access) is
   begin
      Ada.Directories.Create_Directory (Path);
      Err := Errors.No_Error;
   exception
      when E : Ada.Directories.Use_Error
         | Ada.Directories.Name_Error =>
         Err := Errors.New_K
           ("mkdir " & Path & ": "
            & Ada.Exceptions.Exception_Message (E));
   end Mkdir;

end Gada.Std.OS;
