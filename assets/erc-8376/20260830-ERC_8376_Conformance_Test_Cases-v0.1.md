# ERC-8376 Conformance Test Cases v0.1

The cases a conformant implementation MUST cover at minimum, referenced from the
Test Cases section of [ERC-8376](../../ERCS/erc-8376.md).

1. **Score reproducibility.** A fixed `SignalVector` under the reference hard-rug profile yields a deterministic score. `liquidityRemoved = 6000`, `lpLockedShare = 0`, `proceedsWithdrawnShare = 9000`, `lpLockRemaining = 0`, `deployerSellRatio = 7000`, `privilegedPowers = 0x0011`, `priorUpheldClaims = 2` scores in the Conclusive band.
2. **Protective polarity.** The same vector with `lpLockedShare = 10000` and `lpLockRemaining = 365 days` scores materially lower. A protective signal at full strength MUST reduce the score, never raise it.
3. **Unavailable signals excluded.** Setting `priorUpheldClaims = type(uint16).max` yields the weighted mean over the remaining signals, not a score diluted by a zero contribution.
4. **Outcome signals rejected.** A report whose evidence set includes a price or market-cap field as a scored input MUST be rejected with `OutcomeSignalNotPermitted`.
5. **Honest failure scores low.** A launch with locked liquidity, no deployer sales, no retained powers, and a 95 percent price decline MUST score in the None or Weak band. This is the test that decides whether the standard is deployable.
6. **Release schedule respected.** `releaseProceeds` at the midpoint releases at most half; calling repeatedly within one block releases nothing further.
7. **Freeze halts release, and cannot be indefinite.** `releaseProceeds` reverts while `Frozen`; a launch frozen with no adjudication within `maxFreezeDuration()` returns to `Releasing`.
8. **No automatic refund.** No sequence of `submitReport` calls at any score or confidence opens a refund pool without an upheld claim.
9. **Pro-rata correctness.** With three buyers at 1, 2 and 7 ether and a pool of 5 ether, entitlements are 0.5, 1 and 3.5 ether, and the pool is fully drained with no residue.
10. **Net contribution.** A buyer who sold their entire allocation for more than they paid has an entitlement of zero and MUST NOT reduce other buyers' shares.
11. **Pull, not push.** A launch with 10,000 recorded buyers can open a refund pool in constant gas.
12. **Rejected claim forfeits bond.** After `adjudicate(claimId, Rejected, 0)`, the launch resumes releasing and the claimant's bond is not returned.
13. **Guard never reverts.** `checkLaunch` returns successfully for unknown launches, retracted reports, and settled launches.
14. **Resolution from a token address.** `launchesOf(token)` returns the launch, and `escrowOf`, `venueOf`, `deployerOf` and `tokenOf` round-trip correctly. A consumer holding only a token address can reach the guard.
15. **Identifier is derivable.** Recomputing `keccak256(abi.encode(chainid, escrow, token, deployer, nonce))` independently yields the same `launchId` the escrow assigned.
16. **Relaunch does not collide.** The same token relaunched by the same deployer receives a distinct `launchId`, and both appear in `launchesOf`.
17. **Deployer history is on-chain.** `launchesBy(deployer)` returns every launch by that address, so serial-deployer analysis needs no off-chain linkage.
18. **Identifier is chain-bound.** Deriving the same launch under a different `block.chainid` yields a different `launchId`, so an identifier cannot be replayed across networks.
19. **Unsupported vector version is not scored.** A report declaring a `vectorVersion` the consumer does not implement MUST be rejected with `UnsupportedVectorVersion` rather than scored as though it were version 1.
20. **Extension signals score on identical terms.** A `PATTERN_IMPERSONATION` report whose base signals all read clean scores in the Elevated band or above on `symbolCollision` and `nameSimilarity` alone, and an extension field reported as unavailable is excluded from both sums exactly as a base signal is.
21. **Extension leaves cannot collide.** An evidence leaf for an extension field derived as `keccak256(abi.encode(extensionSchema, fieldName))` differs from every base-signal `fieldId`.
22. **Detector reward is bounded and correctly attributed.** After `executeRemedy`, `claimDetectorReward` pays `detectorFeeBps` of the restitution to the detector recorded against the referenced report, never to the caller and never to the relayer of a `submitAndClaim`, and reverts on a claim that is not `Executed`. A `detectorFeeBps` exceeding `feeBps` MUST NOT be settable.
23. **Liquidity share is pool-agnostic.** A launch on a pool minting a fungible liquidity token and one whose positions are non-fungible both yield `lpLockedShare` in basis points of pool liquidity. Where a liquidity token is named it decides the value, and supplied liquidity amounts do not override it. A pool holding no liquidity, or one reporting more locked than it holds, yields the unavailability sentinel rather than zero.
24. **Disclosure at the point of purchase.** A consumer-conformant venue surfaces `abuseScore`, `confidence` and the report's `evidenceURI` to the buyer, and presents a launch with no live report as unknown rather than as safe.
