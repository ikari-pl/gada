--  Body_K of Http_Suite — see spec for test rationale.
--
--  The server runs in a spawned goroutine because Listen_And_Serve's
--  accept loop blocks the calling task at the OS level; main then
--  drives raw HTTP requests over Gada.Std.Net, as in Net_Suite.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Gada.Async.Scheduler;
with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Errors;
with Gada.Std.Http; use Gada.Std.Http;
with Gada.Std.Net; use Gada.Std.Net;

package body Http_Suite is

   package Scheduler renames Gada.Async.Scheduler;
   package Errors renames Gada.Std.Errors;

   use type Errors.Error_Access;

   --  The port the test server listens on, found by probing an
   --  ephemeral port and releasing it (same trick Net_Suite uses for
   --  the refused-dial case).
   The_Port : Natural := 0;

   function Err_Text (Err : Errors.Error_Access) return String is
     (if Err = Errors.No_Error then "<nil>" else Err.all.Message);

   --  Probe a free loopback port: bind :0, read back the ephemeral
   --  port, release (same trick Net_Suite uses for refused dials).
   function Free_Port return Natural is
      L   : Listener;
      Err : Errors.Error_Access;
   begin
      Listen ("tcp", "127.0.0.1:0", L, Err);
      if Err /= Errors.No_Error then
         return 0;
      end if;
      declare
         A : constant String := L.all.Addr;
         C : constant Natural := Ada.Strings.Fixed.Index
           (A, ":", Going => Ada.Strings.Backward);
         P : constant Natural := Natural'Value (A (C + 1 .. A'Last));
      begin
         L.all.Close;
         return P;
      end;
   end Free_Port;

   procedure Server_Body is
      Err : Errors.Error_Access;
      pragma Unreferenced (Err);
   begin
      --  never returns in practice; if it does, the dial-retry loop in
      --  Do_Request surfaces the failure as a test assertion
      Err := Listen_And_Serve
        ("127.0.0.1:" & Ada.Strings.Fixed.Trim (The_Port'Image,
                                                 Ada.Strings.Left));
   end Server_Body;

   procedure Start_Server is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      The_Port := Free_Port;
      pragma Assert (The_Port > 0);
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Server_Body'Access);
      --  the accept loop binds asynchronously; Do_Request retries the
      --  dial until it succeeds
   end Start_Server;

   --  Do_Request sends raw request text and reads until the server
   --  closes the connection (Connection: close), returning the whole
   --  response. With Tolerate_Write_Error the write error is ignored
   --  (used for the oversized-header case, where the server rejects
   --  and closes while the client is still sending).
   function Do_Request (Req_Text : String;
                        Tolerate_Write_Error : Boolean := False)
                       return String is
      C    : Conn;
      Err  : Errors.Error_Access;
      Buf  : Byte_Slice := New_Bytes (65536);
      N    : Natural;
      Acc  : Unbounded_String;
   begin
      --  retry until the accept loop has bound the port
      for I in 1 .. 5_000 loop
         Dial ("tcp", "127.0.0.1:"
                 & Ada.Strings.Fixed.Trim (The_Port'Image, Ada.Strings.Left),
               C, Err);
         exit when Err = Errors.No_Error;
         delay 0.001;
      end loop;
      Assert (Err = Errors.No_Error, "dial server: " & Err_Text (Err));
      C.all.Write (To_Bytes (Req_Text), N, Err);
      if not Tolerate_Write_Error then
         Assert (Err = Errors.No_Error,
                 "write request: " & Err_Text (Err));
      end if;
      loop
         C.all.Read (Buf, N, Err);
         exit when Err /= Errors.No_Error or else N = 0;
         for I in 1 .. N loop
            Append (Acc, Byte_Vectors.Element (Buf, I));
         end loop;
      end loop;
      C.all.Close;
      return To_String (Acc);
   end Do_Request;

   procedure Echo_Body (W : Response_Writer; R : Request_Access) is
      N   : Natural;
      Err : Errors.Error_Access;
   begin
      W.all.Write (To_Bytes ("echo:"), N, Err);
      W.all.Write (R.Body_K, N, Err);
      pragma Unreferenced (Err);
   end Echo_Body;

   procedure Root_Body (W : Response_Writer; R : Request_Access) is
      pragma Unreferenced (R);
      N   : Natural;
      Err : Errors.Error_Access;
   begin
      W.all.Write (To_Bytes ("root"), N, Err);
      pragma Unreferenced (Err);
   end Root_Body;

   overriding procedure Register_Tests (T : in out Http_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      --  Order matters: the 404 and bad-request tests must run before
      --  any Handle_Func registers "/" (the mux is process-global).
      Register_Routine (T, Test_Listen_Error'Access, "listen on busy port");
      Register_Routine (T, Test_Not_Found'Access, "404 before handlers");
      Register_Routine (T, Test_Bad_Requests'Access, "400 bad requests");
      Register_Routine (T, Test_Echo_And_Catchall'Access,
                        "POST echo + catch-all");
   end Register_Tests;

   overriding function Name (T : Http_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Http suite (PKG=stdlib.net.http)"));

   procedure Test_Not_Found (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Start_Server;
      declare
         R : constant String := Do_Request
           ("GET /nope HTTP/1.1" & Character'Val (13) & Character'Val (10)
            & "Host: x" & Character'Val (13) & Character'Val (10)
            & Character'Val (13) & Character'Val (10));
      begin
         Assert (Ada.Strings.Fixed.Index (R, "HTTP/1.1 404") = 1,
                 "expected 404 status line, got: " & R);
      end;
      Scheduler.Shutdown;
   end Test_Not_Found;

   --  Listen_And_Serve on an already-bound address must return the
   --  listen error (covers the error arm of Listen_And_Serve without
   --  needing the scheduler).
   procedure Test_Listen_Error (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      L   : Listener;
      Err : Errors.Error_Access;
   begin
      Listen ("tcp", "127.0.0.1:0", L, Err);
      Assert (Err = Errors.No_Error, "listen failed: " & Err_Text (Err));
      declare
         E : constant Errors.Error_Access := Listen_And_Serve (L.all.Addr);
      begin
         Assert (E /= Errors.No_Error,
                 "expected error serving on busy port, got <nil>");
      end;
      L.all.Close;
   end Test_Listen_Error;

   --  Malformed requests must get a 400: a garbage request line, a
   --  header section over 1 MiB, and a peer that closes before
   --  sending anything (EOF arm).
   procedure Test_Bad_Requests (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      CRLF : constant String := Character'Val (13) & Character'Val (10);
   begin
      Start_Server;
      declare
         R : constant String := Do_Request ("GARBAGE" & CRLF & CRLF);
      begin
         Assert (Ada.Strings.Fixed.Index (R, "HTTP/1.1 400") = 1,
                 "expected 400 for garbage request line, got: " & R);
      end;
      declare
         Pad : String (1 .. 1_100_000) := (others => 'A');
         R   : constant String := Do_Request
           ("GET / HTTP/1.1" & CRLF & "X-Pad: " & Pad & CRLF & CRLF,
            Tolerate_Write_Error => True);
      begin
         Assert (Ada.Strings.Fixed.Index (R, "HTTP/1.1 400") = 1,
                 "expected 400 for oversized header, got: " & R);
      end;
      declare
         C   : Conn;
         Err : Errors.Error_Access;
      begin
         --  connect and close immediately: server read hits EOF
         Dial ("tcp", "127.0.0.1:"
                 & Ada.Strings.Fixed.Trim (The_Port'Image,
                                            Ada.Strings.Left),
               C, Err);
         Assert (Err = Errors.No_Error, "dial: " & Err_Text (Err));
         C.all.Close;
      end;
      Scheduler.Shutdown;
   end Test_Bad_Requests;

   procedure Test_Echo_And_Catchall
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      CRLF : constant String := Character'Val (13) & Character'Val (10);
   begin
      Start_Server;
      Handle_Func ("/echo", Echo_Body'Access);
      Handle_Func ("/", Root_Body'Access);
      declare
         R : constant String := Do_Request
           ("POST /echo HTTP/1.1" & CRLF & "Host: x" & CRLF
            & "Content-Length: 5" & CRLF & CRLF & "hello");
      begin
         Assert (Ada.Strings.Fixed.Index (R, "HTTP/1.1 200") = 1,
                 "expected 200, got: " & R);
         Assert (Ada.Strings.Fixed.Index (R, "echo:hello") > 0,
                 "expected echo body, got: " & R);
         Assert (Ada.Strings.Fixed.Index (R, "Content-Length: 10") > 0,
                 "expected content-length header, got: " & R);
      end;
      declare
         R : constant String := Do_Request
           ("GET /anything HTTP/1.1" & CRLF & "Host: x" & CRLF & CRLF);
      begin
         Assert (Ada.Strings.Fixed.Index (R, "HTTP/1.1 200") = 1,
                 "catch-all expected 200, got: " & R);
         Assert (Ada.Strings.Fixed.Index (R, "root") > 0,
                 "catch-all expected root body, got: " & R);
      end;
      Scheduler.Shutdown;
   end Test_Echo_And_Catchall;

end Http_Suite;
