# ERC-8395 reference assets

These assets accompany [ERC-8395](../../ERCS/erc-8395.md). The Solidity helper
implements grant-proof verification.

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

`verifyP256Grant` verifies through the RIP-7212 P-256 precompile at
`0x0000000000000000000000000000000000000100` or, where it is absent, Solady's
fallback P-256 verifier at `0x000000000000D01eA45F9eFD5c54f037Fa57Ea1a`. On a
chain with neither, it returns false for every proof, valid or not, so false is
not a definitive invalid proof there. Before classifying false as
`bad_grant_signature`, a caller establishes that one of them is available on
that chain, for example from code at the fallback address or a known-valid
precompile probe; otherwise the result is `grant_verification_unavailable`.

No transaction is required: helper execution can use `eth_call`, including the
reverted simulation needed for ERC-6492 counterfactual verification. Equivalent
offchain verification uses the same domain and proof rules; Universal Account
verification can still require access to Account state on the Revocation
Account's chain.

## Deployment pins

The CREATE2 inputs and code hashes are identical across chains:

| Property | Value |
| --- | --- |
| `verifyingContract` | `0x7271B48567f0dD8fAb1ee505b091f253B0528B40` |
| CREATE2 deployer | `0x4e59b44847b379578588920ca78fbf26c0b4956c` |
| Salt | `0xc07accaa153ec807c474cf97ca6424b77f59aacf9db59509075bfbca281dd155` (`keccak256("erc8395.delegation-verifier")`) |
| Constructor arguments | None |
| Init-code hash | `0x5bbb62a29ff1ffe34c7eb99da7c0ebf18d5a631733d3f9ac24c14d5e8dcc40a8` |
| Runtime code hash | `0xe0c36f1c31c57ca71e049d89b06656462e619762be261e128084f23761456bf7` |

### Build settings

Compile `DelegationVerifier.sol` with:

- Solidity `0.8.36+commit.8a079791`
- Optimizer enabled, `1000000` runs
- EVM target `osaka`; `viaIR` disabled
- Metadata bytecode hash `none`; default Solidity CBOR metadata retained
- Solady `0.1.26`, imported through `solady/`
- No constructor arguments, linked libraries, or immutables

The init code is the compiled creation bytecode with no appended constructor
arguments. Executing the helper requires a chain that supports its compiled
bytecode and a deployment matching the runtime hash.

### Deployments

Anyone can deploy the helper to a chain with the CREATE2 inputs above; the
address is the same on every chain. Callers check the runtime code hash on
each chain they use.

## Clear signing

Clear-signing metadata for grants binds the `Delegation` type to the grant
domain. Wallets match it by the domain's chain ID and `verifyingContract`, so a
grant whose Revocation Account is on a chain the metadata doesn't list cannot be
clear-signed until that chain is added.

Wallets show an intent summary followed by grouped fields: access (issuer and
delegate), allowed services (each Audience), a notice that permission details
are not displayed, duration and sharing, request security, and signed request
parts. Permission tokens are not displayed because each means only what its
service defines, which generic metadata cannot describe; the application
presenting the grant shows them with each service's own descriptions. The grant
identifier and revocation epoch are optional details; the parent grant hash is
shown only for child grants. `remainingDelegations` is labelled
**Re-delegation levels**: the number of further delegation levels allowed, not
a count of grants or requests.

The fixtures cover every signed member across the listed chains, including
P-256 JWK and Ethereum delegates, a child grant, services with different
permissions, a service without permissions, and a grant that allows no further
delegation and does not require single-use requests. Branding, supplementary
descriptions, publication policy, and wallet trust decisions do not change the
signed grant or protocol validation rules.
