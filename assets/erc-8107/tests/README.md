# ERC-8107 test suite

This file lists what the reference tests check. The normative requirements are in
[ERC-8107](https://eips.ethereum.org/EIPS/eip-8107); section names below refer to it.

[`TrustRegistry.t.sol`](TrustRegistry.t.sol) is the reference suite and needs no network
access. The files in [`continuity/`](continuity/ExecutionWindow.fork.t.sol) run on an Ethereum mainnet fork and are
skipped without one.

## Attestation and authority

* `setTrust` rejects self-trust, stale nonces, already-expired attestations, and signatures from any address other than the name controller
* `setTrust` rejects attestations whose level is `Unknown` or `None`, and a later attestation restores trust after a revocation
* Any address can submit a valid signature, so relayed attestations succeed
* An ENS operator approval does not confer signing authority
* Contract controllers are accepted through ERC-1271, and reject signers they do not recognise
* An EOA with an EIP-7702 delegation attests by ECDSA even when its delegate has no `isValidSignature`, and through ERC-1271 when its delegate validates a non-ECDSA credential
* A malleable (high-s) signature is rejected even though it recovers the controller
* An ERC-1271 controller that returns empty, short or dirty data, reverts with large data, or consumes all forwarded gas yields `InvalidSignature`, including an EIP-7702 delegate with an empty fallback; trailing data after a valid magic word is ignored
* Wrapped names attest through the unwrapped NameWrapper holder, and approvals for a wrapped name are read from the NameWrapper rather than the registry; a per-token approval grants nothing
* Only the pinned NameWrapper is unwrapped: a name held by any other wrapper contract resolves to that contract as a raw controller, so its token holder cannot attest
* A pinned NameWrapper whose `ownerOf` reverts yields no controller, so the name cannot attest
* Nobody can revoke on behalf of an unregistered name or a wrapped `.eth` name past its grace period
* A wrapped `.eth` second-level name keeps every power, including new attestations, withdrawal, denial, clearing and nonce invalidation, through its grace period while the NameWrapper refuses management. Its authority ends one second after the grace period, its stored records persist, and the next holder controls them
* On a path `G → T → M`, an edge into `T` set while `T` was registered still carries the path after another party re-registers `T`, to any agent the new registrant endorses, through all three verification entry points. For a wrapped `T`, validation by node returns the same verdicts after a renewal as after such a re-registration, which is why the continuity checks under Wrapped Name Lifecycle fall to the coordinator
* An emancipated subname loses its authority one second after its expiry; an unemancipated subname keeps it after expiry, including with a NameWrapper expiry of zero
* An expired unwrapped name keeps its authority, documenting the behaviour described under Expired Unwrapped Names
* A parent that reassigns a subname hands the new controller the subname's authority and the trust placed in it, documenting the behaviour described under Parent-Controlled Subnames
* `TrustSet` carries the attestation's nonce, for single attestations and for each item in a batch
* Domain separation prevents an attestation from replaying onto a second registry
* Every row of the Revert Order table has a test that violates that row and every later row, and asserts the row's exact error and arguments

## Scope

* `(trustor, trustee, scope)` records are independent
* Path verification prefers scoped trust and falls back to universal only when no scoped record exists; an expired scoped record does not fall back
* A universal withdrawal voids the edge in every scope, including scopes with a stored grant, and a later universal attestation restores the scoped path
* A withdrawal in a named scope applies to that scope only and leaves other scopes intact
* Withdrawal sets the stored expiry to zero, for `revokeTrust` and `revokeTrustBatch`
* Withdrawal requires no prior trust, and a preemptive withdrawal in a scope blocks the universal fallback for that scope
* `revokeTrustBatch` withdraws in every listed scope, including scopes that were never granted, leaves unlisted scopes untouched, and emits one `TrustRevoked` per listed scope

## Withdrawal

* An approved operator's withdrawal of `G → X` leaves `G → A → X` valid, through all three verification entry points: withdrawal does not deny
* A withdrawn intermediary still carries paths that avoid the withdrawn edge
* Universal withdrawal overrides positive scoped records for the same pair, and scoped withdrawal leaves other scopes alone
* Withdrawing the only edge into a required anchor invalidates the anchored path, even where an unanchored path remains

## Denial

* A validator's denial of the target or of any intermediary voids the path, at every index, even when every edge verifies and the denied edge stores `Full`
* An intermediary's denial of its own successor voids that edge
* A non-validator's denial of a non-adjacent node, or a denial held off the path, does not void the path
* Universal denial applies in every scope, including over stored scoped grants; scoped denial applies only in its own scope; a cleared or unset scoped flag never lifts a universal denial
* Denial holds with `enforceExpiry` off and with either `minEdgeTrust`
* `setTrust`, `setTrustBatch`, `revokeTrust` and `revokeTrustBatch` never change the denial flag, and `setDenial` and `clearDenial` change no other bit of the stored record, checked against the raw storage word
* Clearing a denial reveals the stored `Full`, `Marginal`, `None` or `Unknown` exactly, and clearing a universal denial leaves a scoped denial in force
* For every combination of universal and scoped flags, `getDenial(A, B, bytes32(0)) || getDenial(A, B, s)` matches the verdict of path verification in scope `s`
* `setDenial` and `clearDenial` are controller-only: approved operators (on the registry or the NameWrapper), strangers, the NameWrapper itself and names without a controller are rejected, and a transfer moves the authority to the new controller
* Denying an agent already denied, or clearing a flag that is not set, succeeds and emits nothing, and `DenialSet` logs alone reconstruct every stored flag
* `clearDenial` reverts with `NonceChanged` when an attestation lands after review, including a front-run pre-signed attestation, one in another scope when clearing a universal denial, one for another trustee, and a nonce invalidation; the denial stays in force, and a clear at the new nonce then succeeds
* A withdrawal after review does not block `clearDenial`, and the clear reveals the withdrawal; a stale nonce reverts even when the flag is not set
* Without a raised floor, an attestation signed before review and submitted after the clear applies immediately, documenting the back-run the guard cannot stop; with the floor raised before the nonce is read, that attestation fails with `NonceTooLow` before and after the clear, and the reviewed endorsement stays in force
* `getDenial` returns the stored flag for the exact scope, not the effective denial
* A fuzzed sequence of endorsements, withdrawals, denials and clears over two scopes matches a direct model of the specification for `getTrust`, `getDenial`, the edge check and the validator check

## Revocation durability and quarantine

* An attestation signed before a withdrawal remains submittable and restores trust, which is the hazard described under Pre-Signed Attestations
* `invalidateNonces` closes it: after raising the floor, the pre-signed attestation is rejected and the withdrawal holds
* An attestation submitted while a denial is in force updates the stored endorsement but does not admit the agent, and clearing the denial reveals it
* Signatures at or below a new floor are rejected, while a signature above it still lands
* The floor is trustor-wide, applying to every trustee and scope, and still permits fresh attestations above it
* Neither a single attestation nor a single `invalidateNonces` call can raise the floor by more than 2^32; the largest allowed jump succeeds and can be repeated, and near `type(uint64).max` the bound caps rather than wrapping
* At a floor of `type(uint64).max`, `setTrust`, `setTrustBatch` and `invalidateNonces` revert with `NonceTooLow` whose `required` saturates at `type(uint64).max`; the last nonce is usable exactly once
* Approved operators cannot call `invalidateNonces`

## Path verification

* Direct and transitive paths, missing edges, paths shorter than two nodes, and paths exceeding `maxPathLength`
* `minEdgeTrust` rejects marginal edges when `Full` is required
* Expiry is enforced when `enforceExpiry` is set and ignored when it is not
* A withdrawn edge voids the path
* `verifyPath`, `validateParticipantWithPath` and `validateParticipantAddress` reach the same verdict in every withdrawal and denial case above
* Paths containing a repeated node are rejected, even when every individual edge verifies
* `requiredAnchors` is part of the verdict: a path whose edges all verify but which traverses no anchor is invalid, and neither the validator nor the target can satisfy an anchor
* `ValidationParams` outside the stated constraints are rejected

## ENSv2 migration

Migration is modelled with a mock that holds the name and does not implement `isValidSignature`, once as the unwrapped registry owner and once as the NameWrapper holder.

* `setTrust` from a migrated name reverts with `InvalidSignature`, including for an attestation signed before migration
* `revokeTrust`, `setDenial`, `clearDenial` and `invalidateNonces` for a migrated name revert with `NotAuthorized`, for both the former controller and a former approved operator, and the stored endorsement and denial persist
* A stored path through a migrated intermediary or gatekeeper still verifies, through `verifyPath` and both gate functions, and a denial recorded before migration still applies
* `validateParticipantAddress` fails when a migrated terminal node's resolver is cleared, and passes when the legacy resolver is retained

The reference tests model the NameWrapper with a mock whose `ownerOf` follows the deployed
contract's expiry rules, with the NameWrapper expiry set at the end of the grace period.
The lifecycle cases above, and the migration and `clear` behaviour described under ENSv2
Compatibility and Migration, were also checked against the deployed contracts: the ENSv1
cases on an Ethereum mainnet fork, and the ENSv2 cases on a Sepolia fork of the ENSv2
deployment at block 11,906,480, since ENSv2 is not yet deployed on mainnet. On the
mainnet fork, wrapped names were renewed through each path a renewal can take: through
`NameWrapper.renew`, both from a registrar controller and called directly by an authorised
controller; and through
the BaseRegistrar's `renew` called directly, which leaves the NameWrapper expiry behind,
with the effects described under Wrapped Name Lifecycle and on
`validateParticipantAddress`. Those fork tests are not part of the reference suite because they
need network access.

The execution-window and subname continuity cases among the identity gate tests also
run on a mainnet fork, against the deployed ETHRegistrarController and BaseRegistrar with
unwrapped names, and with names wrapped through the NameWrapper for the expiry check and
the subname cases. They are in
[`tests/continuity/ExecutionWindow.fork.t.sol`](continuity/ExecutionWindow.fork.t.sol),
[`tests/continuity/ExpiryDeadline.fork.t.sol`](continuity/ExpiryDeadline.fork.t.sol)
and
[`tests/continuity/SubnameBoundary.fork.t.sol`](continuity/SubnameBoundary.fork.t.sol),
and apply the continuity check through a non-normative coordinator-side implementation,
[`tests/continuity/RegistrationBoundary.sol`](continuity/RegistrationBoundary.sol).
A non-normative coordinator,
[`tests/continuity/ReferenceCoordinator.sol`](continuity/ReferenceCoordinator.sol),
combines the gate, the continuity check, the liveness check and the expiry check from
the decision through execution, and
[`tests/continuity/ReferenceCoordinator.fork.t.sol`](continuity/ReferenceCoordinator.fork.t.sol)
runs it on the same fork. They are skipped without a fork.

## Interface detection

* `supportsInterface` returns `true` for `IERC165` and `ITrustRegistry`, and `false` for `0xffffffff` and unrelated identifiers. The reference implementation also returns `false` for `0x93e686a3`, the identifier of the withdrawn `ITrustRegistryExtended`
* The identifiers published in Interface Detection match Solidity's computed values, guarding the spec's literals against interface drift
* The earlier identifiers `0x42b46ef5` and `0x31f35e83` are not reported; the first differs from the current one by exactly the `setDenial`, `clearDenial` and `getDenial` selectors, and the second by exactly the replacement of the boolean `setDenial` with `setDenial` and `clearDenial`
* `supportsInterface` stays within the 30,000 gas budget

## Identity gates and ERC-8001 integration

* Gates are namespaced per coordinator: two coordinators registering the same coordination type hold independent gates, and neither can modify or remove the other's
* Registering a gate does not require controlling the named gatekeeper
* Both validation functions revert with `GateNotFound` when no gate is enabled, including when the gate is read under the wrong coordinator address and after it has been removed
* Both validation functions reject paths shorter than two nodes
* `validateParticipantWithPath` rejects paths that do not start at the gatekeeper or do not terminate at the named participant
* A gate with a non-empty `requiredAnchors` rejects a direct path from its gatekeeper
* `setIdentityGate` rejects a non-empty `requiredAnchors` with `maxPathLength` 1 with `UnsatisfiableAnchors` and leaves any existing gate unchanged. It accepts every other configuration the Validation Parameters Constraints accept, including `maxPathLength` 1 without anchors and `maxPathLength` 2 with anchors, where a path through an anchor passes and one that misses it fails. `verifyPath` given the same rejected parameters returns `false` rather than reverting
* `validateParticipantAddress` rejects a participant address the terminal node does not resolve to, the zero address, nodes with no `addr` record, and nodes behind an off-chain resolver
* After a re-registration that leaves the `addr` record untouched, `validateParticipantAddress` admits the previous holder's address and not the new registrant's until the new registrant sets the record, and then only the new registrant's; a registration that sets the record in the same transaction leaves no such window
* A wrapped terminal node past its NameWrapper expiry, whose `addr` record still resolves, fails `validateParticipantAddress` because it has no controller, while `validateParticipantWithPath` still passes; once a NameWrapper renewal restores the holder, it passes again
* A lapsed unwrapped holder that repoints the `addr` record after its grace period moves the address `validateParticipantAddress` admits
* With two endorsed names resolving to the same address, denying one at universal scope rejects the address through the path to that name, and `validateParticipantAddress` still admits it through the path to the other
* With a path whose continuity check passes at block B, a registration of a `.eth` second-level name on it in block B+1, ordered immediately before the executing transaction, leaves `validateParticipantWithPath` returning `true`, whether the registrant is a new holder or the previous one. A coordinator that reads `nameExpires` at block B and requires it unchanged rejects that execution. It executes when the registration follows the execution or nothing is registered, and rejects on a renewal in the window
* For a `.eth` second-level name live at block B, wrapped or unwrapped, a coordinator that requires `block.timestamp` no later than the expiry read at block B plus `GRACE_PERIOD`, or that expiry unchanged, rejects a registration at the first second one is possible, ordered before execution in the same block, and a renewal followed by a lapse and a registration by the same holder. It executes on a renewal in the window, at the last second of the grace period, and after the grace period when nothing has been registered. A deadline computed from the expiry read in the executing transaction accepts both registrations
* For a name below a `.eth` second-level name, as trustee or trustor, the continuity check rejects an attestation once the second-level ancestor is registered again, by another holder or the same one, and not after three renewals of it, nor past the ancestor's grace period while nothing is registered. It also rejects one once the NameWrapper emits `NameWrapped` for the name: when a live parent creates an emancipated subname again after its NameWrapper expiry, or when the holder unwraps the name and wraps it again. The same holds for an ancestor below the second-level name that is unwrapped and wrapped again. A new signature restores the attestation. A parent reassigning a subname that still has a holder leaves it eligible, as do a sibling created under the same parent, an unwrap alone, and a child of the name wrapped for the first time. A name proof that does not hash to the node fails closed
* A coordinator that applies the gate, the continuity check and the liveness check at block B, and at execution the expiry check, the liveness check and the gate again, executes on a path through a wrapped second-level name, an emancipated subname or an unwrapped second-level name, by node and by address. It rejects at execution a path whose emancipated subname trustor passes its NameWrapper expiry after B, and one whose wrapped second-level trustor, decided on in its grace period, passes its NameWrapper expiry with nothing registered, where `validateParticipantWithPath` still returns `true`. It rejects a registration in the window by its expiry check, and decides against a name registered again before B at the continuity check while the gate passes
* `resolveAgent` returns the zero address, without reverting, for a resolver with no code and for empty, short, dirty or reverting responses; it reads only the first word of an oversized response; a resolver that consumes gas costs the caller at most the cap, and cannot stop a coordinator that validates several participants in one call from validating the others
