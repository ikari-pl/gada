--  Reflect_Suite body — see spec.
--
--  The registry is process-wide and persists across the suite's tests,
--  so each test uses its own high, otherwise-unused Type_Id to stay
--  independent of registration order and of any future suite that
--  registers types in the same runner.

with AUnit.Assertions; use AUnit.Assertions;

with Gada.Reflect.Registry;
with Gada.Reflect.Types; use Gada.Reflect.Types;

package body Reflect_Suite is

   procedure Test_Register_Then_Lookup
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Pt : Type_Descriptor := Make (Id => 9001, Name => "Point",
                                    Kind => Struct_Kind);
   begin
      Add_Field (Pt, "X", Field_Type => 1);
      Add_Field (Pt, "Y", Field_Type => 1);
      Gada.Reflect.Registry.Register_Type (Pt);

      declare
         Got : constant Type_Descriptor := Gada.Reflect.Registry.Lookup (9001);
      begin
         Assert (Got = Pt, "Lookup must return the registered descriptor");
         Assert (Name (Got) = "Point", "round-tripped name");
         Assert (Kind (Got) = Struct_Kind, "round-tripped kind");
         Assert (Num_Fields (Got) = 2, "round-tripped fields");
      end;
   end Test_Register_Then_Lookup;

   procedure Test_Lookup_Unknown_Is_Invalid
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Got : constant Type_Descriptor := Gada.Reflect.Registry.Lookup (987654);
   begin
      --  Go's zero reflect.Type: Invalid kind, no identity.
      Assert (Kind (Got) = Invalid_Kind,
              "an unregistered Id looks up as Invalid_Kind");
      Assert (Id (Got) = No_Type,
              "the zero descriptor carries No_Type identity");
   end Test_Lookup_Unknown_Is_Invalid;

   procedure Test_Duplicate_Register_Last_Wins
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First  : constant Type_Descriptor :=
        Make (Id => 9002, Name => "V1", Kind => Int_Kind);
      Second : constant Type_Descriptor :=
        Make (Id => 9002, Name => "V2", Kind => String_Kind);
   begin
      Gada.Reflect.Registry.Register_Type (First);
      Gada.Reflect.Registry.Register_Type (Second);

      declare
         Got : constant Type_Descriptor := Gada.Reflect.Registry.Lookup (9002);
      begin
         Assert (Name (Got) = "V2" and Kind (Got) = String_Kind,
                 "re-registering an Id replaces the prior descriptor "
                 & "(last-wins); got Name=" & Name (Got));
      end;
   end Test_Duplicate_Register_Last_Wins;

   overriding procedure Register_Tests (T : in out Reflect_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Register_Then_Lookup'Access,
         "Register_Type then Lookup round-trips the descriptor by Id");
      Register_Routine
        (T, Test_Lookup_Unknown_Is_Invalid'Access,
         "Lookup of an unregistered Id returns the Invalid_Kind zero "
         & "descriptor (Go's zero reflect.Type)");
      Register_Routine
        (T, Test_Duplicate_Register_Last_Wins'Access,
         "Registering the same Id twice replaces the prior descriptor");
   end Register_Tests;

   overriding function Name (T : Reflect_Test) return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Gada.Reflect registry suite");
   end Name;

end Reflect_Suite;
