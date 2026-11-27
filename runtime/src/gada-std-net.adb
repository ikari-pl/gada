--  Body of Gada.Std.Net — see spec for the Go-semantics contract.

with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with GNAT.Sockets;
with Gada.Std.Bytes;
with Gada.Std.Errors;
with Gada.Std.Strings;

package body Gada.Std.Net is

   package GS renames GNAT.Sockets;

   use type GS.Socket_Type;
   use type GS.Family_Type;
   use type Ada.Streams.Stream_Element_Offset;

   ---------------------------------------------------------------
   --  One-time GNAT.Sockets init (lazy, on first use)
   ---------------------------------------------------------------

   Initialized : Boolean := False;
   pragma Volatile (Initialized);

   procedure Ensure_Init is
   begin
      if not Initialized then
         GS.Initialize;
         Initialized := True;
      end if;
   end Ensure_Init;

   ---------------------------------------------------------------
   --  IP parsing / formatting
   ---------------------------------------------------------------

   Zero_IP : constant IP := (Len => 0,
                             B => (others => Character'Val (0)));

   function Parse_Octet (S : String; V : out Natural) return Boolean is
   begin
      V := 0;
      if S'Length = 0 or else S'Length > 3 then
         return False;
      end if;
      --  Go (since 1.17) rejects leading zeros in IPv4 octets.
      if S'Length > 1 and then S (S'First) = '0' then
         return False;
      end if;
      for I in S'Range loop
         if S (I) not in '0' .. '9' then
            return False;
         end if;
      end loop;
      V := Natural'Value (S);
      return V <= 255;
   end Parse_Octet;

   function Parse_IPv4 (S : String) return IP is
      use Ada.Strings.Fixed;
      Result : IP := Zero_IP;
      Pos    : Natural := S'First;
   begin
      if Count (S, ".") /= 3 then
         return Zero_IP;
      end if;
      for Part in 1 .. 4 loop
         if Pos > S'Last then
            return Zero_IP;
         end if;
         declare
            --  Index returns an index into the slice's own range,
            --  i.e. an absolute position in S.
            Dot  : constant Natural := Index (S (Pos .. S'Last), ".");
            Last : constant Natural :=
              (if Part = 4 then S'Last else Dot - 1);
            V    : Natural;
         begin
            if Part < 4 and then Dot = 0 then
               return Zero_IP;
            end if;
            if Last < Pos then
               return Zero_IP;   --  empty octet (e.g. "1..2.3")
            end if;
            if not Parse_Octet (S (Pos .. Last), V) then
               return Zero_IP;
            end if;
            Result.B (Part) := Character'Val (V);
            Pos := (if Part = 4 then S'Last + 1 else Dot + 1);
         end;
      end loop;
      Result.Len := 4;
      return Result;
   end Parse_IPv4;

   type Group_Array is array (1 .. 8) of Natural;

   --  Parse colon-separated hex groups of one side of a "::". An
   --  embedded IPv4 tail (e.g. "::ffff:1.2.3.4") is accepted as the
   --  final group and expands to two 16-bit groups.
   function Parse_Groups (S : String; Arr : out Group_Array;
                          N : out Natural) return Boolean is
      use Ada.Strings.Fixed;
      Pos : Natural := S'First;
   begin
      N := 0;
      Arr := (others => 0);
      if S'Length = 0 then
         return True;
      end if;
      while Pos <= S'Last loop
         declare
            --  Index returns an index into the slice's own range,
            --  i.e. an absolute position in S.
            Colon : constant Natural := Index (S (Pos .. S'Last), ":");
            Last  : constant Natural :=
              (if Colon = 0 then S'Last else Colon - 1);
            G     : constant String :=
              (if Last < Pos then "" else S (Pos .. Last));
            V     : Natural;
         begin
            if Index (G, ".") > 0 then
               --  embedded IPv4: only as the very last group
               if Colon /= 0 then
                  return False;
               end if;
               declare
                  A : constant IP := Parse_IPv4 (G);
               begin
                  if A.Len /= 4 or else N + 2 > 8 then
                     return False;
                  end if;
                  N := N + 1;
                  Arr (N) := Character'Pos (A.B (1)) * 256
                    + Character'Pos (A.B (2));
                  N := N + 1;
                  Arr (N) := Character'Pos (A.B (3)) * 256
                    + Character'Pos (A.B (4));
               end;
            else
               if G'Length = 0 or else G'Length > 4 then
                  return False;
               end if;
               V := 0;
               for C of G loop
                  declare
                     D : Natural;
                  begin
                     if C in '0' .. '9' then
                        D := Character'Pos (C) - Character'Pos ('0');
                     elsif C in 'a' .. 'f' then
                        D := Character'Pos (C) - Character'Pos ('a') + 10;
                     elsif C in 'A' .. 'F' then
                        D := Character'Pos (C) - Character'Pos ('A') + 10;
                     else
                        return False;
                     end if;
                     V := V * 16 + D;
                  end;
               end loop;
               if N + 1 > 8 then
                  return False;
               end if;
               N := N + 1;
               Arr (N) := V;
            end if;
            if Colon = 0 then
               exit;
            end if;
            Pos := Colon + 1;
            if Pos > S'Last then
               return False;   --  trailing single ':'
            end if;
         end;
      end loop;
      return True;
   end Parse_Groups;

   function Parse_IPv6 (S : String) return IP is
      use Ada.Strings.Fixed;
      Dbl    : constant Natural := Index (S, "::");
      Head_S : constant String :=
        (if Dbl = 0 then S
         elsif Dbl > S'First then S (S'First .. Dbl - 1)
         else "");
      Tail_S : constant String :=
        (if Dbl = 0 then ""
         elsif Dbl + 2 <= S'Last then S (Dbl + 2 .. S'Last)
         else "");
      Head, Tail : Group_Array;
      N_Head, N_Tail : Natural;
      Groups : Group_Array;
      Result : IP := Zero_IP;
   begin
      if Dbl > 0 and then Index (Tail_S, "::") > 0 then
         return Zero_IP;   --  more than one "::"
      end if;
      if not Parse_Groups (Head_S, Head, N_Head) then
         return Zero_IP;
      end if;
      if not Parse_Groups (Tail_S, Tail, N_Tail) then
         return Zero_IP;
      end if;
      if Dbl = 0 then
         if N_Head /= 8 then
            return Zero_IP;
         end if;
         Groups := Head;
      else
         --  "::" must compress at least one zero group.
         if N_Head + N_Tail > 7 then
            return Zero_IP;
         end if;
         Groups := (others => 0);
         for G in 1 .. N_Head loop
            Groups (G) := Head (G);
         end loop;
         for G in 1 .. N_Tail loop
            Groups (8 - N_Tail + G) := Tail (G);
         end loop;
      end if;
      for G in 1 .. 8 loop
         Result.B (2 * G - 1) := Character'Val (Groups (G) / 256);
         Result.B (2 * G)     := Character'Val (Groups (G) mod 256);
      end loop;
      Result.Len := 16;
      return Result;
   end Parse_IPv6;

   function Parse_IP (S : String) return IP is
   begin
      if S'Length = 0 then
         return Zero_IP;
      end if;
      if Ada.Strings.Fixed.Index (S, ":") > 0 then
         return Parse_IPv6 (S);
      end if;
      return Parse_IPv4 (S);
   end Parse_IP;

   function Equal (A, B : IP) return Boolean is
   begin
      if A.Len /= B.Len then
         return False;
      end if;
      for I in 1 .. A.Len loop
         if A.B (I) /= B.B (I) then
            return False;
         end if;
      end loop;
      return True;
   end Equal;

   Hex_Digits : constant String := "0123456789abcdef";

   function Hex_Group (V : Natural) return String is
      --  lowercase hex, no leading zeros (RFC 5952)
      N : Natural := V;
      Out_S : String (1 .. 4);
      Len : Natural := 0;
   begin
      if N = 0 then
         return "0";
      end if;
      while N > 0 loop
         Len := Len + 1;
         Out_S (Len) := Hex_Digits (N mod 16 + 1);
         N := N / 16;
      end loop;
      declare
         R : String (1 .. Len);
      begin
         for I in 1 .. Len loop
            R (I) := Out_S (Len - I + 1);
         end loop;
         return R;
      end;
   end Hex_Group;

   function Octet_Image (C : Character) return String is
      use Ada.Strings.Fixed;
   begin
      return Trim (Natural'Image (Character'Pos (C)), Ada.Strings.Left);
   end Octet_Image;

   function To_String (A : IP) return String is
      use Ada.Strings.Fixed;
      Groups : Group_Array;
      Best_Start, Best_Len : Natural := 0;
      Cur_Start, Cur_Len   : Natural := 0;
      B : Unbounded_String;
   begin
      if A.Len = 0 then
         return "<nil>";
      end if;
      if A.Len = 4 then
         return Octet_Image (A.B (1)) & "." & Octet_Image (A.B (2))
           & "." & Octet_Image (A.B (3)) & "." & Octet_Image (A.B (4));
      end if;
      for G in 1 .. 8 loop
         Groups (G) := Character'Pos (A.B (2 * G - 1)) * 256
           + Character'Pos (A.B (2 * G));
      end loop;
      --  v4-mapped (::ffff:a.b.c.d) renders as Go does: dotted quad
      if (for all G in 1 .. 5 => Groups (G) = 0)
        and then Groups (6) = 16#FFFF#
      then
         return "::ffff:" & Octet_Image (A.B (13)) & "."
           & Octet_Image (A.B (14)) & "." & Octet_Image (A.B (15))
           & "." & Octet_Image (A.B (16));
      end if;
      --  longest run of zero groups (RFC 5952: first of equal-length
      --  runs wins; only runs of length >= 2 compress)
      for G in 1 .. 8 loop
         if Groups (G) = 0 then
            if Cur_Len = 0 then
               Cur_Start := G;
            end if;
            Cur_Len := Cur_Len + 1;
            if Cur_Len > Best_Len then
               Best_Len := Cur_Len;
               Best_Start := Cur_Start;
            end if;
         else
            Cur_Len := 0;
         end if;
      end loop;
      if Best_Len >= 2 then
         declare
            Before : Unbounded_String;
            After  : Unbounded_String;
         begin
            for G in 1 .. Best_Start - 1 loop
               if Length (Before) > 0 then
                  Append (Before, ":");
               end if;
               Append (Before, Hex_Group (Groups (G)));
            end loop;
            for G in Best_Start + Best_Len .. 8 loop
               if Length (After) > 0 then
                  Append (After, ":");
               end if;
               Append (After, Hex_Group (Groups (G)));
            end loop;
            return To_String (Before) & "::" & To_String (After);
         end;
      end if;
      for G in 1 .. 8 loop
         if G > 1 then
            Append (B, ":");
         end if;
         Append (B, Hex_Group (Groups (G)));
      end loop;
      return To_String (B);
   end To_String;

   ---------------------------------------------------------------
   --  Address helpers
   ---------------------------------------------------------------

   function Parse_Port (S : String; Port : out Natural) return Boolean is
   begin
      Port := 0;
      if S'Length = 0 or else S'Length > 5 then
         return False;
      end if;
      for I in S'Range loop
         if S (I) not in '0' .. '9' then
            return False;
         end if;
      end loop;
      Port := Natural'Value (S);
      return Port <= 65535;
   end Parse_Port;

   --  Split "host:port" (or "[v6]:port"). OK = False on malformed.
   procedure Split_Address (Address : String;
                            Host  : out Unbounded_String;
                            Port  : out Natural;
                            OK    : out Boolean) is
      use Ada.Strings.Fixed;
   begin
      Host := Null_Unbounded_String;
      Port := 0;
      OK   := False;
      if Address'Length = 0 then
         return;
      end if;
      if Address (Address'First) = '[' then
         declare
            Close_B : constant Natural := Index (Address, "]");
         begin
            if Close_B > 0 and then Close_B < Address'Last
              and then Address (Close_B + 1) = ':'
            then
               Host := To_Unbounded_String
                 (Address (Address'First + 1 .. Close_B - 1));
               OK := Parse_Port (Address (Close_B + 2 .. Address'Last),
                                 Port);
            end if;
            return;
         end;
      end if;
      declare
         Last_Colon : Natural := 0;
      begin
         for I in Address'Range loop
            if Address (I) = ':' then
               Last_Colon := I;
            end if;
         end loop;
         if Last_Colon = 0 then
            return;
         end if;
         Host := To_Unbounded_String
           (Address (Address'First .. Last_Colon - 1));
         OK := Parse_Port (Address (Last_Colon + 1 .. Address'Last),
                           Port);
      end;
   end Split_Address;

   --  Resolve a host string to an IPv4 address. OK = False when the
   --  name does not resolve.
   function Resolve (Host : String; OK : out Boolean)
                     return GS.Inet_Addr_Type is
   begin
      OK := True;
      if Host = "" or else Host = "0.0.0.0" or else Host = "::" then
         return GS.Any_Inet_Addr;
      end if;
      if Parse_IP (Host).Len = 4 then
         return GS.Inet_Addr (Host);
      end if;
      if Parse_IP (Host).Len = 16 then
         --  IPv6 literal: v1 sockets are IPv4-only.
         OK := False;
         return GS.Any_Inet_Addr;
      end if;
      begin
         declare
            H : constant GS.Host_Entry_Type := GS.Get_Host_By_Name (Host);
         begin
            for I in 1 .. GS.Addresses_Length (H) loop
               declare
                  A : constant GS.Inet_Addr_Type := GS.Addresses (H, I);
               begin
                  if A.Family = GS.Family_Inet then
                     return A;
                  end if;
               end;
            end loop;
            --  Resolved, but to no IPv4 address (v6-only name).
            OK := False;
            return GS.Any_Inet_Addr;
         end;
      exception
         when GS.Socket_Error | GS.Host_Error =>
            OK := False;
            return GS.Any_Inet_Addr;
      end;
   end Resolve;

   function To_IP (A : GS.Inet_Addr_Type) return IP is
      Result : IP := Zero_IP;
   begin
      --  A.Family is Family_Inet_4_6; v1 sockets are always v4, so
      --  the Inet6 arm is defensive (excluded from coverage — see
      --  runtime/COVERAGE.md).
      case A.Family is
         when GS.Family_Inet =>
            Result.Len := 4;
            for I in 1 .. 4 loop
               Result.B (I) := Character'Val (Natural (A.Sin_V4 (I)));
            end loop;
         when GS.Family_Inet6 =>
            Result.Len := 16;
            for I in 1 .. 16 loop
               Result.B (I) := Character'Val (Natural (A.Sin_V6 (I)));
            end loop;
      end case;
      return Result;
   end To_IP;

   function To_Sock_Addr (A : IP; Port : Natural) return GS.Sock_Addr_Type
   is
      Result : GS.Sock_Addr_Type (GS.Family_Inet);
   begin
      Result.Port := GS.Port_Type (Port);
      if A.Len = 4 then
         for I in 1 .. 4 loop
            Result.Addr.Sin_V4 (I) :=
              GS.Inet_Addr_Comp_Type (Character'Pos (A.B (I)));
         end loop;
      else
         Result.Addr := GS.Any_Inet_Addr;
      end if;
      return Result;
   end To_Sock_Addr;

   function Addr_Image (A : GS.Sock_Addr_Type) return String is
      use Ada.Strings.Fixed;
   begin
      if A.Family /= GS.Family_Inet and then A.Family /= GS.Family_Inet6
      then
         return "";
      end if;
      return GS.Image (A.Addr) & ":"
        & Trim (Integer'Image (Integer (A.Port)), Ada.Strings.Left);
   end Addr_Image;

   --  Fill a stream-element array from a byte slice.
   procedure To_Elements (Data : in Bytes.Byte_Slice;
                          Arr  : out Ada.Streams.Stream_Element_Array) is
      use Ada.Streams;
   begin
      for K in 1 .. Natural (Arr'Length) loop
         Arr (Arr'First + Stream_Element_Offset (K - 1)) :=
           Stream_Element (Character'Pos
              (Bytes.Byte_Vectors.Element (Data, K)));
      end loop;
   end To_Elements;

   ---------------------------------------------------------------
   --  Conn_Impl
   ---------------------------------------------------------------

   protected body Conn_Impl is

      procedure Set (S : GS.Socket_Type) is
      begin
         Sock := S;
         Closed := False;
      end Set;

      procedure Read (Buf : in out Bytes.Byte_Slice;
                      N   : out Natural;
                      Err : out Errors.Error_Access) is
         use Ada.Streams;
         Max : constant Natural :=
           Natural (Bytes.Byte_Vectors.Length (Buf));
      begin
         N := 0;
         Err := Errors.No_Error;
         if Closed or else Sock = GS.No_Socket then
            Err := Errors.New_K ("read: connection closed");
            return;
         end if;
         if Max = 0 then
            return;
         end if;
         declare
            Arr  : Stream_Element_Array (1 .. Stream_Element_Offset (Max));
            Last : Stream_Element_Offset;
         begin
            GS.Receive_Socket (Sock, Arr, Last);
            if Last < Arr'First then
               --  peer performed an orderly shutdown: Go's io.EOF
               Err := Errors.New_K ("EOF");
            else
               N := Natural (Last);
               Bytes.Byte_Vectors.Clear (Buf);
               for I in Arr'First .. Last loop
                  Bytes.Byte_Vectors.Append
                    (Buf, Character'Val (Arr (I)));
               end loop;
            end if;
         exception
            when E : GS.Socket_Error =>
               Err := Errors.New_K
                 ("read: " & Ada.Exceptions.Exception_Message (E));
         end;
      end Read;

      procedure Read (Buf : in out Bytes.Byte_Slice) is
         N   : Natural;
         Err : Errors.Error_Access;
      begin
         Read (Buf, N, Err);
      end Read;

      procedure Write (Data : in Bytes.Byte_Slice;
                       N    : out Natural;
                       Err  : out Errors.Error_Access) is
         use Ada.Streams;
         Total : constant Natural :=
           Natural (Bytes.Byte_Vectors.Length (Data));
      begin
         N := 0;
         Err := Errors.No_Error;
         if Closed or else Sock = GS.No_Socket then
            Err := Errors.New_K ("write: connection closed");
            return;
         end if;
         if Total = 0 then
            return;
         end if;
         declare
            Arr  : Stream_Element_Array (1 .. Stream_Element_Offset (Total));
            Off  : Stream_Element_Offset := 0;
            Sent : Stream_Element_Offset;
         begin
            To_Elements (Data, Arr);
            while Off < Arr'Last loop
               GS.Send_Socket (Sock, Arr (Off + 1 .. Arr'Last), Sent);
               if Sent <= Off then
                  N := Natural (Off);
                  Err := Errors.New_K ("write: no progress");
                  return;
               end if;
               Off := Sent;
            end loop;
            N := Total;
         exception
            when E : GS.Socket_Error =>
               N := Natural (Off);
               Err := Errors.New_K
                 ("write: " & Ada.Exceptions.Exception_Message (E));
         end;
      end Write;

      procedure Write (Data : in Bytes.Byte_Slice) is
         N   : Natural;
         Err : Errors.Error_Access;
      begin
         Write (Data, N, Err);
      end Write;

      procedure Close is
      begin
         if Sock /= GS.No_Socket then
            GS.Close_Socket (Sock);
            Sock := GS.No_Socket;
         end if;
         Closed := True;
      end Close;

      function Remote_Addr return String is
      begin
         if Sock = GS.No_Socket then
            return "";
         end if;
         return Addr_Image (GS.Get_Peer_Name (Sock));
      end Remote_Addr;

   end Conn_Impl;

   ---------------------------------------------------------------
   --  Dial
   ---------------------------------------------------------------

   procedure Dial (Network, Address : String;
                   C   : out Conn;
                   Err : out Errors.Error_Access) is
      Mode : GS.Mode_Type;
      Host : Unbounded_String;
      Port : Natural;
      OK   : Boolean;
   begin
      C := null;
      Err := Errors.No_Error;
      Ensure_Init;
      if Network = "tcp" or else Network = "tcp4" then
         Mode := GS.Socket_Stream;
      elsif Network = "udp" or else Network = "udp4" then
         Mode := GS.Socket_Datagram;
      else
         Err := Errors.New_K ("dial: unknown network " & Network);
         return;
      end if;
      Split_Address (Address, Host, Port, OK);
      if not OK then
         Err := Errors.New_K ("dial: bad address " & Address);
         return;
      end if;
      declare
         R_OK     : Boolean;
         Resolved : constant GS.Inet_Addr_Type :=
           Resolve (To_String (Host), R_OK);
         Addr     : GS.Sock_Addr_Type;
         S        : GS.Socket_Type;
      begin
         if not R_OK then
            Err := Errors.New_K
              ("dial: cannot resolve " & To_String (Host));
            return;
         end if;
         Addr := (Family => GS.Family_Inet,
                  Addr   => Resolved,
                  Port   => GS.Port_Type (Port));
         begin
            GS.Create_Socket (S, GS.Family_Inet, Mode);
            GS.Connect_Socket (S, Addr);
            C := new Conn_Impl;
            C.all.Set (S);
         exception
            when E : GS.Socket_Error =>
               if S /= GS.No_Socket then
                  begin
                     GS.Close_Socket (S);
                  exception
                     --  never mask the original connect error
                     when others => null;
                  end;
               end if;
               Err := Errors.New_K
                 ("dial " & Address & ": "
                  & Ada.Exceptions.Exception_Message (E));
         end;
      end;
   end Dial;

   ---------------------------------------------------------------
   --  Listener
   ---------------------------------------------------------------

   protected body Listener_Impl is

      procedure Set (S : GS.Socket_Type) is
      begin
         Sock := S;
      end Set;

      procedure Accept_K (C : out Conn; Err : out Errors.Error_Access) is
         S : GS.Socket_Type;
         A : GS.Sock_Addr_Type;
      begin
         C := null;
         Err := Errors.No_Error;
         if Sock = GS.No_Socket then
            Err := Errors.New_K ("accept: listener closed");
            return;
         end if;
         begin
            GS.Accept_Socket (Sock, S, A);
            C := new Conn_Impl;
            C.all.Set (S);
         exception
            when E : GS.Socket_Error =>
               Err := Errors.New_K
                 ("accept: " & Ada.Exceptions.Exception_Message (E));
         end;
      end Accept_K;

      procedure Close is
      begin
         if Sock /= GS.No_Socket then
            --  shutdown(2) first: on POSIX, close alone does not wake a
            --  thread blocked in accept(2) on the same socket
            begin
               GS.Shutdown_Socket (Sock, GS.Shut_Read_Write);
            exception
               when GS.Socket_Error => null;
            end;
            GS.Close_Socket (Sock);
            Sock := GS.No_Socket;
         end if;
      end Close;

      function Addr return String is
      begin
         if Sock = GS.No_Socket then
            return "";
         end if;
         return Addr_Image (GS.Get_Socket_Name (Sock));
      end Addr;

   end Listener_Impl;

   procedure Listen (Network, Address : String;
                     L   : out Listener;
                     Err : out Errors.Error_Access) is
      Host : Unbounded_String;
      Port : Natural;
      OK   : Boolean;
   begin
      L := null;
      Err := Errors.No_Error;
      Ensure_Init;
      if Network /= "tcp" and then Network /= "tcp4" then
         Err := Errors.New_K
           ("listen: unsupported network " & Network & " (v1: tcp)");
         return;
      end if;
      Split_Address (Address, Host, Port, OK);
      if not OK then
         Err := Errors.New_K ("listen: bad address " & Address);
         return;
      end if;
      declare
         R_OK     : Boolean;
         Resolved : constant GS.Inet_Addr_Type :=
           Resolve (To_String (Host), R_OK);
         Addr     : GS.Sock_Addr_Type;
         S        : GS.Socket_Type;
      begin
         if not R_OK then
            Err := Errors.New_K
              ("listen: cannot resolve " & To_String (Host));
            return;
         end if;
         Addr := (Family => GS.Family_Inet,
                  Addr   => Resolved,
                  Port   => GS.Port_Type (Port));
         begin
            GS.Create_Socket (S, GS.Family_Inet, GS.Socket_Stream);
            GS.Set_Socket_Option
              (S, GS.Socket_Level, (GS.Reuse_Address, True));
            GS.Bind_Socket (S, Addr);
            GS.Listen_Socket (S);
            L := new Listener_Impl;
            L.all.Set (S);
         exception
            when E : GS.Socket_Error =>
               if S /= GS.No_Socket then
                  begin
                     GS.Close_Socket (S);
                  exception
                     --  never mask the original bind/listen error
                     when others => null;
                  end;
               end if;
               Err := Errors.New_K
                 ("listen " & Address & ": "
                  & Ada.Exceptions.Exception_Message (E));
         end;
      end;
   end Listen;

   ---------------------------------------------------------------
   --  Packet_Conn (UDP)
   ---------------------------------------------------------------

   protected body Packet_Conn_Impl is

      procedure Set (S : GS.Socket_Type) is
      begin
         Sock := S;
      end Set;

      procedure Read_From (Buf  : in out Bytes.Byte_Slice;
                           N    : out Natural;
                           From : out IP;
                           Err  : out Errors.Error_Access) is
         use Ada.Streams;
         Max : constant Natural :=
           Natural (Bytes.Byte_Vectors.Length (Buf));
      begin
         N := 0;
         From := Zero_IP;
         Err := Errors.No_Error;
         if Sock = GS.No_Socket then
            Err := Errors.New_K ("read: connection closed");
            return;
         end if;
         if Max = 0 then
            return;
         end if;
         declare
            Arr   : Stream_Element_Array (1 .. Stream_Element_Offset (Max));
            Last  : Stream_Element_Offset;
            A_From : GS.Sock_Addr_Type;
         begin
            GS.Receive_Socket (Sock, Arr, Last, A_From);
            if Last >= Arr'First then
               N := Natural (Last);
               From := To_IP (A_From.Addr);
               Bytes.Byte_Vectors.Clear (Buf);
               for I in Arr'First .. Last loop
                  Bytes.Byte_Vectors.Append
                    (Buf, Character'Val (Arr (I)));
               end loop;
            end if;
         exception
            when E : GS.Socket_Error =>
               Err := Errors.New_K
                 ("read: " & Ada.Exceptions.Exception_Message (E));
         end;
      end Read_From;

      procedure Write_To (Data    : in Bytes.Byte_Slice;
                          To      : in IP;
                          To_Port : in Natural;
                          N       : out Natural;
                          Err     : out Errors.Error_Access) is
         use Ada.Streams;
         Total : constant Natural :=
           Natural (Bytes.Byte_Vectors.Length (Data));
      begin
         N := 0;
         Err := Errors.No_Error;
         if Sock = GS.No_Socket then
            Err := Errors.New_K ("write: connection closed");
            return;
         end if;
         if Total = 0 then
            return;
         end if;
         declare
            Arr  : Stream_Element_Array (1 .. Stream_Element_Offset (Total));
            Sent : Stream_Element_Offset;
            Addr : constant GS.Sock_Addr_Type := To_Sock_Addr (To, To_Port);
         begin
            To_Elements (Data, Arr);
            GS.Send_Socket (Sock, Arr, Sent, Addr);
            N := Natural (Sent);
         exception
            when E : GS.Socket_Error =>
               Err := Errors.New_K
                 ("write: " & Ada.Exceptions.Exception_Message (E));
         end;
      end Write_To;

      procedure Close is
      begin
         if Sock /= GS.No_Socket then
            --  shutdown(2) first: on POSIX, close alone does not wake a
            --  thread blocked in accept(2) on the same socket
            begin
               GS.Shutdown_Socket (Sock, GS.Shut_Read_Write);
            exception
               when GS.Socket_Error => null;
            end;
            GS.Close_Socket (Sock);
            Sock := GS.No_Socket;
         end if;
      end Close;

      function Addr return String is
      begin
         if Sock = GS.No_Socket then
            return "";
         end if;
         return Addr_Image (GS.Get_Socket_Name (Sock));
      end Addr;

   end Packet_Conn_Impl;

   procedure Listen_Packet (Network, Address : String;
                            PC  : out Packet_Conn;
                            Err : out Errors.Error_Access) is
      Host : Unbounded_String;
      Port : Natural;
      OK   : Boolean;
   begin
      PC := null;
      Err := Errors.No_Error;
      Ensure_Init;
      if Network /= "udp" and then Network /= "udp4" then
         Err := Errors.New_K
           ("listenpacket: unsupported network " & Network
            & " (v1: udp)");
         return;
      end if;
      Split_Address (Address, Host, Port, OK);
      if not OK then
         Err := Errors.New_K ("listenpacket: bad address " & Address);
         return;
      end if;
      declare
         R_OK     : Boolean;
         Resolved : constant GS.Inet_Addr_Type :=
           Resolve (To_String (Host), R_OK);
         Addr     : GS.Sock_Addr_Type;
         S        : GS.Socket_Type;
      begin
         if not R_OK then
            Err := Errors.New_K
              ("listenpacket: cannot resolve " & To_String (Host));
            return;
         end if;
         Addr := (Family => GS.Family_Inet,
                  Addr   => Resolved,
                  Port   => GS.Port_Type (Port));
         begin
            GS.Create_Socket (S, GS.Family_Inet, GS.Socket_Datagram);
            GS.Set_Socket_Option
              (S, GS.Socket_Level, (GS.Reuse_Address, True));
            GS.Bind_Socket (S, Addr);
            PC := new Packet_Conn_Impl;
            PC.all.Set (S);
         exception
            when E : GS.Socket_Error =>
               if S /= GS.No_Socket then
                  begin
                     GS.Close_Socket (S);
                  exception
                     --  never mask the original bind error
                     when others => null;
                  end;
               end if;
               Err := Errors.New_K
                 ("listenpacket " & Address & ": "
                  & Ada.Exceptions.Exception_Message (E));
         end;
      end;
   end Listen_Packet;

   ---------------------------------------------------------------
   --  LookupHost
   ---------------------------------------------------------------

   procedure Lookup_Host (Host  : String;
                          Addrs : out Strings.String_Slice;
                          Err   : out Errors.Error_Access) is
   begin
      Err := Errors.No_Error;
      Addrs := Strings.String_Vectors.Empty_Vector;
      Ensure_Init;
      begin
         declare
            H : constant GS.Host_Entry_Type := GS.Get_Host_By_Name (Host);
         begin
            for I in 1 .. GS.Addresses_Length (H) loop
               Strings.String_Vectors.Append
                 (Addrs,
                  To_Unbounded_String
                    (GS.Image (GS.Addresses (H, I))));
            end loop;
         end;
      exception
         when E : GS.Socket_Error | GS.Host_Error =>
            Addrs := Strings.String_Vectors.Empty_Vector;
            Err := Errors.New_K
              ("lookup " & Host & ": "
               & Ada.Exceptions.Exception_Message (E));
      end;
   end Lookup_Host;

end Gada.Std.Net;
