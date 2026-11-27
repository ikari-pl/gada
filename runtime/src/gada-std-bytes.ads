--  Gada.Std.Bytes — the Go `bytes` package, ported (Phase 5 wave 1).
--
--  Go `[]byte` maps to a vector of Character (Byte_Slice), the same
--  pattern Gada.Std.Strings uses for Go `[]string` — Gada.Core.Slices'
--  address-overlay generic only supports definite, non-controlled
--  element types. The compiler-side []byte mapping lands with the
--  integration example.
--
--  Index-returning functions keep Go's 0-based, -1-not-found contract.
--  Buffer/Reader mirror Go's structs: Buffer is a growable byte buffer
--  with a read offset (Write appends at the end, String/Bytes expose
--  the unread portion); Reader reads through a byte slice. Read
--  returns N = 0 at end of data (Go's io.EOF — the io package lands in
--  this wave too and refines the error value).

with Ada.Containers.Vectors;

package Gada.Std.Bytes is

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Character);

   subtype Byte_Slice is Byte_Vectors.Vector;

   package Byte_Slice_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Byte_Slice,
      "="          => Byte_Vectors."=");

   subtype Byte_Slice_List is Byte_Slice_Vectors.Vector;

   --  Go `make ([]byte, N)`: a slice of N zero bytes (Phase 7 read
   --  buffers for net.Conn.Read and friends).
   function New_Bytes (N : Natural) return Byte_Slice;

   --  Conversions between Go string and []byte (a plain copy in Go).
   function To_Bytes (S : String) return Byte_Slice;
   function To_String (B : Byte_Slice) return String;

   function Equal (A, B : Byte_Slice) return Boolean;
   --  Lexicographic: -1 / 0 / +1 (Go's bytes.Compare).
   function Compare (A, B : Byte_Slice) return Integer;
   function Contains (S, Sub : Byte_Slice) return Boolean;
   --  0-based, -1 = not found (Go's contract); empty Sub → 0.
   function Index (S, Sub : Byte_Slice) return Integer;
   function Has_Prefix (S, Prefix : Byte_Slice) return Boolean;
   function Has_Suffix (S, Suffix : Byte_Slice) return Boolean;

   --  Split on Sep; empty Sep splits per byte; empty S → one empty
   --  part (Go semantics, same as Gada.Std.Strings.Split).
   function Split (S, Sep : Byte_Slice) return Byte_Slice_List;
   function Join (Parts : Byte_Slice_List; Sep : Byte_Slice)
     return Byte_Slice;

   ---------------------------------------------------------------
   --  Go: type Buffer struct { buf []byte; off int }
   ---------------------------------------------------------------

   type Buffer is tagged private;

   procedure Write (B : in out Buffer; Data : Byte_Slice);
   procedure Write_String (B : in out Buffer; S : String);
   procedure Write_Byte (B : in out Buffer; C : Character);
   --  Reads up to Data'Length bytes; N = 0 means end of data
   --  (Go returns io.EOF there).
   procedure Read (B : in out Buffer; Data : out String;
                   N : out Natural);
   function Len (B : Buffer) return Natural;
   --  Go's b.String() — named To_String because a subprogram cannot
   --  share the type name String (homograph rule).
   function To_String (B : Buffer) return String;
   function Bytes (B : Buffer) return Byte_Slice;
   procedure Reset (B : in out Buffer);

   ---------------------------------------------------------------
   --  Go: type Reader struct { s []byte; i int64 }
   ---------------------------------------------------------------

   type Reader is tagged private;

   function New_Reader (Data : Byte_Slice) return Reader;
   procedure Read (R : in out Reader; Data : out String; N : out Natural);
   procedure Read_Byte (R : in out Reader; C : out Character;
                        Ok : out Boolean);
   function Len (R : Reader) return Natural;
   procedure Reset (R : in out Reader);

private

   type Buffer is tagged record
      Data : Byte_Vectors.Vector;
      Off  : Natural := 0;
   end record;

   type Reader is tagged record
      Data : Byte_Vectors.Vector;
      Off  : Natural := 0;
   end record;

end Gada.Std.Bytes;
