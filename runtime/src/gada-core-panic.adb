--  Gada.Core.Panic body — see spec for design.
--
--  The pending-panic stack lives at package-body scope. It's a
--  fixed-capacity array (16 entries) so Do_Panic does no
--  allocation; that ceiling matches Go's practical recursion-
--  during-panic depth and is documented in ADR-0006.
--
--  v1 single-threaded runtime: one global stack. Phase 3 promotes
--  this to per-task storage when the goroutine scheduler lands.

package body Gada.Core.Panic is

   --  Cap chosen to comfortably exceed any sane nested-panic
   --  depth a transpiled Go program could produce. Doubling is a
   --  one-line change if a future workload demands it; tracked in
   --  docs/imperfections.md.
   Max_Pending_Panics : constant := 16;

   Pending : array (1 .. Max_Pending_Panics) of Payload_Type :=
     (others => Default);
   Pending_Count : Natural := 0;

   procedure Do_Panic (Value : Payload_Type) is
   begin
      --  Bounded — overflow is a programmer error, not a runtime
      --  contract; raise Constraint_Error to surface it loudly.
      if Pending_Count >= Max_Pending_Panics then
         raise Constraint_Error
           with "Gada.Core.Panic: pending-panic stack overflow"
                & " (depth >" & Max_Pending_Panics'Image & ")";
      end if;
      Pending_Count := @ + 1;
      Pending (Pending_Count) := Value;
      raise Panicking;
   end Do_Panic;

   function Recover return Payload_Type is
      V : Payload_Type;
   begin
      if Pending_Count = 0 then
         return Default;
      end if;
      V := Pending (Pending_Count);
      Pending (Pending_Count) := Default;  -- drop reference
      Pending_Count := @ - 1;
      return V;
   end Recover;

   function Is_Panicking return Boolean is
     (Pending_Count > 0);

end Gada.Core.Panic;
