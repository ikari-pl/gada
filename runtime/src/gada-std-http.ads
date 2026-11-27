--  Gada.Std.Http — GADA's port of Go's `net/http` (Phase 7 wave 3,
--  item 3: server side). v1 scope: exact-match + "/" catch-all
--  patterns, HTTP/1.1 request parsing (request line, headers,
--  Content-Length body), handler dispatch, buffered responses with
--  Content-Length and Connection: close, sequential accept loop on
--  Gada.Std.Net.
--
--  Shapes mirror Gada.Std.Net: Response_Writer is an
--  access-to-protected so the transpiled `w.Write(b)` lowers to
--  `W.all.Write (B, N, Err);` like net.Conn's methods.

with Ada.Strings.Unbounded;
with Gada.Std.Bytes;
with Gada.Std.Errors;
with Gada.Std.Net;

package Gada.Std.Http is

   use Ada.Strings.Unbounded;

   ---------------------------------------------------------------
   --  Request
   ---------------------------------------------------------------

   --  Request — Go *http.Request (the body is pre-read into memory;
   --  v1 has no streaming Body_K).
   type Request is record
      Method : Unbounded_String;
      Path   : Unbounded_String;
      Body_K   : Gada.Std.Bytes.Byte_Slice;
   end record;

   type Request_Access is access all Request;

   ---------------------------------------------------------------
   --  ResponseWriter
   ---------------------------------------------------------------

   protected type Response_Writer_Impl is
      --  Buffer the body; the server writes status line + headers +
      --  body when the handler returns.
      procedure Write (Data : Gada.Std.Bytes.Byte_Slice;
                       N    : out Natural;
                       Err  : out Gada.Std.Errors.Error_Access);
      procedure Write_Header (Status : Natural);
      function Status return Natural;
   private
      Status_Code : Natural := 200;
      Body_K        : Gada.Std.Bytes.Byte_Slice :=
        Gada.Std.Bytes.Byte_Vectors.Empty_Vector;
   end Response_Writer_Impl;

   type Response_Writer is access all Response_Writer_Impl;

   ---------------------------------------------------------------
   --  Handler + mux
   ---------------------------------------------------------------

   --  Handler_Func — Go http.HandlerFunc: `func(w, r *Request)`.
   type Handler_Func is access procedure (W : Response_Writer;
                                           R : Request_Access);

   --  Handle_Func registers H for Pattern in the default mux
   --  (`http.HandleFunc`). "/" is the catch-all, as in Go.
   procedure Handle_Func (Pattern : String; H : Handler_Func);

   --  Listen_And_Serve serves the default mux on Addr (Go:
   --  `http.ListenAndServe(addr, nil)`). Returns the terminal error
   --  (Go's ListenAndServe always returns a non-nil error).
   function Listen_And_Serve (Addr : String)
                              return Gada.Std.Errors.Error_Access;

end Gada.Std.Http;
