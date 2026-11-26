--  Body of Fmt_Suite — see spec for test rationale.
pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded;
with System;
with Gada.Core.IO;
with Gada.Std.Errors;
with Gada.Std.Fmt; use Gada.Std.Fmt;

package body Fmt_Suite is

   package Errors renames Gada.Std.Errors;

   use type Errors.Error_Access;

   overriding function Name
     (T : Fmt_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Fmt suite"));

   overriding procedure Register_Tests (T : in out Fmt_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Sprintf_Int'Access, "Sprintf integers");
      Register_Routine (T, Test_Sprintf_Str_Bool'Access, "Sprintf str/bool");
      Register_Routine (T, Test_Sprintf_Float'Access, "Sprintf floats");
      Register_Routine (T, Test_Sprintf_Misc'Access, "Sprintf misc/badverb");
      Register_Routine (T, Test_Errorf'Access, "Errorf + %w");
      Register_Routine (T, Test_Sscanf'Access, "Sscanf");
      Register_Routine (T, Test_Print_Family'Access, "Print/Println/Printf");
      Register_Routine (T, Test_Edges'Access, "bad verbs, Sscanf edges");
   end Register_Tests;

   procedure Test_Sprintf_Int (T : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Sprintf ("%d", (1 => A (42))) = "42", "%d");
      Assert (Sprintf ("%d", (1 => A (-7))) = "-7", "%d negative");
      Assert (Sprintf ("%5d", (1 => A (42))) = "   42", "%5d width");
      Assert (Sprintf ("%-5d|", (1 => A (42))) = "42   |", "%-5d left");
      Assert (Sprintf ("%05d", (1 => A (-42))) = "-0042", "%05d zero pad");
      Assert (Sprintf ("%+d", (1 => A (42))) = "+42", "%+d");
      Assert (Sprintf ("% d", (1 => A (42))) = " 42", "% d space");
      Assert (Sprintf ("%x", (1 => A (255))) = "ff", "%x");
      Assert (Sprintf ("%X", (1 => A (255))) = "FF", "%X");
      Assert (Sprintf ("%#x", (1 => A (255))) = "0xff", "%#x");
      Assert (Sprintf ("%#08x", (1 => A (255))) = "0x0000ff", "%#08x");
      Assert (Sprintf ("%b", (1 => A (5))) = "101", "%b");
      Assert (Sprintf ("%o", (1 => A (8))) = "10", "%o");
      Assert (Sprintf ("%c", (1 => A (65))) = "A", "%c");
      Assert (Sprintf ("%v", (1 => A (42))) = "42", "%v int");
      Assert (Sprintf ("100%%", (1 .. 0 => A (0))) = "100%", "%%");
   end Test_Sprintf_Int;

   procedure Test_Sprintf_Str_Bool (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Sprintf ("%s", (1 => A ("hi"))) = "hi", "%s");
      Assert (Sprintf ("%5s|", (1 => A ("hi"))) = "   hi|", "%5s");
      Assert (Sprintf ("%-5s|", (1 => A ("hi"))) = "hi   |", "%-5s");
      Assert (Sprintf ("%.1s", (1 => A ("hello"))) = "h", "%.1s trunc");
      Assert (Sprintf ("%q", (1 => A ("a" & '"' & "b"))) = """a\""b""",
              "%q");
      Assert (Sprintf ("%t", (1 => A (True))) = "true", "%t true");
      Assert (Sprintf ("%v", (1 => A (False))) = "false", "%v bool");
      Assert (Sprintf ("%s %d", (1 => A ("x"), 2 => A (7))) = "x 7",
              "two args");
   end Test_Sprintf_Str_Bool;

   procedure Test_Sprintf_Float (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      Assert (Sprintf ("%f", (1 => A (3.14159))) = "3.141590", "%f dflt 6");
      Assert (Sprintf ("%.2f", (1 => A (3.14159))) = "3.14", "%.2f");
      Assert (Sprintf ("%e", (1 => A (31415.9))) = "3.141590e+04", "%e");
      Assert (Sprintf ("%g", (1 => A (3.14))) = "3.14", "%g");
      Assert (Sprintf ("%v", (1 => A (100000.0))) = "100000", "%v float");
   end Test_Sprintf_Float;

   procedure Test_Sprintf_Misc (T : in out AUnit.Test_Cases.Test_Case'Class) is
      E : constant Errors.Error_Access := Errors.New_K ("boom");
   begin
      declare
         P : constant String := Sprintf ("%p", (1 => A (E.all'Address)));
      begin
         Assert (P'Length >= 2 and then P (1) = '0' and then P (2) = 'x',
                 "%p is 0x…: " & P);
      end;
      Assert (Sprintf ("%v", (1 => A (E))) = "boom", "%v error");
      Assert (Sprintf ("%s", (1 => A (E))) = "boom", "%s error");
      Assert (Sprintf ("%z", (1 => A (1))) = "%!z(BADVERB)", "bad verb");
      Assert (Sprintf ("%d", (1 .. 0 => A (0))) = "%!(NOVERB)",
              "missing arg");
      Assert (Sprintf ("%c", (1 => A ('x'))) = "x", "%c char arg");
   end Test_Sprintf_Misc;

   procedure Test_Errorf (T : in out AUnit.Test_Cases.Test_Case'Class) is
      E   : constant Errors.Error_Access := Errors.New_K ("root cause");
      Err : Errors.Error_Access;
   begin
      Err := Errorf ("bad %d", (1 => A (1)));
      Assert (Errors.Message (Err.all) = "bad 1", "Errorf message");
      Assert (Errors.Unwrap (Err) = Errors.No_Error, "no %w: no cause");
      Err := Errorf ("wrap: %w", (1 => A (E)));
      Assert (Errors.Message (Err.all) = "wrap: root cause",
              "Errorf %w message");
      Assert (Errors.Is_K (Err, E), "%w wraps as the cause");
   end Test_Errorf;

   procedure Test_Sscanf (T : in out AUnit.Test_Cases.Test_Case'Class) is
      Args : Arg_Array (1 .. 4) :=
        (1 => (Int_Arg, 0), 2 => A (""), 3 => A (0.0), 4 => A (False));
      N    : Natural;
      Err  : Errors.Error_Access;
   begin
      Sscanf ("42 hello 3.5 true", "%d %s %f %t", Args, N, Err);
      Assert (Err = Errors.No_Error and N = 4, "Sscanf ok");
      Assert (Args (1).I = 42, "int parsed");
      Assert (Ada.Strings.Unbounded.To_String (Args (2).S) = "hello",
              "string parsed");
      Assert (Args (3).F = 3.5, "float parsed");
      Assert (Args (4).B, "bool parsed");
      --  Error paths.
      declare
         A2 : Arg_Array (1 .. 1) := (1 => (Int_Arg, 0));
      begin
         Sscanf ("xyz", "%d", A2, N, Err);
         Assert (Err /= Errors.No_Error and N = 0, "bad integer errors");
         Sscanf ("", "%d", A2, N, Err);
         Assert (Err /= Errors.No_Error, "EOF errors");
      end;
   end Test_Sscanf;

   procedure Test_Print_Family (T : in out
      AUnit.Test_Cases.Test_Case'Class) is
   begin
      --  Smoke test: writes to standard output; covers the code paths.
      Print ((1 => A ("a"), 2 => A (1)));
      Gada.Core.IO.New_Line;
      Println ((1 => A ("b")));
      Printf ("%d-%s" & Character'Val (10), (1 => A (7), 2 => A ("z")));
   end Test_Print_Family;

   procedure Test_Edges (T : in out AUnit.Test_Cases.Test_Case'Class) is
      E   : constant Errors.Error_Access := Errors.New_K ("e");
      N   : Natural;
      Err : Errors.Error_Access;
   begin
      Assert (Sprintf ("%d", (1 => A (0))) = "0", "%d of 0");
      Assert (Sprintf ("%05d", (1 => A (42))) = "00042", "%05d no sign");
      Assert (Sprintf ("%p", (1 => A (System.Null_Address))) = "0x0",
              "%p of null");
      Assert (Sprintf ("%q", (1 => A ('x'))) = '"' & 'x' & '"',
              "%q of char");
      --  One bad verb per argument kind (each kind's others arm).
      Assert (Sprintf ("%s", (1 => A (1.5))) = "%!s(BADVERB)", "float %s");
      Assert (Sprintf ("%d", (1 => A ("x"))) = "%!d(BADVERB)", "str %d");
      Assert (Sprintf ("%d", (1 => A (True))) = "%!d(BADVERB)", "bool %d");
      Assert (Sprintf ("%d", (1 => A ('x'))) = "%!d(BADVERB)", "char %d");
      Assert (Sprintf ("%d", (1 => A (System.Null_Address)))
                = "%!d(BADVERB)", "ptr %d");
      Assert (Sprintf ("%d", (1 => A (E))) = "%!d(BADVERB)", "err %d");
      --  Sscanf edges.
      declare
         None : Arg_Array (1 .. 0) := (others => A (0));
      begin
         Sscanf ("100", "%%", None, N, Err);
         Assert (Err = Errors.No_Error and N = 0, "literal %%");
      end;
      declare
         One : Arg_Array (1 .. 1) := (1 => (Int_Arg, 0));
      begin
         Sscanf ("1", "%d %d", One, N, Err);
         Assert (Err /= Errors.No_Error, "not enough args");
         Sscanf ("1", "%z", One, N, Err);
         Assert (Err /= Errors.No_Error, "unsupported verb");
         Sscanf ("x", "%s", One, N, Err);
         Assert (Err /= Errors.No_Error, "%s into int kind");
         Sscanf ("1.5", "%f", One, N, Err);
         Assert (Err /= Errors.No_Error, "%f into int kind");
      end;
      declare
         B : Arg_Array (1 .. 1) := (1 => A (""));
      begin
         Sscanf ("true", "%t", B, N, Err);
         Assert (Err /= Errors.No_Error, "%t into str kind");
      end;
      declare
         C : Arg_Array (1 .. 1) := (1 => A (' '));
      begin
         Sscanf ("x", "%c", C, N, Err);
         Assert (Err = Errors.No_Error and N = 1 and C (1).C = 'x',
                 "%c parses one char");
      end;
      declare
         D : Arg_Array (1 .. 1) := (1 => A (""));
      begin
         Sscanf ("1", "%d", D, N, Err);
         Assert (Err /= Errors.No_Error, "%d into str kind errors");
      end;
      declare
         F : Arg_Array (1 .. 1) := (1 => A (0.0));
      begin
         Sscanf ("abc", "%f", F, N, Err);
         Assert (Err /= Errors.No_Error, "%f unparseable token errors");
      end;
      declare
         I1 : Arg_Array (1 .. 1) := (1 => (Int_Arg, 0));
      begin
         Sscanf ("x", "%c", I1, N, Err);
         Assert (Err /= Errors.No_Error, "%c into int kind errors");
      end;
   end Test_Edges;

end Fmt_Suite;
