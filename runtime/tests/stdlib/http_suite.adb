--  Body_K of Http_Suite — see spec for test rationale.
--
--  The server runs in a spawned goroutine because Listen_And_Serve's
--  accept loop blocks the calling task at the OS level; main then
--  drives raw HTTP requests over Gada.Std.Net, as in Net_Suite.

pragma Warnings (Off, "use of an anonymous access type allocator");

with Ada.Text_IO;
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
   use type Response_Access;

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   --  The port the test server listens on, found by probing an
   --  ephemeral port and releasing it (same trick Net_Suite uses for
   --  the refused-dial case).
   The_Port : Natural := 0;

   --  Base_URL is "http://127.0.0.1:<The_Port>".
   function Base_URL return String is
     ("http://127.0.0.1:"
      & Ada.Strings.Fixed.Trim (The_Port'Image, Ada.Strings.Left));

   --  Raw acceptor for the client error-paths test: serves three
   --  malformed responses on one listener, one per connection.
   Raw_L : Listener;

   procedure Raw_Acceptor_Body is
      C   : Conn;
      Err : Errors.Error_Access;
      N   : Natural;
   begin
      for I in 1 .. 3 loop
         Raw_L.all.Accept_K (C, Err);
         exit when Err /= Errors.No_Error;
         case I is
            when 1 =>
               --  headers never terminated: no CRLFCRLF
               C.all.Write (To_Bytes ("HTTP/1.1 200 OK" & CRLF), N, Err);
            when 2 =>
               --  no spaces in the status line at all
               C.all.Write (To_Bytes ("GARBAGE" & CRLF & CRLF), N, Err);
            when 3 =>
               --  well-formed shape, non-digit status code
               C.all.Write
                 (To_Bytes ("HTTP/1.1 A1B OK" & CRLF & CRLF), N, Err);
         end case;
         C.all.Close;
      end loop;
   end Raw_Acceptor_Body;

   function Err_Text (Err : Errors.Error_Access) return String is
     (if Err = Errors.No_Error then "<nil>" else Err.all.Message);

   --  Progress marker so a CI hang is localisable from the job log.
   procedure Trace (S : String) is
   begin
      --  stderr, not stdout: stdout is block-buffered on pipes and the
      --  markers would only appear in chunks, hiding the hang point
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "[http_suite] " & S);
   end Trace;

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

   Scheduler_Up : Boolean := False;

   procedure Start_Server is
      Unused_G : Scheduler.Goroutine_Id;
   begin
      The_Port := Free_Port;
      pragma Assert (The_Port > 0);
      if not Scheduler_Up then
         Scheduler.Init (Workers => 1);
         Scheduler_Up := True;
      end if;
      Unused_G := Scheduler.Spawn (Server_Body'Access);
      --  the accept loop binds asynchronously; Do_Request retries the
      --  dial until it succeeds
   end Start_Server;

   --  Stop the http accept loop first (Stop_Server closes the listener,
   --  waking the blocked Accept), then drain the scheduler — Shutdown's
   --  Drain waits for every worker to exit, so the server goroutine
   --  must be finished before it runs.
   procedure Stop_Server is
   begin
      Trace ("Stop_Server: http stop");
      Gada.Std.Http.Stop_Server;
      Trace ("Stop_Server: scheduler shutdown");
      Scheduler.Shutdown;
      Scheduler_Up := False;
      Trace ("Stop_Server: done");
   end Stop_Server;

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
      for I in 1 .. 500 loop
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
      Register_Routine (T, Test_Client_404'Access, "client GET 404");
      Register_Routine (T, Test_Client_Errors'Access, "client error paths");
      Register_Routine (T, Test_Echo_And_Catchall'Access,
                        "POST echo + catch-all");
      Register_Routine (T, Test_Client_Echo'Access, "client GET/POST echo");
   end Register_Tests;

   overriding function Name (T : Http_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Http suite (PKG=stdlib.net.http)"));

   procedure Test_Not_Found (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Trace ("Test_Not_Found");
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
      Stop_Server;
   end Test_Not_Found;

   --  Listen_And_Serve on an already-bound address must return the
   --  listen error (covers the error arm of Listen_And_Serve without
   --  needing the scheduler).
   procedure Test_Listen_Error (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      L   : Listener;
      Err : Errors.Error_Access;
   begin
      Trace ("Test_Listen_Error");
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
   begin
      Trace ("Test_Bad_Requests");
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
      declare
         C   : Conn;
         Err : Errors.Error_Access;
         N   : Natural;
      begin
         --  Content-Length promises 100 bytes but the peer closes
         --  after 3: the server's body read hits EOF -> 400
         Dial ("tcp", "127.0.0.1:"
                 & Ada.Strings.Fixed.Trim (The_Port'Image,
                                            Ada.Strings.Left),
               C, Err);
         Assert (Err = Errors.No_Error, "dial: " & Err_Text (Err));
         C.all.Write (To_Bytes
           ("POST /x HTTP/1.1" & CRLF & "Content-Length: 100" & CRLF
            & CRLF & "abc"), N, Err);
         C.all.Close;
      end;
      Stop_Server;
   end Test_Bad_Requests;

   --  Client against the real server with an empty mux: a 404 status
   --  parses into Resp.StatusCode (must run before any "/" handler is
   --  registered).
   procedure Test_Client_404 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Resp : Response_Access;
      Err  : Errors.Error_Access;
   begin
      Trace ("Test_Client_404");
      Start_Server;
      Trace ("Client_404: server up, first GET");
      Get (Base_URL & "/nope", Resp, Err);
      Trace ("Client_404: first GET done");
      Assert (Err = Errors.No_Error, "GET 404: " & Err_Text (Err));
      Assert (Resp /= null, "GET 404 returned null response");
      Assert (Resp.StatusCode = 404,
              "expected 404, got" & Resp.StatusCode'Image);
      Assert (Ada.Strings.Fixed.Index
                (To_String (Resp.Body_K), "404 page not found") > 0,
              "expected 404 body");
      --  no path in the URL: Split_URL defaults Path to "/"
      Trace ("Client_404: second GET (no path)");
      Get (Base_URL, Resp, Err);
      Trace ("Client_404: second GET done");
      Assert (Err = Errors.No_Error, "GET no-path: " & Err_Text (Err));
      Assert (Resp /= null and then Resp.StatusCode = 404,
              "GET no-path expected 404");
      Stop_Server;
   end Test_Client_404;

   --  Client error paths: bad scheme, empty host, refused dial, and
   --  three malformed server responses (no header end / no status
   --  spaces / non-digit status code).
   procedure Test_Client_Errors (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Resp : Response_Access;
      Err  : Errors.Error_Access;
   begin
      Trace ("Test_Client_Errors");
      Get ("ftp://example.com/", Resp, Err);
      Assert (Err /= Errors.No_Error and then Resp = null,
              "expected scheme error");
      Get ("http:///x", Resp, Err);
      Assert (Err /= Errors.No_Error and then Resp = null,
              "expected empty-host error");
      declare
         P : constant Natural := Free_Port;
      begin
         Get ("http://127.0.0.1:"
                & Ada.Strings.Fixed.Trim (P'Image, Ada.Strings.Left) & "/",
              Resp, Err);
         Assert (Err /= Errors.No_Error and then Resp = null,
                 "expected refused-dial error");
      end;
      Listen ("tcp", "127.0.0.1:0", Raw_L, Err);
      Assert (Err = Errors.No_Error, "raw listen: " & Err_Text (Err));
      if not Scheduler_Up then
         Scheduler.Init (Workers => 1);
         Scheduler_Up := True;
      end if;
      declare
         Unused_G : Scheduler.Goroutine_Id;
      begin
         Unused_G := Scheduler.Spawn (Raw_Acceptor_Body'Access);
      end;
      for I in 1 .. 3 loop
         Get ("http://" & Raw_L.all.Addr & "/", Resp, Err);
         Assert (Err /= Errors.No_Error and then Resp = null,
                 "expected parse error for garbage response"
                 & I'Image & ", got <nil>");
      end loop;
      Raw_L.all.Close;
      Scheduler.Shutdown;
      Scheduler_Up := False;
   end Test_Client_Errors;

   procedure Test_Echo_And_Catchall
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Trace ("Test_Echo_And_Catchall");
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
      Stop_Server;
   end Test_Echo_And_Catchall;

   --  Client happy path against the echo server: package-level Post
   --  with a body, then a zero-value Client's Get. Runs after
   --  Test_Echo_And_Catchall so the mux already has "/echo".
   procedure Test_Client_Echo (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Resp : Response_Access;
      Err  : Errors.Error_Access;
      C    : Client;
   begin
      Trace ("Test_Client_Echo");
      Start_Server;
      Post (Base_URL & "/echo", "text/plain", To_Bytes ("hello"),
            Resp, Err);
      Assert (Err = Errors.No_Error, "POST: " & Err_Text (Err));
      Assert (Resp /= null and then Resp.StatusCode = 200,
              "POST expected 200");
      Assert (To_String (Resp.Body_K) = "echo:hello",
              "POST body mismatch: '" & To_String (Resp.Body_K) & "'");
      C.Get (Base_URL & "/echo", Resp, Err);
      Assert (Err = Errors.No_Error, "client GET: " & Err_Text (Err));
      Assert (Resp /= null and then Resp.StatusCode = 200,
              "client GET expected 200");
      Assert (To_String (Resp.Body_K) = "echo:",
              "client GET body mismatch: '" & To_String (Resp.Body_K) & "'");
      Stop_Server;
   end Test_Client_Echo;

end Http_Suite;
