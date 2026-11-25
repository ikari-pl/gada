--  Body of Gada.Std.Errors — see spec for the Go-semantics contract.
--
--  Ada 2022 idioms used: expression functions for the one-liners and
--  conditional expressions for the null-guarded ones.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Tags; use Ada.Tags;

package body Gada.Std.Errors is

   function New_K (Message : String) return Error_Access is
     (new Error'(Message => To_Unbounded_String (Message), Cause => null));

   function With_Cause (Message : String; Cause : Error_Access)
     return Error_Access is
     (new Error'(Message => To_Unbounded_String (Message), Cause => Cause));

   procedure Make_Base (E : out Error; Msg : String; Cause : Error_Access) is
   begin
      E := (Message => To_Unbounded_String (Msg), Cause => Cause);
   end Make_Base;

   function Message (E : Error) return String is
     (To_String (E.Message));

   function Unwrap (E : Error_Access) return Error_Access is
     (if E = null then No_Error else E.Cause);

   function Is_K (Err, Target : Error_Access) return Boolean is
   begin
      --  Go: errors.Is(nil, nil) is true; errors.Is(err, nil) is
      --  (err == nil).
      if Target = null then
         return Err = null;
      end if;
      declare
         X : Error_Access := Err;
      begin
         while X /= null loop
            if X = Target then
               return True;
            end if;
            --  Dispatching call: derived error types (e.g. strconv's
            --  Num_Error) override Unwrap to expose their own cause.
            X := Unwrap (X);
         end loop;
         return False;
      end;
   end Is_K;

   function As (Err : Error_Access; Target : not null access Error'Class)
     return Boolean is
      X : Error_Access := Err;
   begin
      while X /= null loop
         if X.all'Tag = Target.all'Tag then
            Target.all := X.all;
            return True;
         end if;
         X := Unwrap (X);
      end loop;
      return False;
   end As;

end Gada.Std.Errors;
