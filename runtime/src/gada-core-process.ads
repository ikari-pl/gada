--  Gada.Core.Process — Go process-exit semantics for generated mains.
--
--  Go ends the process as soon as main returns: goroutines still
--  running, parked or sleeping, and pending timers, are simply
--  abandoned. Ada instead makes the environment task wait for every
--  library-level task before the program ends (and an unhandled
--  exception in the main subprogram waits the same way before the
--  last-chance handler reports it), so a generated main that merely
--  returned would hang on a parked goroutine or a live ticker. The
--  generated main therefore finishes through this package
--  (docs/adr/0011-go-main-return-exit.md):
--
--    * Exit_Main — main's body and defers completed: flush standard
--      output/error and terminate with status 0 at once.
--    * Unhandled — an unrecovered panic (or any other exception)
--      escaped main: print the message GNAT's last-chance handler
--      would have printed ("raised NAME : message") to standard
--      error and terminate with Go's panic status, 2.
--
--  Lives in Gada.Core (not Gada.Async) so programs without goroutines
--  still link without the scheduler.

with Ada.Exceptions;

package Gada.Core.Process is

   --  Go's exit status for an unrecovered panic / runtime error.
   Panic_Exit_Status : constant := 2;

   --  Flush Ada.Text_IO's standard output and error, then terminate
   --  the process with Code via the exit handler (GNAT.OS_Lib.OS_Exit
   --  unless a test installed another). Does not wait for any task.
   procedure Finish (Code : Integer);

   --  Go: main returned normally. Finish (0).
   procedure Exit_Main;

   --  Go: a panic escaped main. Report E on standard error in GNAT's
   --  unhandled-exception format, then Finish (Panic_Exit_Status).
   procedure Unhandled (E : Ada.Exceptions.Exception_Occurrence);

   --  Test seam: the procedure Finish calls last. The default (null)
   --  is GNAT.OS_Lib.OS_Exit; AUnit installs one that records the code
   --  and raises, since a real exit would end the test runner.
   type Exit_Handler is access procedure (Code : Integer);
   procedure Set_Exit_Handler (H : Exit_Handler);

end Gada.Core.Process;
