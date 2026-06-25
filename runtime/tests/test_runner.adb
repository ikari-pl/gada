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
with Slices_Suite;
with Defer_Suite;
with Panic_Suite;
with Maps_Suite;
with Hash_Suite;
with Stress_Gc_Suite;
with Stress_Scheduler_Suite;
with Stress_Goroutines_Suite;
with Context_Suite;
with Scheduler_Suite;
with Channels_Suite;
with Channels_Unbounded_Suite;
with Selector_Suite;
with Race_Suite;
with Reflect_Types_Suite;
with Reflect_Suite;
with Reflect_Values_Suite;

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
      or else Pkg = "core.memory"
      or else Pkg = "core.slices"
      or else Pkg = "core.defer"
      or else Pkg = "core.panic"
      or else Pkg = "core.maps"
      or else Pkg = "core.hash"
      or else Pkg = "async.context"
      or else Pkg = "async.scheduler"
      or else Pkg = "async.channels.bounded"
      or else Pkg = "async.channels.unbounded"
      or else Pkg = "async.select"
      or else Pkg = "async.race"
      or else Pkg = "reflect.type"
      or else Pkg = "reflect"
      or else Pkg = "reflect.values"
      or else Pkg = "stress.gc"
      or else Pkg = "stress.scheduler"
      or else Pkg = "stress.goroutines");

   --  Suites under the `stress.*` namespace are *opt-in*: an
   --  unfiltered `make test` (the default `make ci` path) skips
   --  them so the PR-time runtime stays bounded; `make test
   --  PKG=stress.gc` runs them. The filter shape mirrors the
   --  intent expressed in roadmap/02-core-runtime.md item 10.
   function Is_Stress (Pkg : String) return Boolean is
     (Pkg'Length >= 7 and then Pkg (Pkg'First .. Pkg'First + 6) = "stress.");

   function Should_Register (Pkg : String) return Boolean is
     (if Selected_Pkg = "" then not Is_Stress (Pkg)
      else Selected_Pkg = Pkg);

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
      if Should_Register ("core.slices") then
         Add_Test (Result, new Slices_Suite.Slices_Test);
      end if;
      if Should_Register ("core.defer") then
         Add_Test (Result, new Defer_Suite.Defer_Test);
      end if;
      if Should_Register ("core.panic") then
         Add_Test (Result, new Panic_Suite.Panic_Test);
      end if;
      if Should_Register ("core.maps") then
         Add_Test (Result, new Maps_Suite.Maps_Test);
      end if;
      if Should_Register ("core.hash") then
         Add_Test (Result, new Hash_Suite.Hash_Test);
      end if;
      if Should_Register ("async.context") then
         Add_Test (Result, new Context_Suite.Context_Test);
      end if;
      if Should_Register ("async.scheduler") then
         Add_Test (Result, new Scheduler_Suite.Scheduler_Test);
      end if;
      if Should_Register ("async.channels.bounded") then
         Add_Test (Result, new Channels_Suite.Channels_Test);
      end if;
      if Should_Register ("async.channels.unbounded") then
         Add_Test
           (Result,
            new Channels_Unbounded_Suite.Channels_Unbounded_Test);
      end if;
      if Should_Register ("async.select") then
         Add_Test (Result, new Selector_Suite.Selector_Test);
      end if;
      if Should_Register ("async.race") then
         Add_Test (Result, new Race_Suite.Race_Test);
      end if;
      if Should_Register ("reflect.type") then
         Add_Test (Result, new Reflect_Types_Suite.Reflect_Types_Test);
      end if;
      if Should_Register ("reflect") then
         Add_Test (Result, new Reflect_Suite.Reflect_Test);
      end if;
      if Should_Register ("reflect.values") then
         Add_Test (Result, new Reflect_Values_Suite.Reflect_Values_Test);
      end if;
      if Should_Register ("stress.gc") then
         Add_Test (Result, new Stress_Gc_Suite.Stress_Gc_Test);
      end if;
      if Should_Register ("stress.scheduler") then
         Add_Test
           (Result,
            new Stress_Scheduler_Suite.Stress_Scheduler_Test);
      end if;
      if Should_Register ("stress.goroutines") then
         Add_Test
           (Result,
            new Stress_Goroutines_Suite.Stress_Goroutines_Test);
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
         & "'. Known suites: core.io, core.memory, core.slices,"
         & " core.defer, core.panic, core.maps, core.hash,"
         & " async.context, async.scheduler, async.channels.bounded,"
         & " async.channels.unbounded, async.select, async.race,"
         & " reflect.type, reflect, reflect.values,"
         & " stress.gc, stress.scheduler, stress.goroutines.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;
   Run (Reporter);
end Test_Runner;
