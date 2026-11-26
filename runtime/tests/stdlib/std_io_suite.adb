--  Body of IO_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Gada.Std.Errors;
with Gada.Std.IO; use Gada.Std.IO;

package body Std_IO_Suite is

   package Errors renames Gada.Std.Errors;

   use type Errors.Error_Access;

   --  In-memory io.Reader double: serves Data from Pos, then EOF.
   type Mem_Reader is new Reader with record
      Data : Unbounded_String;
      Pos  : Natural := 1;
   end record;

   overriding function Read (R : in out Mem_Reader; Data : out String;
                             N : out Natural) return Errors.Error_Access is
      Remaining : constant Natural := Length (R.Data) - R.Pos + 1;
      M         : constant Natural :=
        Natural'Min (Data'Length, Remaining);
   begin
      if Remaining <= 0 then
         N := 0;
         return EOF;
      end if;
      for I in 1 .. M loop
         Data (Data'First + I - 1) := Element (R.Data, R.Pos + I - 1);
      end loop;
      R.Pos := R.Pos + M;
      N := M;
      return Errors.No_Error;
   end Read;

   --  In-memory io.Writer double: appends everything, never fails.
   type Mem_Writer is new Writer with record
      Data : Unbounded_String;
   end record;

   overriding function Write (W : in out Mem_Writer; Data : String;
                              N : out Natural) return Errors.Error_Access is
   begin
      Append (W.Data, Data);
      N := Data'Length;
      return Errors.No_Error;
   end Write;

   --  Failing reader: hard error on the first Read.
   type Fail_Reader is new Reader with null record;

   overriding function Read (R : in out Fail_Reader; Data : out String;
                             N : out Natural) return Errors.Error_Access is
      pragma Unreferenced (R, Data);
   begin
      N := 0;
      return Errors.New_K ("read failed");
   end Read;

   --  Failing writer: hard error on every Write.
   type Fail_Writer is new Writer with null record;

   overriding function Write (W : in out Fail_Writer; Data : String;
                              N : out Natural) return Errors.Error_Access is
      pragma Unreferenced (W, Data);
   begin
      N := 0;
      return Errors.New_K ("write failed");
   end Write;

   --  Short-writing writer: reports success but writes only half.
   type Short_Writer is new Writer with null record;

   overriding function Write (W : in out Short_Writer; Data : String;
                              N : out Natural) return Errors.Error_Access is
      pragma Unreferenced (W);
   begin
      N := Data'Length / 2;
      return Errors.No_Error;
   end Write;

   function Mem_Src (S : String) return Reader_Access is
     (new Mem_Reader'(Reader with Data => To_Unbounded_String (S),
                      Pos => 1));

   overriding function Name
     (T : Std_IO_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.IO suite"));

   overriding procedure Register_Tests (T : in out Std_IO_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_EOF_Sentinel'Access, "EOF sentinel identity");
      Register_Routine (T, Test_Copy'Access, "Copy happy path");
      Register_Routine (T, Test_Copy_Empty'Access, "Copy empty source");
      Register_Routine (T, Test_Copy_Read_Error'Access, "Copy read error");
      Register_Routine (T, Test_Copy_Write_Error'Access, "Copy write error");
      Register_Routine (T, Test_Copy_Short_Write'Access,
                        "Copy short write = ErrShortWrite");
      Register_Routine (T, Test_Read_All'Access, "ReadAll + EOF");
      Register_Routine (T, Test_Read_All_Error'Access, "ReadAll hard error");
   end Register_Tests;

   procedure Test_EOF_Sentinel (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Src : constant Reader_Access := Mem_Src ("");
      Buf : String (1 .. 4);
      N   : Natural;
      E   : Errors.Error_Access;
   begin
      Assert (Errors.Is_K (EOF, EOF), "EOF Is itself");
      Assert (EOF /= Errors.No_Error, "EOF is not nil");
      E := Read (Src.all, Buf, N);
      Assert (N = 0 and Errors.Is_K (E, EOF), "empty reader returns EOF");
   end Test_EOF_Sentinel;

   procedure Test_Copy (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Src : constant Reader_Access := Mem_Src ("hello world");
      Dst : constant Writer_Access := new Mem_Writer;
      N   : Natural;
      E   : Errors.Error_Access;
   begin
      Copy (Dst, Src, N, E);
      Assert (E = Errors.No_Error, "Copy err = No_Error");
      Assert (N = 11, "Copy wrote 11 bytes, got" & Integer'Image (N));
      Assert (To_String (Mem_Writer (Dst.all).Data) = "hello world",
              "Copy content");
   end Test_Copy;

   procedure Test_Copy_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Src : constant Reader_Access := Mem_Src ("");
      Dst : constant Writer_Access := new Mem_Writer;
      N   : Natural;
      E   : Errors.Error_Access;
   begin
      Copy (Dst, Src, N, E);
      Assert (E = Errors.No_Error and N = 0, "Copy of empty: 0, no error");
      Assert (Length (Mem_Writer (Dst.all).Data) = 0, "nothing written");
   end Test_Copy_Empty;

   procedure Test_Copy_Read_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Src : constant Reader_Access := new Fail_Reader;
      Dst : constant Writer_Access := new Mem_Writer;
      N   : Natural;
      E   : Errors.Error_Access;
   begin
      Copy (Dst, Src, N, E);
      Assert (E /= Errors.No_Error and not Errors.Is_K (E, EOF),
              "read error propagates");
      Assert (N = 0, "nothing written");
   end Test_Copy_Read_Error;

   procedure Test_Copy_Write_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Src : constant Reader_Access := Mem_Src ("data");
      Dst : constant Writer_Access := new Fail_Writer;
      N   : Natural;
      E   : Errors.Error_Access;
   begin
      Copy (Dst, Src, N, E);
      Assert (E /= Errors.No_Error and not Errors.Is_K (E, EOF),
              "write error propagates");
      Assert (N = 0, "failed write counts 0");
   end Test_Copy_Write_Error;

   procedure Test_Copy_Short_Write (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Src : constant Reader_Access := Mem_Src ("hello world");
      Dst : constant Writer_Access := new Short_Writer;
      N   : Natural;
      E   : Errors.Error_Access;
   begin
      Copy (Dst, Src, N, E);
      --  Go: io.Copy returns io.ErrShortWrite when the writer reports
      --  success with n < len(p); the unwritten tail is not dropped
      --  silently.
      Assert (Errors.Is_K (E, Err_Short_Write),
              "short write returns ErrShortWrite");
      Assert (N = 5, "only the 5 written bytes are counted, got"
              & Integer'Image (N));
   end Test_Copy_Short_Write;

   procedure Test_Read_All (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Src  : constant Reader_Access := Mem_Src ("all of it");
      Data : Unbounded_String;
      E    : Errors.Error_Access;
   begin
      Read_All (Src, Data, E);
      Assert (E = Errors.No_Error, "ReadAll err = No_Error (EOF swallowed)");
      Assert (To_String (Data) = "all of it", "ReadAll content");
   end Test_Read_All;

   procedure Test_Read_All_Error (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
      Src  : constant Reader_Access := new Fail_Reader;
      Data : Unbounded_String;
      E    : Errors.Error_Access;
   begin
      Read_All (Src, Data, E);
      Assert (E /= Errors.No_Error and not Errors.Is_K (E, EOF),
              "ReadAll hard error propagates (EOF not reported)");
      Assert (Length (Data) = 0, "nothing accumulated");
   end Test_Read_All_Error;

end Std_IO_Suite;
