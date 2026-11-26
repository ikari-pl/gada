--  Gada.Std.Net — the Go `net` package, ported (Phase 7, stdlib wave 3).
--
--  v1 scope (roadmap/07-stdlib-wave3-network.md item 1): TCP and UDP
--  over IPv4 loopback/LAN, Dial / Listen / ListenPacket, LookupHost,
--  and IP parsing/formatting (IPv4 + IPv6). Sockets ride GNAT.Sockets,
--  the GCC-Ada native binding — no FFI, no cgo.
--
--  Go's two-value returns (value, error) become out-parameter
--  procedures, the same shape as Gada.Std.OS: `conn, err := net.Dial(n,
--  a)` lowers to `Gada.Std.Net.Dial (N, A, Conn, Err);`. Go's net.Conn
--  and net.Listener are interfaces; here they are access-to-protected
--  types (Conn = access all Conn_Impl), so a method call lowers to an
--  explicit `Conn.all.Read (…)` protected call.

with Gada.Std.Bytes;
with Gada.Std.Errors;
with Gada.Std.Strings;
with GNAT.Sockets;

package Gada.Std.Net is

   ---------------------------------------------------------------
   --  IP — Go net.IP (a 4- or 16-byte address; Len = 0 is Go's nil)
   ---------------------------------------------------------------

   type IP_Octets is array (1 .. 16) of Character;

   type IP is record
      Len : Natural := 0;   --  0 = nil, 4 = IPv4, 16 = IPv6
      B   : IP_Octets := (others => Character'Val (0));
   end record;

   --  Go net.ParseIP: returns the nil IP (Len = 0) when S is not a
   --  valid IPv4 dotted quad or IPv6 address.
   function Parse_IP (S : String) return IP;

   function Is_Valid (A : IP) return Boolean is (A.Len > 0);

   --  Go ip.String(): dotted quad for IPv4, RFC 5952 compressed hex
   --  for IPv6; the nil IP renders as "<nil>" (Go's behaviour).
   function To_String (A : IP) return String;

   function Equal (A, B : IP) return Boolean;

   ---------------------------------------------------------------
   --  Conn — Go net.Conn (interface in Go; access-to-protected here)
   ---------------------------------------------------------------

   protected type Conn_Impl is
      --  Go conn.Read(b): reads up to len(b) bytes; Buf is replaced by
      --  the received prefix and N is the count. Peer shutdown yields
      --  N = 0 with Err = "EOF" (Go: io.EOF).
      procedure Read (Buf : in out Bytes.Byte_Slice;
                      N   : out Natural;
                      Err : out Errors.Error_Access);
      --  Statement form `conn.Read(b)` (Go discards the results).
      procedure Read (Buf : in out Bytes.Byte_Slice);
      --  Go conn.Write(b): sends all of Data (looping over partial
      --  sends); N is the count sent.
      procedure Write (Data : in Bytes.Byte_Slice;
                       N    : out Natural;
                       Err  : out Errors.Error_Access);
      procedure Write (Data : in Bytes.Byte_Slice);
      --  Go conn.Close(). Idempotent.
      procedure Close;
      --  Go conn.RemoteAddr(): "ip:port" of the peer.
      function Remote_Addr return String;
      entry Set (S : GNAT.Sockets.Socket_Type);
   private
      Sock   : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Closed : Boolean := False;
   end Conn_Impl;

   type Conn is access all Conn_Impl;

   --  Go net.Dial(network, address): "tcp"/"tcp4" connect a stream
   --  socket, "udp"/"udp4" connect a datagram socket. Address is
   --  "host:port" (host may be a dotted quad, a name, or empty/"
   --  0.0.0.0" for any). On failure C is null and Err carries the
   --  message.
   procedure Dial (Network, Address : String;
                   C   : out Conn;
                   Err : out Errors.Error_Access);

   ---------------------------------------------------------------
   --  Listener — Go net.Listener (TCP accept loop)
   ---------------------------------------------------------------

   protected type Listener_Impl is
      --  Go listener.Accept() [Accept_K]: blocks until a connection arrives.
      procedure Accept_K (C : out Conn; Err : out Errors.Error_Access);
      procedure Close;
      --  Go listener.Addr().String(): the bound "ip:port" (useful with
      --  port 0, where the OS picks an ephemeral port).
      function Addr return String;
      entry Set (S : GNAT.Sockets.Socket_Type);
   private
      Sock : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
   end Listener_Impl;

   type Listener is access all Listener_Impl;

   --  Go net.Listen(network, address): TCP only in v1.
   procedure Listen (Network, Address : String;
                     L   : out Listener;
                     Err : out Errors.Error_Access);

   ---------------------------------------------------------------
   --  Packet_Conn — Go net.PacketConn (UDP)
   ---------------------------------------------------------------

   protected type Packet_Conn_Impl is
      --  Go pc.ReadFrom(b): one datagram; From is the sender's IP.
      procedure Read_From (Buf  : in out Bytes.Byte_Slice;
                           N    : out Natural;
                           From : out IP;
                           Err  : out Errors.Error_Access);
      --  Go pc.WriteTo(b, addr): send one datagram to To:To_Port.
      procedure Write_To (Data    : in Bytes.Byte_Slice;
                          To      : in IP;
                          To_Port : in Natural;
                          N       : out Natural;
                          Err     : out Errors.Error_Access);
      procedure Close;
      function Addr return String;
      entry Set (S : GNAT.Sockets.Socket_Type);
   private
      Sock : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
   end Packet_Conn_Impl;

   type Packet_Conn is access all Packet_Conn_Impl;

   --  Go net.ListenPacket(network, address): UDP only in v1.
   procedure Listen_Packet (Network, Address : String;
                            PC  : out Packet_Conn;
                            Err : out Errors.Error_Access);

   ---------------------------------------------------------------
   --  LookupHost — Go net.LookupHost
   ---------------------------------------------------------------

   --  Resolves Host to its IP address strings (Go returns []string of
   --  dotted quads / compressed v6). On failure Addrs is empty and
   --  Err carries the message.
   procedure Lookup_Host (Host  : String;
                          Addrs : out Strings.String_Slice;
                          Err   : out Errors.Error_Access);

end Gada.Std.Net;
