--  Gada.Std.Http body — see the spec for the v1 scope.

with Ada.Containers.Vectors;
with Ada.Strings;
with Ada.Strings.Fixed;

package body Gada.Std.Http is

   use Gada.Std.Bytes;
   use Gada.Std.Errors;

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   ---------------------------------------------------------------
   --  Mux (the default ServeMux)
   ---------------------------------------------------------------

   type Mux_Entry is record
      Pattern : Unbounded_String;
      H       : Handler_Func;
   end record;

   package Mux_Vectors is new
     Ada.Containers.Vectors (Positive, Mux_Entry);

   protected type Mux_Type is
      procedure Register (Pattern : String; H : Handler_Func);
      function Lookup (Path : String) return Handler_Func;
   private
      Entries : Mux_Vectors.Vector;
   end Mux_Type;

   protected body Mux_Type is
      procedure Register (Pattern : String; H : Handler_Func) is
         E : constant Mux_Entry :=
           (Pattern => To_Unbounded_String (Pattern), H => H);
      begin
         Mux_Vectors.Append (Entries, E);
      end Register;

      function Lookup (Path : String) return Handler_Func is
      begin
         for E of Entries loop
            if To_String (E.Pattern) = Path then
               return E.H;
            end if;
         end loop;
         --  "/" is the catch-all, as in Go's DefaultServeMux.
         for E of Entries loop
            if To_String (E.Pattern) = "/" then
               return E.H;
            end if;
         end loop;
         return null;
      end Lookup;
   end Mux_Type;

   The_Mux : Mux_Type;

   procedure Handle_Func (Pattern : String; H : Handler_Func) is
   begin
      The_Mux.Register (Pattern, H);
   end Handle_Func;

   ---------------------------------------------------------------
   --  Response_Writer
   ---------------------------------------------------------------

   protected body Response_Writer_Impl is
      procedure Write (Data : Byte_Slice;
                       N    : out Natural;
                       Err  : out Error_Access) is
      begin
         for I in 1 .. Integer (Byte_Vectors.Length (Data)) loop
            Byte_Vectors.Append
              (Body_K, Byte_Vectors.Element (Data, I));
         end loop;
         N   := Integer (Byte_Vectors.Length (Data));
         Err := No_Error;
      end Write;

      procedure Write_Header (Status : Natural) is
      begin
         Status_Code := Status;
      end Write_Header;

      function Status return Natural is
      begin
         return Status_Code;
      end Status;

      function Get_Body return Byte_Slice is
      begin
         return Body_K;
      end Get_Body;
   end Response_Writer_Impl;

   ---------------------------------------------------------------
   --  Request parsing
   ---------------------------------------------------------------

   function To_Lower (S : String) return String is
      R : String := S;
   begin
      for I in R'Range loop
         if R (I) in 'A' .. 'Z' then
            R (I) := Character'Val (Character'Pos (R (I)) + 32);
         end if;
      end loop;
      return R;
   end To_Lower;

   --  Read_Request reads one HTTP/1.1 request from C: request line,
   --  headers up to the blank line, then Content-Length body bytes.
   procedure Read_Request (C   : Gada.Std.Net.Conn;
                           Req : out Request_Access;
                           Err : out Error_Access) is
      use Ada.Strings.Fixed;
      Buf : Byte_Slice := New_Bytes (65536);
      Acc : Unbounded_String;
      N   : Natural;
      E   : Error_Access;
      Hd  : Natural;  --  index of the header terminator in Acc
   begin
      Req := new Request'(Method => Null_Unbounded_String,
                          Path   => Null_Unbounded_String,
                          Body_K => Byte_Vectors.Empty_Vector);
      Err := No_Error;
      loop
         C.all.Read (Buf, N, E);
         if E /= No_Error then
            Err := E;
            return;
         end if;
         if N = 0 then
            Err := New_K ("http: EOF before end of headers");
            return;
         end if;
         for I in 1 .. N loop
            Append (Acc, Byte_Vectors.Element (Buf, I));
         end loop;
         Hd := Index (Acc, CRLF & CRLF);
         exit when Hd > 0;
         if Length (Acc) > 1_048_576 then
            Err := New_K ("http: header section too large");
            return;
         end if;
      end loop;
      declare
         Head : constant String := Slice (Acc, 1, Hd + 3);
         Rest : constant String := Slice (Acc, Hd + 4, Length (Acc));
         First_Lf : constant Natural := Index (Head, CRLF);
      begin
         if First_Lf = 0 then
            Err := New_K ("http: malformed request line");
            return;
         end if;
         declare
            Line : constant String := Head (1 .. First_Lf - 1);
            S1   : constant Natural := Index (Line, " ");
            S2   : constant Natural := Index (Line, " ",
                                             Going => Ada.Strings.Backward);
         begin
            if S1 = 0 or else S2 <= S1 then
               Err := New_K ("http: malformed request line");
               return;
            end if;
            Req.all.Method := To_Unbounded_String (Line (1 .. S1 - 1));
            Req.all.Path   := To_Unbounded_String (Line (S1 + 1 .. S2 - 1));
         end;
         --  Content-Length (case-insensitive) from the header lines.
         declare
            Content_Len : Natural := 0;
            Pos         : Natural := First_Lf + 2;
         begin
            --  Header lines live between the request line and the
            --  blank line (positions First_Lf+2 .. Hd-1, each CRLF-
            --  terminated).
            while Pos < Hd loop
               declare
                  Lf    : constant Natural :=
                    Index (Head (Pos .. Hd - 1), CRLF);
                  Hline : constant String :=
                    (if Lf = 0 then Head (Pos .. Hd - 1)
                     else Head (Pos .. Pos + Lf - 2));
                  Colon : constant Natural := Index (Hline, ":");
               begin
                  if Lf = 0 then
                     exit;
                  end if;
                  if Colon > 0
                    and then To_Lower (Trim (Hline (1 .. Colon - 1),
                                             Ada.Strings.Both))
                      = "content-length"
                  then
                     declare
                        V : constant String :=
                          Trim (Hline (Colon + 1 .. Hline'Last),
                                Ada.Strings.Both);
                     begin
                        if V'Length > 0 and then
                          (for all Ch of V => Ch in '0' .. '9')
                        then
                           Content_Len := Natural'Value (V);
                        else
                           Err := New_K ("http: bad Content-Length");
                           return;
                        end if;
                     end;
                  end if;
                  Pos := Pos + Lf + 1;
               end;
            end loop;
            --  Body_K: the bytes already read past the header block,
            --  plus more reads up to Content_Len.
            declare
               Have : Natural := Rest'Length;
            begin
               for I in Rest'Range loop
                  Byte_Vectors.Append (Req.all.Body_K, Rest (I));
               end loop;
               while Have < Content_Len loop
                  C.all.Read (Buf, N, E);
                  if E /= No_Error then
                     Err := E;
                     return;
                  end if;
                  if N = 0 then
                     Err := New_K ("http: EOF in body");
                     return;
                  end if;
                  for I in 1 .. N loop
                     Byte_Vectors.Append
                       (Req.all.Body_K, Byte_Vectors.Element (Buf, I));
                  end loop;
                  Have := Have + N;
               end loop;
            end;
         end;
      end;
   end Read_Request;

   ---------------------------------------------------------------
   --  Response writing + serve loop
   ---------------------------------------------------------------

   function Reason (Status : Natural) return String is
   begin
      case Status is
         when 200 => return "OK";
         when 404 => return "Not Found";
         when 500 => return "Internal Server Error";
         when others => return "Status";
      end case;
   end Reason;

   procedure Write_Response (C      : Gada.Std.Net.Conn;
                             Status : Natural;
                             Body_K   : Byte_Slice;
                             Err    : out Error_Access) is
      use Ada.Strings.Fixed;
      Head : constant String :=
        "HTTP/1.1 " & Trim (Status'Image, Ada.Strings.Left) & " "
        & Reason (Status) & CRLF
        & "Content-Length: "
        & Trim (Integer'Image (Integer (Byte_Vectors.Length (Body_K))),
                Ada.Strings.Left)
        & CRLF & "Connection: close" & CRLF & CRLF;
      N : Natural;
   begin
      C.all.Write (To_Bytes (Head), N, Err);
      if Err = No_Error then
         C.all.Write (Body_K, N, Err);
      end if;
   end Write_Response;

   --  Serve_One handles a single accepted connection: read the
   --  request, dispatch, write the buffered response, close.
   procedure Serve_One (C : Gada.Std.Net.Conn) is
      Req : Request_Access;
      Err : Error_Access;
      W   : Response_Writer;
      H   : Handler_Func;
   begin
      Read_Request (C, Req, Err);
      if Err /= No_Error then
         Write_Response (C, 400, To_Bytes ("bad request"),
                         Err);
         C.all.Close;
         return;
      end if;
      H := The_Mux.Lookup (To_String (Req.all.Path));
      if H = null then
         Write_Response (C, 404, To_Bytes ("404 page not found"), Err);
      else
         W := new Response_Writer_Impl;
         H (W, Req);
         Write_Response (C, W.all.Status, W.all.Get_Body, Err);
      end if;
      C.all.Close;
   end Serve_One;

   function Listen_And_Serve (Addr : String) return Error_Access is
      L   : Gada.Std.Net.Listener;
      Err : Error_Access;
      C   : Gada.Std.Net.Conn;
   begin
      Gada.Std.Net.Listen ("tcp", Addr, L, Err);
      if Err /= No_Error then
         return Err;
      end if;
      loop
         L.all.Accept_K (C, Err);
         if Err /= No_Error then
            L.all.Close;
            return Err;
         end if;
         Serve_One (C);
      end loop;
      return No_Error;  --  unreachable: the accept loop never exits
   end Listen_And_Serve;

   ---------------------------------------------------------------
   --  Client (item 4)
   ---------------------------------------------------------------

   --  Split_URL parses "http://host[:port]/path" (v1: http only).
   --  Path defaults to "/".
   procedure Split_URL (URL  : String;
                        Host : out Unbounded_String;
                        Path : out Unbounded_String;
                        Err  : out Error_Access) is
      use Ada.Strings.Fixed;
      Prefix : constant String := "http://";
   begin
      Host := Null_Unbounded_String;
      Path := Null_Unbounded_String;
      Err  := No_Error;
      if URL'Length < Prefix'Length or else
        URL (URL'First .. URL'First + Prefix'Length - 1) /= Prefix
      then
         Err := New_K ("http: unsupported URL scheme (v1: http only)");
         return;
      end if;
      declare
         Rest  : constant String := URL (URL'First + Prefix'Length ..
                                           URL'Last);
         Slash : constant Natural := Index (Rest, "/");
      begin
         if Slash = 0 then
            Host := To_Unbounded_String (Rest);
            Path := To_Unbounded_String ("/");
         else
            Host := To_Unbounded_String (Rest (Rest'First .. Slash - 1));
            Path := To_Unbounded_String (Rest (Slash .. Rest'Last));
         end if;
         if Length (Host) = 0 then
            Err := New_K ("http: empty host in URL");
         end if;
      end;
   end Split_URL;

   --  Do_Request performs one HTTP/1.1 exchange: dial host, send the
   --  request, read until the server closes (v1 servers send
   --  Connection: close), parse status line + body.
   procedure Do_Request (Method       : String;
                         URL          : String;
                         Content_Type : String;
                         Body_K       : Byte_Slice;
                         Resp         : out Response_Access;
                         Err          : out Error_Access) is
      use Ada.Strings.Fixed;
      Host : Unbounded_String;
      Path : Unbounded_String;
      C    : Gada.Std.Net.Conn;
      Buf  : Byte_Slice := New_Bytes (65536);
      N    : Natural;
      E    : Error_Access;
      Acc  : Unbounded_String;
   begin
      Resp := null;
      Err  := No_Error;
      Split_URL (URL, Host, Path, Err);
      if Err /= No_Error then
         return;
      end if;
      Gada.Std.Net.Dial ("tcp", To_String (Host), C, Err);
      if Err /= No_Error then
         return;
      end if;
      declare
         Req : constant String :=
           Method & " " & To_String (Path) & " HTTP/1.1" & CRLF
           & "Host: " & To_String (Host) & CRLF
           & (if Content_Type'Length > 0 then
                 "Content-Type: " & Content_Type & CRLF else "")
           & "Content-Length: "
           & Trim (Integer'Image
                     (Integer (Byte_Vectors.Length (Body_K))),
                   Ada.Strings.Left)
           & CRLF & CRLF;
      begin
         C.all.Write (To_Bytes (Req), N, E);
         if E = No_Error and then
           Integer (Byte_Vectors.Length (Body_K)) > 0 then
            C.all.Write (Body_K, N, E);
         end if;
         if E /= No_Error then
            Err := E;
            C.all.Close;
            return;
         end if;
      end;
      --  read the whole response until EOF
      loop
         C.all.Read (Buf, N, E);
         exit when E /= No_Error or else N = 0;
         for I in 1 .. N loop
            Append (Acc, Byte_Vectors.Element (Buf, I));
         end loop;
      end loop;
      C.all.Close;
      --  split head / body at the blank line
      declare
         Raw : constant String := To_String (Acc);
         Hd  : constant Natural := Index (Raw, CRLF & CRLF);
      begin
         if Hd = 0 then
            Err := New_K ("http: malformed response (no header end)");
            return;
         end if;
         declare
            Head  : constant String := Raw (Raw'First .. Hd + 3);
            Rest  : constant String :=
              Raw (Hd + 4 .. Raw'Last);
            --  Hd > 0 guarantees a CRLF, so First_Lf >= 1.
            First_Lf : constant Natural := Index (Head, CRLF);
            Line     : constant String := Head (1 .. First_Lf - 1);
            SP1      : constant Natural := Index (Line, " ");
            SP2      : constant Natural :=
              (if SP1 > 0 then Index (Line (SP1 + 1 .. Line'Last), " ")
               else 0);
         begin
            --  "HTTP/1.1 200 OK": code is the token after the first SP
            if SP1 = 0 or else SP2 = 0 or else
              Line (1 .. SP1 - 1)'Length < 5 or else
              Line (1 .. 5) /= "HTTP/"
            then
               Err := New_K ("http: malformed status line");
               return;
            end if;
            declare
               Code_S : constant String :=
                 Line (SP1 + 1 .. SP1 + 3);
            begin
               if Code_S (1) not in '0' .. '9' or else
                 Code_S (2) not in '0' .. '9' or else
                 Code_S (3) not in '0' .. '9'
               then
                  Err := New_K ("http: malformed status code");
                  return;
               end if;
               Resp := new Response'
                 (StatusCode => Natural'Value (Code_S),
                  Body_K     => Byte_Vectors.Empty_Vector);
               for I in Rest'Range loop
                  Byte_Vectors.Append (Resp.all.Body_K, Rest (I));
               end loop;
            end;
         end;
      end;
   end Do_Request;

   protected body Client is
      procedure Get (URL : String; Resp : out Response_Access;
                     Err  : out Error_Access) is
      begin
         Do_Request ("GET", URL, "", Byte_Vectors.Empty_Vector,
                     Resp, Err);
      end Get;

      procedure Post (URL, Content_Type : String;
                      Body_K : Byte_Slice;
                      Resp : out Response_Access;
                      Err  : out Error_Access) is
      begin
         Do_Request ("POST", URL, Content_Type, Body_K, Resp, Err);
      end Post;
   end Client;

   procedure Get (URL : String; Resp : out Response_Access;
                  Err : out Error_Access) is
   begin
      Do_Request ("GET", URL, "", Byte_Vectors.Empty_Vector, Resp, Err);
   end Get;

   procedure Post (URL, Content_Type : String;
                   Body_K : Byte_Slice;
                   Resp : out Response_Access;
                   Err : out Error_Access) is
   begin
      Do_Request ("POST", URL, Content_Type, Body_K, Resp, Err);
   end Post;

end Gada.Std.Http;
