--  Top-level umbrella for Gada.Async.Channels — Go-style channels.
--
--  Per ADR-0002 (runtime layering) Gada.Async.Channels is a peer of
--  Gada.Async.Scheduler under the Gada.Async umbrella. Bounded and
--  unbounded variants are separate generic children:
--
--    * Gada.Async.Channels.Bounded   — make(chan T, N), N > 0
--    * Gada.Async.Channels.Unbounded — linked-list backed unbounded
--                                       channel (send never blocks);
--                                       Phase 3 item 5. Note: this is
--                                       NOT Go's `make (chan T)` form
--                                       (which is synchronous
--                                       rendezvous, not unbounded);
--                                       see Channels.Unbounded.ads
--                                       for the divergence rationale.
--
--  Both children depend on Gada.Async.Scheduler for Park / Unpark;
--  blocking Send / Receive route through the same primitives Phase 4
--  I/O and item 6's Select build on. The umbrella itself is empty —
--  it is a namespace, not a unit of behaviour.

package Gada.Async.Channels with Pure is
end Gada.Async.Channels;
