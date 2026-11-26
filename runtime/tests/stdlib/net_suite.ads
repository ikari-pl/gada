--  AUnit suite for `Gada.Std.Net` (Go `net` port, Phase 7 wave 3).
--
--  Covers: IP parsing/formatting (IPv4 + IPv6 incl. :: compression
--  and v4-mapped), LookupHost (localhost hit + unknown-host error),
--  TCP Dial/Listen/Accept with a real loopback echo round-trip
--  (incl. EOF on peer close, read/write on closed conn, refused
--  dial, bad network/address), and UDP ListenPacket/WriteTo/
--  ReadFrom plus connected-Dial UDP write/read.

with AUnit;
with AUnit.Test_Cases;

package Net_Suite is

   type Net_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Net_Test);
   overriding function  Name (T : Net_Test) return AUnit.Message_String;

   procedure Test_Parse_IP_V4 (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Parse_IP_V6 (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_IP_Nil_Equal (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Lookup_Host (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_TCP_Echo (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_TCP_Errors (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_UDP (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Listen_Errors (T : in out
      AUnit.Test_Cases.Test_Case'Class);

end Net_Suite;
