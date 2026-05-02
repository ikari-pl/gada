--  Test_Runner — entry point of the AUnit harness.
--
--  Builds a single suite (`Gada_Suite`) that aggregates every per-package
--  test suite shipped in this runtime crate, then dispatches to AUnit's
--  generic `Test_Runner` to drive it. Exit code: 0 if all suites pass,
--  non-zero otherwise (AUnit-defined).
--
--  Optional command-line argument: a suite-name filter (e.g. "core.io")
--  forwarded by `tests/run_tests.sh` from `make -C runtime test PKG=...`.
--  Empty / absent = run every registered suite. An unrecognised filter
--  exits non-zero with a message naming the unknown PKG so a typo in CI
--  fails loudly instead of silently registering zero suites.

--  Suppress GNAT's `-gnatw_a` warning on the AUnit `new IO_Suite.IO_Test`
--  / `new Memory_Suite.Memory_Test` allocators. The pattern is the
--  AUnit-documented way to register a Test_Case subtype and produces
--  an anonymous access value that AUnit's `Add_Test` accepts; refusing
--  it would mean refactoring against the framework. Scoped to this
--  unit so the warning still fires on real anonymous-access misuse
--  elsewhere in the runtime.
pragma Warnings (Off, "use of an anonymous access type allocator");

with Ada.Command_Line;
with Ada.Text_IO;

with AUnit.Run;
with AUnit.Reporter.Text;
with AUnit.Test_Suites; use AUnit.Test_Suites;

with IO_Suite;
with Memory_Suite;

procedure Test_Runner is

   --  Selected_Pkg captures the optional first command-line arg. The
   --  builder generic `AUnit.Run.Test_Runner` instantiates a closure
   --  over `Gada_Suite`, which in turn reads this constant — that's why
   --  it lives at the procedure scope rather than inside Gada_Suite.
   Selected_Pkg : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1)
      else "");

   --  All known suite names. When Selected_Pkg is non-empty and not in
   --  this set, we fail fast — silently registering nothing would let a
   --  CI typo masquerade as success.
   function Is_Known (Pkg : String) return Boolean is
     (Pkg = ""
      or else Pkg = "core.io"
      or else Pkg = "core.memory");

   function Should_Register (Pkg : String) return Boolean is
     (Selected_Pkg = "" or else Selected_Pkg = Pkg);

   function Gada_Suite return Access_Test_Suite;
   --  Aggregator returning every per-package suite shipped in this
   --  runtime crate. AUnit.Run.Test_Runner is generic over a function
   --  of exactly this signature.

   function Gada_Suite return Access_Test_Suite is
      Result : constant Access_Test_Suite := New_Suite;
   begin
      if Should_Register ("core.io") then
         Add_Test (Result, new IO_Suite.IO_Test);
      end if;
      if Should_Register ("core.memory") then
         Add_Test (Result, new Memory_Suite.Memory_Test);
      end if;
      return Result;
   end Gada_Suite;

   procedure Run is new AUnit.Run.Test_Runner (Gada_Suite);

   Reporter : AUnit.Reporter.Text.Text_Reporter;

begin
   if not Is_Known (Selected_Pkg) then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "test_runner: unknown PKG filter '" & Selected_Pkg
         & "'. Known suites: core.io, core.memory.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;
   Run (Reporter);
end Test_Runner;
