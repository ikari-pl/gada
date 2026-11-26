--  Body of Net_Suite — see spec for test rationale.
--
--  TCP/UDP tests use real loopback sockets on ephemeral ports (CI is
--  Linux; 127.0.0.1 always exists). The acceptor runs in a spawned
--  goroutine because Accept blocks the calling task at the OS level;
--  main then drives Dial/Write/Read. Main-task blocking on socket
--  reads is fine — those are OS calls, not scheduler parks.

pragma Warnings (Off, "use of an anonymous access type allocator");

with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Gada.Async.Scheduler;
with Gada.Std.Bytes; use Gada.Std.Bytes;
with Gada.Std.Errors;
with Gada.Std.Net; use Gada.Std.Net;
with Gada.Std.Strings; use Gada.Std.Strings;

package body Net_Suite is

   package Scheduler renames Gada.Async.Scheduler;
   package Errors renames Gada.Std.Errors;

   --  Shared handles for the goroutine acceptor body (Spawn'd
   --  procedures have no closures).
   The_Listener : Listener := null;
   Accept_Done  : Boolean := False;
   pragma Volatile (Accept_Done);

   function Pad (N : Natural) return Byte_Slice is
      S : String (1 .. N) := (others => ' ');
   begin
      return To_Bytes (S);
   end Pad;

   --  Extract the port from a listener/packet-conn "ip:port" string.
   function Port_Of (Addr : String) return Natural is
      use Ada.Strings.Fixed;
      C : constant Natural := Index (Addr, ":", Going => Ada.Strings.Backward);
   begin
      return Natural'Value (Addr (C + 1 .. Addr'Last));
   end Port_Of;

   function Err_Text (Err : Errors.Error_Access) return String is
     (if Err = Errors.No_Error then "<nil>" else Err.all.Message);

   --  Acceptor: take one connection, echo one read back, close it.
   procedure Acceptor_Body is
      C   : Conn;
      Err : Errors.Error_Access;
      Buf : Byte_Slice := Pad (64);
      N   : Natural;
   begin
      The_Listener.all.Accept_K (C, Err);
      if Err = Errors.No_Error then
         C.all.Read (Buf, N, Err);
         if Err = Errors.No_Error and then N > 0 then
            --  Read replaced Buf with the received prefix, so Write
            --  echoes exactly what arrived.
            C.all.Write (Buf, N, Err);
         end if;
         C.all.Close;
      end if;
      Accept_Done := True;
   end Acceptor_Body;

   overriding procedure Register_Tests (T : in out Net_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Parse_IP_V4'Access, "ParseIP IPv4");
      Register_Routine (T, Test_Parse_IP_V6'Access, "ParseIP IPv6");
      Register_Routine (T, Test_IP_Nil_Equal'Access, "IP nil/Equal");
      Register_Routine (T, Test_Lookup_Host'Access, "LookupHost");
      Register_Routine (T, Test_TCP_Echo'Access, "TCP echo round-trip");
      Register_Routine (T, Test_TCP_Errors'Access, "TCP error paths");
      Register_Routine (T, Test_UDP'Access, "UDP packet round-trip");
      Register_Routine (T, Test_Listen_Errors'Access, "Listen error paths");
   end Register_Tests;

   overriding function Name (T : Net_Test) return AUnit.Message_String is
     (AUnit.Format ("Gada.Std.Net suite (PKG=stdlib.net)"));

   procedure Test_Parse_IP_V4 (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      type Bad_Array is array (1 .. 8) of String (1 .. 10);
      Bad : constant Bad_Array :=
        ("1.2.3     ", "1.2.3.4.5 ", "256.1.1.1 ", "01.2.3.4  ",
         "1.2.3.x   ", "1..2.3    ", ".1.2.3    ", "          ");
   begin
      declare
         A : constant IP := Parse_IP ("192.168.0.1");
      begin
         Assert (Is_Valid (A) and then A.Len = 4, "v4 parse failed");
         Assert (To_String (A) = "192.168.0.1",
                 "v4 image: " & To_String (A));
      end;
      Assert (To_String (Parse_IP ("0.0.0.0")) = "0.0.0.0", "zero v4");
      Assert (To_String (Parse_IP ("255.255.255.255")) = "255.255.255.255",
              "max v4");
      for I in Bad'Range loop
         Assert (not Is_Valid (Parse_IP (Bad (I))),
                 "should reject: '" & Bad (I) & "'");
      end loop;
   end Test_Parse_IP_V4;

   procedure Test_Parse_IP_V6 (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      type Case_Array is array (Positive range <>) of String (1 .. 40);
      Good : constant Case_Array :=
        ("::1                                   ",
         "2001:db8::1                           ",
         "2001:0db8:0000:0000:0000:ff00:0042:8329",
         "::                                    ",
         "1::                                   ",
         "::ffff:127.0.0.1                      ",
         "fe80::a:b:c:d                         ",
         "1:2:3:4:5:6:7:8                       ");
      Want : constant Case_Array :=
        ("::1                                   ",
         "2001:db8::1                           ",
         "2001:db8::ff00:42:8329                ",
         "::                                    ",
         "1::                                   ",
         "::ffff:127.0.0.1                      ",
         "fe80::a:b:c:d                         ",
         "1:2:3:4:5:6:7:8                       ");
      Bad : constant Case_Array :=
        ("1:2:3:4:5:6:7:8:9                     ",
         "1::2::3                               ",
         "12345::                               ",
         "::ffff:256.1.1.1                      ",
         "1:2:3:4:5:6:7                         ",
         ":1:2                                  ",
         "1:2:                                  ",
         "gg::1                                 ");
   begin
      for I in Good'Range loop
         declare
            A : constant IP := Parse_IP (Good (I));
         begin
            Assert (Is_Valid (A) and then A.Len = 16,
                    "should parse: '" & Good (I) & "'");
            Assert (To_String (A) = Want (I),
                    "image of '" & Good (I) & "' = '" & To_String (A)
                    & "' want '" & Want (I) & "'");
         end;
      end loop;
      for I in Bad'Range loop
         Assert (not Is_Valid (Parse_IP (Bad (I))),
                 "should reject: '" & Bad (I) & "'");
      end loop;
   end Test_Parse_IP_V6;

   procedure Test_IP_Nil_Equal (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (not Is_Valid (Parse_IP ("")), "empty is nil");
      Assert (To_String (Parse_IP ("")) = "<nil>", "nil image");
      Assert (Equal (Parse_IP ("10.0.0.1"), Parse_IP ("10.0.0.1")),
              "equal v4");
      Assert (not Equal (Parse_IP ("10.0.0.1"), Parse_IP ("10.0.0.2")),
              "unequal v4");
      Assert (not Equal (Parse_IP ("10.0.0.1"), Parse_IP ("::1")),
              "v4 vs v6 differ in length");
      Assert (Equal (Parse_IP ("::1"), Parse_IP ("0:0:0:0:0:0:0:1")),
              "equal v6");
   end Test_IP_Nil_Equal;

   procedure Test_Lookup_Host (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Addrs : String_Slice;
      Err   : Errors.Error_Access;
      Found : Boolean := False;
   begin
      Lookup_Host ("localhost", Addrs, Err);
      Assert (Err = Errors.No_Error,
              "localhost must resolve: " & Err_Text (Err));
      Assert (String_Vectors.Length (Addrs) >= 1,
              "localhost has >= 1 address");
      for I in 1 .. String_Vectors.Length (Addrs) loop
         declare
            S : constant String := To_String
              (String_Vectors.Element (Addrs, I));
         begin
            if S = "127.0.0.1" or else S = "::1" then
               Found := True;
            end if;
         end;
      end loop;
      Assert (Found, "localhost resolves to a loopback address");

      Lookup_Host ("127.0.0.1", Addrs, Err);
      Assert (Err = Errors.No_Error
              and then String_Vectors.Length (Addrs) = 1
              and then To_String (String_Vectors.Element
                (Addrs, 1)) = "127.0.0.1",
              "literal IP resolves to itself");

      Lookup_Host ("nonexistent.invalid", Addrs, Err);
      Assert (Err /= Errors.No_Error
              and then String_Vectors.Is_Empty (Addrs),
              "unknown host errors with empty list");
   end Test_Lookup_Host;

   procedure Test_TCP_Echo (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      L        : Listener;
      Err      : Errors.Error_Access;
      C        : Conn;
      Buf      : Byte_Slice := Pad (64);
      N        : Natural;
      Unused_G : Scheduler.Goroutine_Id;
   begin
      Listen ("tcp", "127.0.0.1:0", L, Err);
      Assert (Err = Errors.No_Error, "listen failed: " & Err_Text (Err));
      Assert (L.all.Addr'Length > 0, "listener addr empty");
      The_Listener := L;
      Accept_Done := False;
      Scheduler.Shutdown;
      Scheduler.Init (Workers => 1);
      Unused_G := Scheduler.Spawn (Acceptor_Body'Access);

      Dial ("tcp", L.all.Addr, C, Err);
      Assert (Err = Errors.No_Error and then C /= null,
              "dial failed: " & Err_Text (Err));

      --  empty-buffer read arm: N = 0, no error
      declare
         Empty : Byte_Slice := Byte_Vectors.Empty_Vector;
      begin
         C.all.Read (Empty, N, Err);
         Assert (N = 0 and then Err = Errors.No_Error,
                 "empty read must give N=0, no error");
      end;

      --  write + read the echo
      declare
         Msg : constant Byte_Slice := To_Bytes ("hello net");
      begin
         C.all.Write (Msg, N, Err);
         Assert (Err = Errors.No_Error and then N = 9,
                 "write failed: " & Err_Text (Err));
      end;
      C.all.Read (Buf, N, Err);
      Assert (Err = Errors.No_Error and then N = 9,
              "read failed: " & Err_Text (Err));
      Assert (To_String (Buf) = "hello net",
              "echo mismatch: '" & To_String (Buf) & "'");
      Assert (C.all.Remote_Addr'Length > 0, "remote addr empty");

      --  wait for the acceptor (it closes the conn after the echo)
      for I in 1 .. 5_000 loop
         exit when Accept_Done;
         delay 0.001;
      end loop;
      Assert (Accept_Done, "acceptor did not finish");

      --  peer closed: next read is EOF (N = 0, Err set)
      C.all.Read (Buf, N, Err);
      Assert (N = 0 and then Err /= Errors.No_Error,
              "expected EOF after peer close, got " & Err_Text (Err));

      --  ops on a closed conn; Close is idempotent
      C.all.Close;
      C.all.Close;
      C.all.Read (Buf, N, Err);
      Assert (Err /= Errors.No_Error, "read on closed must error");
      C.all.Write (To_Bytes ("x"), N, Err);
      Assert (Err /= Errors.No_Error, "write on closed must error");
      Assert (C.all.Remote_Addr = "", "remote addr on closed conn");

      L.all.Close;
      Assert (L.all.Addr = "", "addr on closed listener");
      declare
         C2 : Conn;
      begin
         L.all.Accept_K (C2, Err);
         Assert (Err /= Errors.No_Error and then C2 = null,
                 "accept on closed listener must error");
      end;
      Scheduler.Shutdown;
   end Test_TCP_Echo;

   procedure Test_TCP_Errors (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      L   : Listener;
      C   : Conn;
      Err : Errors.Error_Access;
   begin
      --  unknown network
      Dial ("foo", "127.0.0.1:80", C, Err);
      Assert (Err /= Errors.No_Error and then C = null,
              "unknown network must error");

      --  bad address: no port
      Dial ("tcp", "127.0.0.1", C, Err);
      Assert (Err /= Errors.No_Error and then C = null,
              "missing port must error");

      --  malformed bracket form
      Dial ("tcp", "[::1", C, Err);
      Assert (Err /= Errors.No_Error and then C = null,
              "bad bracket must error");

      --  unresolvable host
      Dial ("tcp", "nonexistent.invalid:80", C, Err);
      Assert (Err /= Errors.No_Error and then C = null,
              "unknown host must error: " & Err_Text (Err));

      --  connection refused: grab a free port, close, then dial it
      Listen ("tcp", "127.0.0.1:0", L, Err);
      Assert (Err = Errors.No_Error, "probe listen failed");
      declare
         Addr : constant String := L.all.Addr;
      begin
         L.all.Close;
         Dial ("tcp", Addr, C, Err);
         Assert (Err /= Errors.No_Error and then C = null,
                 "dial to closed port must be refused: "
                 & Err_Text (Err));
      end;
   end Test_TCP_Errors;

   procedure Test_UDP (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      PC1, PC2 : Packet_Conn;
      C        : Conn;
      Err      : Errors.Error_Access;
      Buf      : Byte_Slice := Pad (64);
      N        : Natural;
      From     : IP;
   begin
      Listen_Packet ("udp", "127.0.0.1:0", PC1, Err);
      Assert (Err = Errors.No_Error, "listenpacket 1 failed: "
              & Err_Text (Err));
      Listen_Packet ("udp", "127.0.0.1:0", PC2, Err);
      Assert (Err = Errors.No_Error, "listenpacket 2 failed: "
              & Err_Text (Err));
      declare
         P1 : constant Natural := Port_Of (PC1.all.Addr);
         P2 : constant Natural := Port_Of (PC2.all.Addr);
      begin
         Assert (P1 > 0 and then P2 > 0 and then P1 /= P2,
                 "ephemeral ports assigned");

         --  empty-buffer read arm: N = 0, From = nil, no error
         declare
            Empty : Byte_Slice := Byte_Vectors.Empty_Vector;
         begin
            PC2.all.Read_From (Empty, N, From, Err);
            Assert (N = 0 and then Err = Errors.No_Error
                    and then not Is_Valid (From),
                    "empty read must give N=0, no error, nil From");
         end;

         --  pc1 -> pc2 datagram
         PC1.all.Write_To (To_Bytes ("ping"),
                           Parse_IP ("127.0.0.1"), P2, N, Err);
         Assert (Err = Errors.No_Error and then N = 4,
                 "write_to failed: " & Err_Text (Err));
         PC2.all.Read_From (Buf, N, From, Err);
         Assert (Err = Errors.No_Error and then N = 4,
                 "read_from failed: " & Err_Text (Err));
         Assert (To_String (Buf) = "ping",
                 "datagram mismatch: '" & To_String (Buf) & "'");
         Assert (Equal (From, Parse_IP ("127.0.0.1")),
                 "From must be 127.0.0.1, got " & To_String (From));

         --  nil-IP Write_To sends to the wildcard address (Linux
         --  routes 0.0.0.0 to loopback)
         PC1.all.Write_To (To_Bytes ("any"), Parse_IP (""), P2,
                           N, Err);
         Assert (Err = Errors.No_Error and then N = 3,
                 "write_to nil IP failed: " & Err_Text (Err));

         --  connected UDP dial -> pc read (covers Conn on a
         --  datagram socket)
         Dial ("udp", "127.0.0.1:"
                 & Ada.Strings.Fixed.Trim (Natural'Image (P1),
                                            Ada.Strings.Left),
               C, Err);
         Assert (Err = Errors.No_Error, "udp dial failed: "
                 & Err_Text (Err));
         C.all.Write (To_Bytes ("pong"), N, Err);
         Assert (Err = Errors.No_Error and then N = 4,
                 "udp write failed: " & Err_Text (Err));
         PC1.all.Read_From (Buf, N, From, Err);
         Assert (Err = Errors.No_Error and then N = 4
                 and then To_String (Buf) = "pong",
                 "udp echo failed: " & Err_Text (Err));
         C.all.Close;

         --  closed packet conn: ops error, Close idempotent, Addr ""
         PC1.all.Close;
         PC1.all.Close;
         PC1.all.Read_From (Buf, N, From, Err);
         Assert (Err /= Errors.No_Error, "read on closed must error");
         PC1.all.Write_To (To_Bytes ("x"),
                           Parse_IP ("127.0.0.1"), P2, N, Err);
         Assert (Err /= Errors.No_Error, "write on closed must error");
         Assert (PC1.all.Addr = "", "addr on closed packet conn");
         PC2.all.Close;
      end;
   end Test_UDP;

   procedure Test_Listen_Errors
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      L   : Listener;
      PC  : Packet_Conn;
      Err : Errors.Error_Access;
   begin
      Listen ("udp", "127.0.0.1:0", L, Err);
      Assert (Err /= Errors.No_Error and then L = null,
              "listen udp must be rejected in v1");

      Listen ("tcp", "no-port-here", L, Err);
      Assert (Err /= Errors.No_Error and then L = null,
              "listen bad address must error");

      Listen ("tcp", "nonexistent.invalid:0", L, Err);
      Assert (Err /= Errors.No_Error and then L = null,
              "listen unresolvable must error: " & Err_Text (Err));

      Listen_Packet ("tcp", "127.0.0.1:0", PC, Err);
      Assert (Err /= Errors.No_Error and then PC = null,
              "listenpacket tcp must be rejected in v1");

      Listen_Packet ("udp", "bad", PC, Err);
      Assert (Err /= Errors.No_Error and then PC = null,
              "listenpacket bad address must error");

      Listen_Packet ("udp", "nonexistent.invalid:0", PC, Err);
      Assert (Err /= Errors.No_Error and then PC = null,
              "listenpacket unresolvable must error: " & Err_Text (Err));
   end Test_Listen_Errors;

end Net_Suite;
