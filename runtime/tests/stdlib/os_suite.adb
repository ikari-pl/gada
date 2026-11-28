--  Body of OS_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Command_Line;
with Ada.Containers; use type Ada.Containers.Count_Type;
with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces.C.Strings;
with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Errors;
with Gada.Std.Strings;
with Gada.Std.OS; use Gada.Std.OS;

package body OS_Suite is

   package Errors renames Gada.Std.Errors;

   use type Ada.Strings.Unbounded.Unbounded_String;
   use type Errors.Error_Access;

   Tmp_Name : constant String := "os_suite_tmp.bin";
   Tmp_Dir  : constant String := "os_suite_tmp_dir";

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
      Register_Routine (T, Test_Args'Access, "Args");
      Register_Routine (T, Test_Env'Access, "Getenv/LookupEnv/Setenv");
      Register_Routine (T, Test_Open_Ok'Access, "Open existing ok");
      Register_Routine (T, Test_Open_Missing'Access, "Open missing errors");
      Register_Routine (T, Test_Create_Write_Stat'Access,
                        "Create/Write/Close/Stat roundtrip");
      Register_Routine (T, Test_Stat_Dir_And_Missing'Access,
                        "Stat dir + missing");
      Register_Routine (T, Test_Mkdir'Access, "Mkdir + exists error");
      Register_Routine (T, Test_Read_File_FIFO'Access, "ReadFile FIFO");
      Register_Routine (T, Test_Read_File_Large'Access,
                        "ReadFile > one 64 KiB chunk");
      Register_Routine (T, Test_Mkdir_Invalid'Access,
                        "Mkdir empty/invalid path errors");
      Register_Routine (T, Test_Write_After_Close'Access,
                        "Write after Close raises");
      Register_Routine (T, Test_Read_File_Dir'Access,
                        "ReadFile on a directory errors");
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

   procedure Test_Args (T : in out AUnit.Test_Cases.Test_Case'Class) is
      A : constant Gada.Std.Strings.String_Slice := Args;
   begin
      Assert (A.Length >= 1, "Args has at least argv[0], got"
              & Ada.Containers.Count_Type'Image (A.Length));
      Assert (A (1) = Ada.Strings.Unbounded.To_Unbounded_String
                (Ada.Command_Line.Command_Name),
              "Args(1) is the program name (Go os.Args[0])");
   end Test_Args;

   procedure Test_Env (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Err : Errors.Error_Access;
      V   : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Err := Set_Env ("GADA_OS_SUITE_VAR", "hello-42");
      Assert (Err = Errors.No_Error, "Set_Env ok");
      Assert (Get_Env ("GADA_OS_SUITE_VAR") = "hello-42", "Get_Env hit");
      Assert (Lookup_Env ("GADA_OS_SUITE_VAR", V)
              and then Ada.Strings.Unbounded.To_String (V) = "hello-42",
              "Lookup_Env hit");
      Assert (not Lookup_Env ("GADA_OS_SUITE_MISSING", V),
              "Lookup_Env miss");
      Assert (Get_Env ("GADA_OS_SUITE_MISSING") = "",
              "Get_Env unset is empty string");
      Err := Set_Env ("GADA_BAD=KEY", "x");
      Assert (Err /= Errors.No_Error, "Set_Env rejects '=' in key");
      Err := Set_Env ("", "x");
      Assert (Err /= Errors.No_Error, "Set_Env rejects empty key");
      --  LookupEnv with a bad key returns ("", false), no raise.
      Assert (not Lookup_Env ("GADA_BAD=KEY", V),
              "Lookup_Env rejects '=' in key");
      Assert (not Lookup_Env ("", V), "Lookup_Env rejects empty key");
   end Test_Env;

   procedure Test_Open_Ok (T : in out AUnit.Test_Cases.Test_Case'Class) is
      F   : File_Access;
      Err : Errors.Error_Access;
   begin
      Write_Tmp ("abc");
      Open (Tmp_Name, F, Err);
      Assert (Err = Errors.No_Error and F /= null, "Open existing ok");
      Close (F);
      Assert (F = null, "Close nulls handle");
      Remove_Tmp;
   end Test_Open_Ok;

   procedure Test_Open_Missing (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      F    : File_Access;
      Err  : Errors.Error_Access;
      F2   : File_Access;
      Err2 : Errors.Error_Access;
   begin
      Open ("os_suite_missing_xyz.bin", F, Err);
      Assert (Err /= Errors.No_Error, "open missing: error set");
      Assert (F = null, "open missing: null handle");
      --  Create in a nonexistent directory hits the same error arm.
      Create ("os_suite_missing_dir_xyz/f.bin", F2, Err2);
      Assert (Err2 /= Errors.No_Error, "create in missing dir: error");
      Assert (F2 = null, "create error: null handle");
   end Test_Open_Missing;

   procedure Test_Create_Write_Stat (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      F      : File_Access;
      Err    : Errors.Error_Access;
      Size   : Long_Integer;
      Is_Dir : Boolean;
      Data   : Byte_Slice;
      Raised : Boolean := False;
   begin
      Remove_Tmp;
      Create (Tmp_Name, F, Err);
      Assert (Err = Errors.No_Error and F /= null, "Create ok");
      Write (F, To_Bytes ("hello"));
      Close (F);
      Assert (F = null, "Close nulls the handle");
      begin
         Write (F, To_Bytes ("x"));  --  F is null now
      exception
         when Ada.IO_Exceptions.Use_Error =>
            Raised := True;
      end;
      Assert (Raised, "Write on a closed handle raises Use_Error");
      Stat (Tmp_Name, Size, Is_Dir, Err);
      Assert (Err = Errors.No_Error and not Is_Dir and Size = 5,
              "Stat: size 5, not a dir");
      Read_File (Tmp_Name, Data, Err);
      Assert (Err = Errors.No_Error and To_String (Data) = "hello",
              "Create/Write round-trips through ReadFile");
      Remove_Tmp;
   end Test_Create_Write_Stat;

   procedure Test_Stat_Dir_And_Missing (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Size   : Long_Integer;
      Is_Dir : Boolean;
      Err    : Errors.Error_Access;
   begin
      Stat (".", Size, Is_Dir, Err);
      Assert (Err = Errors.No_Error and Is_Dir, "Stat: cwd is a dir");
      Stat ("os_suite_missing_xyz.bin", Size, Is_Dir, Err);
      Assert (Err /= Errors.No_Error, "Stat missing: error set");
   end Test_Stat_Dir_And_Missing;

   procedure Test_Mkdir (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Err    : Errors.Error_Access;
      Size   : Long_Integer;
      Is_Dir : Boolean;
   begin
      if Ada.Directories.Exists (Tmp_Dir) then
         Ada.Directories.Delete_Directory (Tmp_Dir);
      end if;
      Mkdir (Tmp_Dir, Err);
      Assert (Err = Errors.No_Error, "Mkdir ok");
      Stat (Tmp_Dir, Size, Is_Dir, Err);
      Assert (Err = Errors.No_Error and Is_Dir, "Mkdir made a dir");
      Mkdir (Tmp_Dir, Err);
      Assert (Err /= Errors.No_Error, "Mkdir on existing errors");
      Ada.Directories.Delete_Directory (Tmp_Dir);
   end Test_Mkdir;

   procedure Test_Read_File_Dir (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Data : Byte_Slice;
      Err  : Errors.Error_Access;
   begin
      --  On Linux, opening a directory succeeds and the read fails
      --  with Device_Error (EISDIR) — exercises the read-error arm.
      Read_File (".", Data, Err);
      Assert (Err /= Errors.No_Error, "dir read: error set");
      Assert (Byte_Vectors.Is_Empty (Data), "dir read: empty slice");
   end Test_Read_File_Dir;

   --  Regression (#13): Read_File sized its buffer from Stream_IO.Size.
   --  A FIFO has no size (Size raised Use_Error, which escaped and
   --  leaked the handle; procfs files report 0 and read empty). The
   --  chunked loop reads to EOF: a writer task feeds a FIFO here.
   procedure Test_Read_File_FIFO (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      use Interfaces.C;
      function C_Mkfifo (Path : Interfaces.C.Strings.chars_ptr;
                         Mode : unsigned_short) return int
        with Import, Convention => C, External_Name => "mkfifo";
      --  Ada.Directories.Delete_File only removes ordinary files.
      function C_Unlink (Path : Interfaces.C.Strings.chars_ptr) return int
        with Import, Convention => C, External_Name => "unlink";
      Fifo    : constant String := "os_suite_tmp.fifo";
      Payload : constant String := "fifo payload";
      Data    : Byte_Slice;
      Err     : Errors.Error_Access;
      C_Path  : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Fifo);
   begin
      if C_Unlink (C_Path) /= 0 then
         null;  --  absent from a previous run: fine
      end if;
      Assert (C_Mkfifo (C_Path, 8#600#) = 0, "mkfifo");
      declare
         task Writer;
         task body Writer is
            use Ada.Streams;
            F   : Stream_IO.File_Type;
            Buf : Stream_Element_Array
              (1 .. Stream_Element_Offset (Payload'Length));
         begin
            for I in Payload'Range loop
               Buf (Stream_Element_Offset (I)) :=
                 Stream_Element (Character'Pos (Payload (I)));
            end loop;
            Stream_IO.Open (F, Stream_IO.Out_File, Fifo);
            Stream_IO.Write (F, Buf);
            Stream_IO.Close (F);
         end Writer;
      begin
         Read_File (Fifo, Data, Err);
      end;  --  waits for Writer
      Assert (C_Unlink (C_Path) = 0, "unlink fifo");
      Interfaces.C.Strings.Free (C_Path);
      Assert (Err = Errors.No_Error, "FIFO read: no error");
      Assert (To_String (Data) = Payload,
              "FIFO read to EOF, got """ & To_String (Data) & """");
   end Test_Read_File_FIFO;

   --  A file larger than one 64 KiB chunk crosses the chunk loop.
   procedure Test_Read_File_Large (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Content : constant String (1 .. 150_000) :=
        [for I in 1 .. 150_000 => Character'Val (Character'Pos ('a')
                                                 + I mod 26)];
      Data    : Byte_Slice;
      Err     : Errors.Error_Access;
   begin
      Write_Tmp (Content);
      Read_File (Tmp_Name, Data, Err);
      Remove_Tmp;
      Assert (Err = Errors.No_Error, "large read: no error");
      Assert (Byte_Vectors.Length (Data) = 150_000
                and then To_String (Data) = Content,
              "large read round-trips all 150000 bytes");
   end Test_Read_File_Large;

   --  Mkdir on an empty or invalid path returns an error, no raise.
   procedure Test_Mkdir_Invalid (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Err : Errors.Error_Access;
   begin
      Mkdir ("", Err);
      Assert (Err /= Errors.No_Error, "Mkdir """" errors");
      Mkdir ("os_suite_missing_parent_xyz/child", Err);
      Assert (Err /= Errors.No_Error, "Mkdir under a missing parent errors");
   end Test_Mkdir_Invalid;

   --  Write through a stale copy of a handle after Close (F itself is
   --  nulled, the copy still points at the closed File) raises.
   procedure Test_Write_After_Close (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      F, G   : File_Access;
      Err    : Errors.Error_Access;
      Raised : Boolean := False;
   begin
      Remove_Tmp;
      Create (Tmp_Name, F, Err);
      Assert (Err = Errors.No_Error, "Create ok");
      G := F;
      Close (F);
      begin
         Write (G, To_Bytes ("x"));
      exception
         when Ada.IO_Exceptions.Use_Error =>
            Raised := True;
      end;
      Remove_Tmp;
      Assert (Raised, "Write after Close (stale copy) raises Use_Error");
   end Test_Write_After_Close;

end OS_Suite;
