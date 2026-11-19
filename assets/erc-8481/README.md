# Pre-sign report executable assets

From this directory, install the pinned test library and run:

```sh
mkdir -p lib
git clone --depth 1 --branch v1.17.0 https://github.com/foundry-rs/forge-std.git lib/forge-std
git -C lib/forge-std checkout f3dae6e6ee381f25eb6a246f7da9b85c91a68219
forge test
```

Validated with Forge 1.7.1, Solidity 0.8.30, EVM Prague, and the forge-std commit above:
31 tests pass (14 existing delegate vectors, 12 anchor cases, 5 historical-signer
cases). Each of the two fuzz tests runs 256 cases. No RPC is required.

## Candidate anchor implementation

`PresignReportAnchor` implements the draft's `IPresignReportAnchor`. First publication
is keyed by `(msg.sender, reportHash)`. Repeated publication emits the event but
cannot move the original timestamp or block number; another caller gets a separate
record. There is no owner, upgrade path, caller allowlist or funds handling.

Use `PresignReportAnchor` only on a chain where `block.number` is that chain's own
block number. On Arbitrum chains, use `ArbitrumPresignReportAnchor`, which reads
`ArbSys(address(100)).arbBlockNumber()` and reverts if that read is unavailable. The
choice is explicit at deployment; there is no chain-ID allowlist or runtime fallback
to the wrong clock. The Arbitrum test stubs ArbSys; it is not an Arbitrum fork test.

Tests cover caller isolation, independent reports, repeat publication, event fields,
zero hashes, the 512-byte URI limit, a zero timestamp, checked 64-bit clock conversion,
and the Arbitrum clock. The contract records publication only: a consumer still checks
report content, signatures, identity binding, trusted history and chain canonicality.
Neither contract has been deployed as part of this contribution.

## Historical-signer vectors

The signer tests use real EIP-712 signatures, a rotating ERC-1271 test signer, the
candidate anchor, and a small owner/wallet registry fixture. Foundry snapshot replay
models reading an earlier registry state. Fixed input hashes stand in for canonical
report JSON; this is not a complete report verifier or an archive RPC implementation.

The cases show:

- Clearing a wallet or transferring ownership rejects the old current binding,
  while a report anchored when the key was bound still has that historical binding.
- Adding a binding later cannot retroactively authorize an earlier anchoring.
- The EIP-712 domain uses the registry chain, even when the anchor is on another chain.
- Rotating the key inside an ERC-1271 signer leaves the registry binding unchanged,
  but today's `isValidSignature` rejects the old report. Replaying the signature
  check in the earlier state accepts it.

The last case is now normative: when auditing an anchored report, step 2 runs at the same
historical block as step 3, both whether the signer has code (EIP-7702 can change it) and the
ERC-1271 `isValidSignature` call. A verifier without archive state treats the report as not
read, not as unsigned. Pre-sign checks still use current state.

Cross-chain timestamp-to-block selection, reorg handling, archive unavailability,
and historical content-addressed/mutable registration files are outside this harness.

The pre-existing `PreSignDelegateVectors.t.sol` remains MIT-licensed by it44. New
anchor and historical-signer assets are CC0-1.0. The delegate vectors are unchanged.

## On-list list document vectors

`on-list/` holds JSON vectors for the `address.on-list` list document: normalization, the list hash, matching,
not-read reasons and diffs between list versions. Run `python3 on-list/onlist_vectors.py` (standard library only).
They are CC0-1.0, by the RUNECLAW team.

## Coverage vectors

`coverage/` holds JSON vectors for the report's `coverage` object, the answer to the case where a source cannot decode
part of a request (review: Revinand). Run `python3 coverage/coverage_vectors.py` (standard library only; it reuses
keccak256 and RFC 8785 from `on-list/onlist_vectors.py`); `--write` regenerates `coverage.json` deterministically.

- `wrapped-approve-unsupported-batch`: `approve(spender, 2^256 - 1)` inside an ERC-7821 batch `execute(bytes32,bytes)`
  the source does not decode. Only the outer target is listed, every finding is read, and `coverage` is `partial`
  with a gap at `tx.calls[0]` (`unsupported-selector`, `not-inspected`). The hidden call is given under `hidden`.
- `direct-approve-complete`: the same approval as a direct call, `coverage` `complete`, one approval entity.
- `wrapped-approve-decoded-batch`: the batch sent to a source that decodes ERC-7821: `complete`, and the approval
  entity carries `path` `tx.calls[0].inner[0]`.
- `coverage-is-signed`: the first report with `coverage` rewritten to `complete` has another `reportHash`.
- `conformance`: 20 malformed `coverage` values (absent, status and gaps disagreeing, values outside the enums, bad
  or out-of-range paths, a duplicate path, `nested` disagreeing with `reason`, an extra member) and 3 valid ones;
  4 approval `path` cases (bad syntax, out of range, disagreeing with `callIndex`, and a valid `callIndex` + `path`).
  Array and object values for `path` and `reason` return conformance errors instead of raising a Python exception.

Each vector carries the subject digest, `reportHash` and the EIP-712 digest the source would sign; `signature` is a
placeholder. The batch calldata and one EIP-712 digest were also recomputed with Foundry's `cast`, and agree. CC0-1.0.
