--  Body of Gada.Std.Bytes — see spec for the Go-semantics contract.

with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Gada.Std.Strings;

package body Gada.Std.Bytes is

   use type Ada.Containers.Count_Type;

   function New_Bytes (N : Natural) return Byte_Slice is
      V : Byte_Slice := Byte_Vectors.Empty_Vector;
   begin
      Byte_Vectors.Reserve_Capacity (V, Ada.Containers.Count_Type (N));
      for I in 1 .. N loop
         Byte_Vectors.Append (V, Character'Val (0));
      end loop;
      return V;
   end New_Bytes;

   function To_Bytes (S : String) return Byte_Slice is
      R : Byte_Slice;
   begin
      for C of S loop
         Byte_Vectors.Append (R, C);
      end loop;
      return R;
   end To_Bytes;

   function To_String (B : Byte_Slice) return String is
      R : String (1 .. Integer (Byte_Vectors.Length (B)));
   begin
      for I in R'Range loop
         R (I) := Byte_Vectors.Element (B, I);
      end loop;
      return R;
   end To_String;

   function Equal (A, B : Byte_Slice) return Boolean is
      use Byte_Vectors;
   begin
      if Length (A) /= Length (B) then
         return False;
      end if;
      for I in 1 .. Integer (Length (A)) loop
         if Element (A, I) /= Element (B, I) then
            return False;
         end if;
      end loop;
      return True;
   end Equal;

   function Compare (A, B : Byte_Slice) return Integer is
      use Byte_Vectors;
      N : constant Natural :=
        Natural'Min (Integer (Length (A)), Integer (Length (B)));
   begin
      for I in 1 .. N loop
         if Element (A, I) < Element (B, I) then
            return -1;
         elsif Element (A, I) > Element (B, I) then
            return 1;
         end if;
      end loop;
      if Length (A) < Length (B) then
         return -1;
      elsif Length (A) > Length (B) then
         return 1;
      end if;
      return 0;
   end Compare;

   function Index (S, Sub : Byte_Slice) return Integer is
      I : Natural;
   begin
      if Byte_Vectors.Length (Sub) = 0 then
         return 0;  --  Go: bytes.Index(s, nil) = 0
      end if;
      I := Ada.Strings.Fixed.Index (To_String (S), To_String (Sub));
      if I = 0 then
         return -1;
      end if;
      return I - 1;
   end Index;

   function Contains (S, Sub : Byte_Slice) return Boolean is
   begin
      return Index (S, Sub) >= 0;
   end Contains;

   function Has_Prefix (S, Prefix : Byte_Slice) return Boolean is
      N : constant Integer := Integer (Byte_Vectors.Length (Prefix));
   begin
      if Integer (Byte_Vectors.Length (S)) < N then
         return False;
      end if;
      return To_String (S) (1 .. N) = To_String (Prefix);
   end Has_Prefix;

   function Has_Suffix (S, Suffix : Byte_Slice) return Boolean is
      N : constant Integer := Integer (Byte_Vectors.Length (Suffix));
      L : constant Integer := Integer (Byte_Vectors.Length (S));
   begin
      if L < N then
         return False;
      end if;
      return To_String (S) (L - N + 1 .. L) = To_String (Suffix);
   end Has_Suffix;

   function Split (S, Sep : Byte_Slice) return Byte_Slice_List is
      use Gada.Std.Strings;
      Parts : constant String_Vectors.Vector :=
        Gada.Std.Strings.Split (To_String (S), To_String (Sep));
      R     : Byte_Slice_List;
   begin
      for I in 1 .. Integer (String_Vectors.Length (Parts)) loop
         Byte_Slice_Vectors.Append
           (R, To_Bytes (Ada.Strings.Unbounded.To_String
                           (String_Vectors.Element (Parts, I))));
      end loop;
      return R;
   end Split;

   function Join (Parts : Byte_Slice_List; Sep : Byte_Slice)
      return Byte_Slice is
      R : Byte_Slice;
      procedure Append_All (X : Byte_Slice) is
      begin
         for I in 1 .. Integer (Byte_Vectors.Length (X)) loop
            Byte_Vectors.Append (R, Byte_Vectors.Element (X, I));
         end loop;
      end Append_All;
   begin
      for I in 1 .. Integer (Byte_Slice_Vectors.Length (Parts)) loop
         if I > 1 then
            Append_All (Sep);
         end if;
         Append_All (Byte_Slice_Vectors.Element (Parts, I));
      end loop;
      return R;
   end Join;

   procedure Write (B : in out Buffer; Data : Byte_Slice) is
   begin
      for I in 1 .. Integer (Byte_Vectors.Length (Data)) loop
         Byte_Vectors.Append (B.Data, Byte_Vectors.Element (Data, I));
      end loop;
   end Write;

   procedure Write_String (B : in out Buffer; S : String) is
   begin
      for C of S loop
         Byte_Vectors.Append (B.Data, C);
      end loop;
   end Write_String;

   procedure Write_Byte (B : in out Buffer; C : Character) is
   begin
      Byte_Vectors.Append (B.Data, C);
   end Write_Byte;

   function Len (B : Buffer) return Natural is
   begin
      return Integer (Byte_Vectors.Length (B.Data)) - B.Off;
   end Len;

   function To_String (B : Buffer) return String is
      N : constant Natural := Len (B);
      R : String (1 .. N);
   begin
      for I in R'Range loop
         R (I) := Byte_Vectors.Element (B.Data, B.Off + I);
      end loop;
      return R;
   end To_String;

   function Bytes (B : Buffer) return Byte_Slice is
      R : Byte_Slice;
   begin
      for I in 1 .. Len (B) loop
         Byte_Vectors.Append (R, Byte_Vectors.Element (B.Data, B.Off + I));
      end loop;
      return R;
   end Bytes;

   procedure Reset (B : in out Buffer) is
   begin
      Byte_Vectors.Clear (B.Data);
      B.Off := 0;
   end Reset;

   procedure Read (B : in out Buffer; Data : out String;
                   N : out Natural) is
      M : constant Natural := Natural'Min (Data'Length, Len (B));
   begin
      for I in 1 .. M loop
         Data (Data'First + I - 1) :=
           Byte_Vectors.Element (B.Data, B.Off + I);
      end loop;
      B.Off := B.Off + M;
      N := M;
   end Read;

   function New_Reader (Data : Byte_Slice) return Reader is
     (Data => Data, Off => 0);

   procedure Read (R : in out Reader; Data : out String;
                   N : out Natural) is
      M : constant Natural := Natural'Min (Data'Length, Len (R));
   begin
      for I in 1 .. M loop
         Data (Data'First + I - 1) :=
           Byte_Vectors.Element (R.Data, R.Off + I);
      end loop;
      R.Off := R.Off + M;
      N := M;
   end Read;

   procedure Read_Byte (R : in out Reader; C : out Character;
                        Ok : out Boolean) is
   begin
      if Len (R) = 0 then
         C  := Character'Val (0);
         Ok := False;
      else
         C  := Byte_Vectors.Element (R.Data, R.Off + 1);
         R.Off := R.Off + 1;
         Ok := True;
      end if;
   end Read_Byte;

   function Len (R : Reader) return Natural is
   begin
      return Integer (Byte_Vectors.Length (R.Data)) - R.Off;
   end Len;

   procedure Reset (R : in out Reader) is
   begin
      R.Off := 0;
   end Reset;

end Gada.Std.Bytes;
