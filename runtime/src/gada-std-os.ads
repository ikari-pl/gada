--  Gada.Std.OS — the Go `os` package, ported (Phase 5 wave 1, minimal).
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

end Gada.Std.OS;
