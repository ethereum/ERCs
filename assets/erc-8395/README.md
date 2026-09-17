# ERC-8395 reference assets

These assets accompany [ERC-8395](../../ERCS/erc-8395.md). The Solidity helper
implements grant-proof verification. The clear-signing descriptor and display
fixtures are informative.

- [Test vectors and expected results](test-vectors.md)
- [Verifier pseudocode](verifier-pseudocode.md)

## Grant-proof helper

[DelegationVerifier.sol](DelegationVerifier.sol) verifies individual grant
cryptographic proofs and issuer-key binding. It does not validate the complete
Delegation Chain, attenuation, validity windows, revocation, HTTP signatures,
replay state, or application permissions.

The caller selects the issuer's profile and key from the immediate parent under
Section 3.6 of ERC-8395, never from the current grant's recipient `delegateProfile`
or `delegate`. Ethereum roots use Universal Account verification.

| Issuer verification profile | Helper entry point |
| --- | --- |
| Ethereum root or parent `erc8128` | `verifyEthereumGrant(grant, issuer, signature, false)`: Universal Account verification, including ERC-1271 and ERC-6492 |
| Parent `erc8128-eoa` | `verifyEthereumGrant(grant, issuer, signature, true)`: strict EOA verification even if the Account has code |
| Parent `ecdsa-p256-sha256` | `verifyP256Grant(grant, x, y, signature)`: the parent-authorized P-256 key, SHA-256 of `B`, and the registered 64-byte signature encoding |

The helper does not support other registered algorithms, including Ed25519.
Those profiles require another implementation of Section 3.6. The helper has no
owner, upgrade mechanism, or stored grant state. Its domain uses the executing
chain's ID and its own address.

No transaction is required: helper execution can use `eth_call`, including the
reverted simulation needed for ERC-6492 counterfactual verification. Equivalent
offchain verification uses the same domain and proof rules; Universal Account
verification can still require access to Account state on the Revocation
Account's chain.

## Deployment pins

The CREATE2 inputs and code hashes are identical across chains:

| Property | Value |
| --- | --- |
| `verifyingContract` | `0xE6ea89ebF649325c98E4B7CBc110ff611a1A054A` |
| CREATE2 deployer | `0x4e59b44847b379578588920ca78fbf26c0b4956c` |
| Salt | `0xc07accaa153ec807c474cf97ca6424b77f59aacf9db59509075bfbca281dd155` (`keccak256("erc8395.delegation-verifier")`) |
| Constructor arguments | None |
| Init-code hash | `0xfa4143ddfa526ebb1143830d64768730e6f9f4a6d120e32d47e66d0f64f94dac` |
| Runtime code hash | `0xd8f1c0fc6b70496e00c952db214d421e3a67fa4c7cebd3317483b15b890b1c93` |

### Build settings

Compile `DelegationVerifier.sol` with:

- Solidity `0.8.36+commit.8a079791`
- Optimizer enabled, `1000000` runs
- EVM target `osaka`; `viaIR` disabled
- Metadata bytecode hash `none`; default Solidity CBOR metadata retained
- Solady `0.1.26`, imported through `solady/`
- No constructor arguments, linked libraries, or immutables

The init code is the compiled creation bytecode with no appended constructor
arguments. These pins identify code and its deterministic address; they do not
assert deployment on any public chain. Executing the helper requires a chain
that supports its compiled bytecode and a deployment matching the runtime hash.

## Display examples

- [ERC-7730 descriptor](clear-signing/eip712-delegation.json)
- [Display fixtures](clear-signing/testsv2/eip712-delegation.tests.json)

The snapshots target local Anvil chain `31337` and preserve the original relative
fixture-to-descriptor link. They illustrate labels and formatting for every
signed member, including generic issuer identifiers and canonical public JWKs.
`remainingDelegations` is labelled **Further delegation levels allowed**, not a
count of grants or requests. Permission tokens retain their service-defined
meaning. Branding, supplementary descriptions, publication policy, and wallet
trust decisions do not change the signed grant or protocol validation rules.
