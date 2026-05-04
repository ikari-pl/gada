--  Body of Gada.Async.Selector — see spec for semantics.
--
--  ## Algorithm sketch
--
--  Select_One:
--    1. Validate input (Cases'Length >= 1; <= 1 Default_Op).
--    2. Identify the Default index (if any) and the Timeout deadline
--       (earliest Timeout_Op's deadline, if any).
--    3. Poll loop:
--         a. Build a shuffled order over Cases'Range (Fisher-Yates
--            over a fresh seed; cheap because Cases'Length is small).
--         b. For each case in shuffled order, attempt Try_Op:
--              - Send_Op: Bnd.Try_Send. If Sent, return the index.
--              - Recv_Op: Bnd.Try_Receive. If Got (with OK either
--                value), write back to the out pointers and return.
--              - Default_Op / Timeout_Op: skipped in the inner pass.
--         c. After the pass, if no case fired:
--              * If Default_Op present, return its index immediately.
--              * If Timeout deadline reached, return the
--                earliest-deadline Timeout_Op index.
--              * Else delay Poll_Interval and continue.
--
--  ## Random seed
--
--  Each Select_One call seeds an Ada.Numerics.Float_Random.Generator
--  from clock + Goroutine_Id so the shuffle differs per call AND
--  per goroutine. The 32-bit XOR is enough for a Fisher-Yates over
--  cases'length <= 64 (typical select sizes are 2-4).

with Ada.Numerics.Float_Random;
with Ada.Real_Time;
use Ada.Real_Time;

package body Gada.Async.Selector is

   --  Permutation array; resized via slicing in Select_One. Static
   --  upper bound matches Go's runtime cap (Go itself does not
   --  enforce a hard limit, but more than ~64 cases in a single
   --  select is a code smell — and we use the array as a stack
   --  local so size matters).
   Max_Cases : constant := 64;
   subtype Case_Index is Positive range 1 .. Max_Cases;
   type Index_Array is array (Case_Index range <>) of Positive;

   procedure Shuffle
     (A   : in out Index_Array;
      Gen : in out Ada.Numerics.Float_Random.Generator);
   procedure Try_One_Case
     (Case_Item_Ref : Case_Item;
      Fired         : out Boolean);
   procedure Validate_And_Scan
     (Cases             : Case_Array;
      Default_Index     : out Natural;
      Earliest_Timeout  : out Time;
      Timeout_Index     : out Natural);

   --  Fisher-Yates shuffle in place. Iterates from the back; each
   --  iteration swaps A (I) with A (Rand 1..I). With Cases'Length
   --  <= Max_Cases small, the inline-loop body is faster than a
   --  Discrete_Random over a subtype that would change every call.
   procedure Shuffle
     (A   : in out Index_Array;
      Gen : in out Ada.Numerics.Float_Random.Generator)
   is
      use Ada.Numerics.Float_Random;
      J : Positive;
      T : Positive;
   begin
      for I in reverse A'First + 1 .. A'Last loop
         --  Pick J in A'First .. I uniformly.
         J :=
           A'First
           + Natural (Float'Floor
               (Random (Gen) * Float (I - A'First + 1)));
         if J > I then
            J := I; -- defensive cap on float-rounding edges
         end if;
         T := A (I);
         A (I) := A (J);
         A (J) := T;
      end loop;
   end Shuffle;

   --  Try one case in isolation. Returns Fired => True if the case
   --  succeeded (and writes the result back via the case's out
   --  pointers). Default and Timeout cases are skipped here — the
   --  outer loop handles them.
   procedure Try_One_Case
     (Case_Item_Ref : Case_Item;
      Fired         : out Boolean)
   is
      Got  : Boolean;
      OK   : Boolean;
      Sent : Boolean;
      V_Tmp : Element_Type;
   begin
      Fired := False;
      case Case_Item_Ref.Kind is
         when Send_Op =>
            Bnd.Try_Send (Case_Item_Ref.Chan, Case_Item_Ref.Send_V, Sent);
            Fired := Sent;

         when Recv_Op =>
            --  Initialise V_Tmp from the user's out-pointer (if
            --  any) so the in-out contract preserves the call-site
            --  value on the closed-empty path. The user's pointer
            --  may be null for a discard-recv (`<-ch`); fall back
            --  to the formal default in that case.
            if Case_Item_Ref.Recv_V_Out /= null then
               V_Tmp := Case_Item_Ref.Recv_V_Out.all;
            end if;
            Bnd.Try_Receive
              (C   => Case_Item_Ref.Chan,
               V   => V_Tmp,
               OK  => OK,
               Got => Got);
            if Got then
               if Case_Item_Ref.Recv_V_Out /= null then
                  Case_Item_Ref.Recv_V_Out.all := V_Tmp;
               end if;
               if Case_Item_Ref.Recv_OK_Out /= null then
                  Case_Item_Ref.Recv_OK_Out.all := OK;
               end if;
               Fired := True;
            end if;

         when Default_Op | Timeout_Op =>
            Fired := False;
      end case;
   end Try_One_Case;

   --  Validate the case array. Returns the Default index (or 0 if
   --  absent) and the deadline of the earliest Timeout_Op (or
   --  Time_Last if absent). Raises Selector_Error on >1 Default
   --  case or empty array.
   procedure Validate_And_Scan
     (Cases             : Case_Array;
      Default_Index     : out Natural;
      Earliest_Timeout  : out Time;
      Timeout_Index     : out Natural)
   is
   begin
      if Cases'Length = 0 then
         raise Selector_Error with
           "Gada.Async.Selector.Select_One: empty case array — would "
           & "deadlock the goroutine indefinitely";
      end if;

      Default_Index := 0;
      Earliest_Timeout := Time_Last;
      Timeout_Index := 0;

      for I in Cases'Range loop
         case Cases (I).Kind is
            when Default_Op =>
               if Default_Index /= 0 then
                  raise Selector_Error with
                    "Gada.Async.Selector.Select_One: more than one "
                    & "Default_Op in the case array (Go's compiler "
                    & "rejects this; runtime catches it as a last "
                    & "line of defence)";
               end if;
               Default_Index := I;

            when Timeout_Op =>
               declare
                  Deadline : constant Time :=
                    Clock + To_Time_Span (Cases (I).Timeout_Duration);
               begin
                  if Deadline < Earliest_Timeout then
                     Earliest_Timeout := Deadline;
                     Timeout_Index := I;
                  end if;
               end;

            when Send_Op | Recv_Op =>
               null;
         end case;
      end loop;
   end Validate_And_Scan;

   ---------------------------------------------------------------

   function Select_One (Cases : Case_Array) return Positive is
      use Ada.Numerics.Float_Random;
      Gen              : Generator;
      Default_Index    : Natural;
      Timeout_Index    : Natural;
      Earliest_Timeout : Time;
      Fired            : Boolean;
   begin
      Validate_And_Scan
        (Cases, Default_Index, Earliest_Timeout, Timeout_Index);

      --  Bound check — protects the static Index_Array allocation.
      if Cases'Length > Max_Cases then
         raise Selector_Error with
           "Gada.Async.Selector.Select_One: more than"
           & Max_Cases'Image
           & " cases in a single select; lift Max_Cases or split "
           & "into nested selects";
      end if;

      Reset (Gen);

      --  Build the index permutation. We start with the identity
      --  permutation over Cases'Range, then Fisher-Yates shuffle.
      declare
         Order : Index_Array (1 .. Cases'Length);
      begin
         for I in Order'Range loop
            Order (I) := Cases'First + I - 1;
         end loop;

         loop
            --  Fresh shuffle each polling iteration so a stuck
            --  case at one position doesn't starve the others.
            Shuffle (Order, Gen);

            for I in Order'Range loop
               declare
                  Idx : constant Positive := Order (I);
               begin
                  --  Skip Default and Timeout in the active-case
                  --  scan; they're outer-loop fallbacks.
                  if Cases (Idx).Kind not in Default_Op | Timeout_Op then
                     Try_One_Case (Cases (Idx), Fired);
                     if Fired then
                        return Idx;
                     end if;
                  end if;
               end;
            end loop;

            --  No active case fired this pass. Fall back to
            --  Default if present (Go's `default:` is "no other
            --  case ready right now").
            if Default_Index /= 0 then
               return Default_Index;
            end if;

            --  Timeout check: if any Timeout_Op's deadline has
            --  passed, fire it. Earliest-deadline-first; ties go
            --  to lower index (deterministic for the test gate).
            if Timeout_Index /= 0
              and then Clock >= Earliest_Timeout
            then
               return Timeout_Index;
            end if;

            --  Otherwise wait a tick and retry. delay yields the
            --  worker (Ada delay statement is a synchronous block,
            --  so siblings on the same OS thread continue).
            delay Poll_Interval;
         end loop;
      end;
   end Select_One;

end Gada.Async.Selector;
