--  AUnit suite for `Gada.Std.Bytes` (Go `bytes` port, Phase 5).
--
--  Covers the Go-semantics edge behavior: 0-based/-1 Index contract,
--  empty-separator Split, Join, Compare ordering, and the
--  Buffer/Reader read-offset model (Write appends at the end,
--  Read consumes from the front, N = 0 at end of data).

with AUnit;
with AUnit.Test_Cases;

package Bytes_Suite is

   type Bytes_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Bytes_Test);
   overriding function  Name (T : Bytes_Test) return AUnit.Message_String;

   procedure Test_Conversions (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Equal_Compare (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Index_Contains (T : in out
      AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Prefix_Suffix (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Split_Join (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Reader (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Edges (T : in out AUnit.Test_Cases.Test_Case'Class);

end Bytes_Suite;
