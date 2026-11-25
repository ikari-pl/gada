--  Gada.Std.IO — the Go `io` package, ported (Phase 5 wave 1).
--
--  Go's io.Reader / io.Writer are interfaces with a single method; the
--  idiomatic Ada model is an *abstract tagged* type, so any derived
--  type (a file, a bytes.Buffer, a transpiled Go struct with a Read
--  method) is an io.Reader via the class-wide access (Reader_Access),
--  and Read/Write dispatch on it — the same pattern Gada.Std.Errors
--  uses for Go's `error`.
--
--  v1 note: Go's Read/Write move []byte; this port moves String (the
--  compiler's Go string ↔ our byte-buffer idiom), with N as the
--  comma-ok count and the error as the return value. N = 0 with EOF
--  is the end-of-stream signal; Copy treats EOF as success (Go's
--  contract) and any other error as a hard failure.

with Ada.Strings.Unbounded;
with Gada.Std.Errors;

package Gada.Std.IO is

   --  Go: var EOF = errors.New("EOF") — a sentinel; identity is what
   --  errors.Is compares, so this is a package variable like Go's.
   EOF : Gada.Std.Errors.Error_Access;

   --  Go: type Reader interface { Read(p []byte) (n int, err error) }
   type Reader is abstract tagged private;
   type Reader_Access is access all Reader'Class;

   function Read (R : Reader; Data : out String; N : out Natural)
      return Gada.Std.Errors.Error_Access is abstract;

   --  Go: type Writer interface { Write(p []byte) (n int, err error) }
   type Writer is abstract tagged private;
   type Writer_Access is access all Writer'Class;

   function Write (W : Writer; Data : String; N : out Natural)
      return Gada.Std.Errors.Error_Access is abstract;

   --  Go: func Copy(dst Writer, src Reader) (written int64, err error)
   --  Copies until EOF (success) or a hard error; N is bytes written.
   procedure Copy (Dst : Writer_Access; Src : Reader_Access;
                   N : out Natural;
                   Err : out Gada.Std.Errors.Error_Access);

   --  Go: func ReadAll(r Reader) ([]byte, error) — v1 returns a String.
   procedure Read_All (R : Reader_Access;
                       Data : out Ada.Strings.Unbounded.Unbounded_String;
                       Err : out Gada.Std.Errors.Error_Access);

private

   type Reader is abstract tagged null record;
   type Writer is abstract tagged null record;

end Gada.Std.IO;
