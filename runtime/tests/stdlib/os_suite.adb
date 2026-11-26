--  Body of OS_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Containers; use type Ada.Containers.Count_Type;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Errors;
with Gada.Std.OS; use Gada.Std.OS;

package body OS_Suite is

   package Errors renames Gada.Std.Errors;

   use type Errors.Error_Access;

   Tmp_Name : constant String := "os_suite_tmp.bin";

   --  Writes Content to the temp file via raw stream I/O so the test
   --  controls the exact bytes (including a 0 byte and a >127 byte).
   procedure Write_Tmp (Content : String) is
      use Ada.Streams;
      F   : Stream_IO.File_Type;
      Buf : Stream_Element_Array
        (1 .. Stream_Element_Offset (Content'Length));
   begin
      for I in Content'Range loop
         Buf (Stream_Element_Offset (I - Content'First + 1)) :=
           Stream_Element (Character'Pos (Content (I)));
      end loop;
      Stream_IO.Create (F, Stream_IO.Out_File, Tmp_Name);
      Stream_IO.Write (F, Buf);
      Stream_IO.Close (F);
   end Write_Tmp;

   procedure Remove_Tmp is
   begin
      if Ada.Directories.Exists (Tmp_Name) then
         Ada.Directories.Delete_File (Tmp_Name);
      end if;
   end Remove_Tmp;

   overriding function Name
     (T : OS_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.OS suite"));

   overriding procedure Register_Tests (T : in out OS_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Read_File_Ok'Access, "ReadFile contents");
      Register_Routine (T, Test_Read_File_Empty'Access, "ReadFile empty");
      Register_Routine (T, Test_Read_File_Missing'Access,
                        "ReadFile missing file errors");
   end Register_Tests;

   procedure Test_Read_File_Ok (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Content : constant String :=
        "line one" & Character'Val (10) & "bin:" & Character'Val (0)
        & Character'Val (16#FF#);
      Data : Byte_Slice;
      Err  : Errors.Error_Access;
   begin
      Write_Tmp (Content);
      Read_File (Tmp_Name, Data, Err);
      Assert (Err = Errors.No_Error, "read ok: nil error");
      Assert (Integer (Byte_Vectors.Length (Data)) = Content'Length,
              "read ok: length, got"
                & Integer'Image (Integer (Byte_Vectors.Length (Data))));
      Assert (To_String (Data) = Content, "read ok: exact bytes");
      Remove_Tmp;
   end Test_Read_File_Ok;

   procedure Test_Read_File_Empty (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Data : Byte_Slice;
      Err  : Errors.Error_Access;
   begin
      Write_Tmp ("");
      Read_File (Tmp_Name, Data, Err);
      Assert (Err = Errors.No_Error, "empty: nil error");
      Assert (Byte_Vectors.Is_Empty (Data), "empty: empty slice");
      Remove_Tmp;
   end Test_Read_File_Empty;

   procedure Test_Read_File_Missing (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Data : Byte_Slice;
      Err  : Errors.Error_Access;
   begin
      Remove_Tmp;  --  make sure the path really does not exist
      Read_File (Tmp_Name, Data, Err);
      Assert (Err /= Errors.No_Error, "missing: error set");
      Assert (Byte_Vectors.Is_Empty (Data), "missing: empty slice");
   end Test_Read_File_Missing;

end OS_Suite;
