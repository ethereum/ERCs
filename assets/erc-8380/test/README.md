# ERC-8380 test cases

One test per row of the Test Cases table in the specification, in the same order.

Run with `forge test` from `assets/erc-8380/`.

## The verifier is deliberately not a rubber stamp

`BindingVerifier` issues a proof against one exact public-input vector and accepts it only
against that vector. A permissive mock would make every binding case in the table pass for
free: swap the executor, stretch the expiry, substitute the nullifier, and a verifier that
always returns true still says yes.

Swapping it for one that returns `true` unconditionally fails cases 7 and 8, which is how the
binding cases were checked to be testing the binding rather than the mock. Case 9 still passes
under that swap, so a lifted proof is stopped by `msg.sender != cap.executor` and not by the
circuit.

## Case 16 is fixed

`forge test` reports 17 passed. Case 16 used to fail because `capabilityIndex` is specified per
pair of `agentId` and `homeDomainId`, but `highestIssuedIndex` was keyed on `agentId` alone and
`issue` never received a domain. Once an agent operated in two domains the ceiling was shared,
and a genuine clone colliding at an index another domain already issued read as the
orchestrator's own reissue bug.

Fixed by moving the ceiling to `[agentId][homeDomainId]` and passing a domain to `issue`.
Orchestrator authorization for `issue` moved into `DomainRegistry` at the same time, one address
per domain rather than one for the whole Guard, since a single global orchestrator was the same
domain-blind-issuance root cause surfacing a second time.

## Commitment parity

The specification publishes the inputs and the formula for the parity vector but no expected
digest. Case 11 pins what the reference Solidity produces, so a circuit author has something to
compare against:

```
nullifier            = 0x387e1b17665773c440b8c1e1091763c9b9c2d2733eeaeaf1fdac1d17aa957338
capabilityCommitment = 0x0ca20742a17fa240d3abf6146f61981ee649b937a992f87bb599c1c1899f88cf
```
