--  Gada.Std.OS — the Go `os` package, ported (Phase 5 wave 1, Phase 6
--  wave 2).
--
--  Wave 1 ships only file reading (`os.ReadFile`). The Go signature
--  returns ([]byte, error); the port keeps the two-value shape as an
--  out-parameter procedure so the compiler can lower
--  `data, err := os.ReadFile(p)` to a plain call statement:
--
--     Gada.Std.OS.Read_File (P, Data, Err);
--
--  with Data : Byte_Slice (Go []byte — see Gada.Std.Bytes) and
--  Err : Error_Access (nil error = null access, per Gada.Std.Errors).
--
--  Wave 2 adds the process-environment and file-handle surface:
--  Args, Get_Env/Lookup_Env/Set_Env, Open/Create/Write/Close, Stat,
--  Mkdir. Go's two-value (value, error) returns become out-parameters
--  with Err : out Error_Access throughout.

with Ada.Containers.Indefinite_Vectors;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Gada.Std.Bytes;
with Gada.Std.Errors;

package Gada.Std.OS is

   procedure Read_File (Path : String;
                        Data : out Bytes.Byte_Slice;
                        Err  : out Errors.Error_Access);
   --  Reads the whole file at Path into Data. On success Err is
   --  Errors.No_Error (null); on failure (missing/unreadable file)
   --  Data is empty and Err carries a message — Go's
   --  `if err != nil { ... }` maps to `if Err /= null then`.

   ---------------------------------------------------------------
   --  Args — Go os.Args (Args(1) is the program name, Go's [0])
   ---------------------------------------------------------------

   package Arg_Vectors is new Ada.Containers.Indefinite_Vectors
     (Positive, Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

   function Args return Arg_Vectors.Vector;

   ---------------------------------------------------------------
   --  Environment — Go os.Getenv / os.LookupEnv / os.Setenv
   ---------------------------------------------------------------

   --  Value + True when Key is set; empty + False otherwise.
   function Lookup_Env
     (Key   : String;
      Value : out Ada.Strings.Unbounded.Unbounded_String) return Boolean;

   --  Go os.Getenv: "" when unset.
   function Get_Env (Key : String) return String;

   --  Go os.Setenv: error for an empty key or one containing '='
   --  (Go rejects those with "invalid argument").
   function Set_Env (Key, Value : String) return Errors.Error_Access;

   ---------------------------------------------------------------
   --  Files — Go os.Open / os.Create / (*File).Write / Close
   ---------------------------------------------------------------

   type File is limited private;
   type File_Access is access all File;   --  Go's *os.File

   --  Go os.Open (read-only). On failure F is null and Err carries
   --  the message.
   procedure Open (Path : String;
                   F    : out File_Access;
                   Err  : out Errors.Error_Access);

   --  Go os.Create (truncate-or-create, write-only).
   procedure Create (Path : String;
                     F    : out File_Access;
                     Err  : out Errors.Error_Access);

   --  Go (*File).Write. Raises Use_Error when F is null or closed
   --  (Go returns an error value; v1 raises).
   procedure Write (F : File_Access; Data : Bytes.Byte_Slice);

   --  Go (*File).Close; sets F to null (idempotent).
   procedure Close (F : in out File_Access);

   ---------------------------------------------------------------
   --  Stat / Mkdir
   ---------------------------------------------------------------

   --  Go os.Stat: Size is 0 for directories; missing path sets Err.
   procedure Stat (Path   : String;
                   Size   : out Long_Integer;
                   Is_Dir : out Boolean;
                   Err    : out Errors.Error_Access);

   --  Go os.Mkdir (not MkdirAll): an existing directory is an error.
   procedure Mkdir (Path : String; Err : out Errors.Error_Access);

private

   type File is limited record
      F : Ada.Streams.Stream_IO.File_Type;
   end record;

end Gada.Std.OS;
