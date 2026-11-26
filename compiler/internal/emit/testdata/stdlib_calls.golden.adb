with Gada.Core.Panic;
with Ada.Strings.Unbounded;
with Gada.Std.Errors;
with Gada.Std.Bytes;
with Gada.Std.OS;
with Gada.Std.Strings;

package body P is

   package Panic_Of_Integer is new Gada.Core.Panic
     (Payload_Type => Integer,
      Default      => 0);

   procedure F (Path : String) is
      Data : Gada.Std.Bytes.Byte_Slice;
      Err : Gada.Std.Errors.Error_Access;
      Text : String;
      Words : Gada.Std.Strings.String_Slice;
      N : Integer;
      W : String;
      W2 : String;
   begin
      Gada.Std.OS.Read_File (Path, Data, Err);
      Text := Gada.Std.Bytes.To_String (Data);
      Words := Gada.Std.Strings.Fields (Text);
      N := Integer (Gada.Std.Strings.String_Vectors.Length (Words));
      W := Ada.Strings.Unbounded.To_String
            (Gada.Std.Strings.String_Vectors.Element (Words, 0 + 1));
      W2 := Gada.Std.Strings.Trim_Space (W);
      Gada.Std.Strings.String_Vectors.Replace_Element (Words, 0 + 1,
            Ada.Strings.Unbounded.To_Unbounded_String (W2));
      if Err /= null then
         Panic_Of_Integer.Do_Panic ("read failed");
      end if;
      if (N > 0) and (W2 /= "") then
         Panic_Of_Integer.Do_Panic ("nonempty");
      end if;
   exception
      when Panic_Of_Integer.Panicking =>
         if Panic_Of_Integer.Is_Panicking then
            raise;
         end if;
   end F;

end P;
