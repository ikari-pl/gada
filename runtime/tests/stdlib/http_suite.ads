--  AUnit suite for `Gada.Std.Http` (Go `net/http` server, Phase 7
--  wave 3 item 3).
--
--  Drives a real Listen_And_Serve on a loopback ephemeral port from a
--  spawned goroutine, then speaks raw HTTP/1.1 over Gada.Std.Net:
--  404 before any handler is registered, POST /echo round-trip with
--  a Content-Length body, and the "/" catch-all.

with AUnit;
with AUnit.Test_Cases;

package Http_Suite is

   type Http_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Http_Test);
   overriding function  Name (T : Http_Test) return AUnit.Message_String;

   procedure Test_Listen_Error (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Not_Found (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Bad_Requests (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Client_404 (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Client_Errors (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Echo_And_Catchall (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Client_Echo (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Split_Body (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Handler_Raises (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_500_Status (T : in out AUnit.Test_Cases.Test_Case'Class);

end Http_Suite;
