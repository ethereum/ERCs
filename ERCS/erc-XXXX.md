---
eip: XXXX
title: Encrypted Token Interface
description: An interface for fungible tokens with FHE-encrypted balances and zero-knowledge transfer verification.
author: Valisthea (@Valisthea)
discussions-to: https://ethereum-magicians.org/
status: Draft
type: Standards Track
category: ERC
created: 2026-04-12
requires: 20, 165
---

## Abstract

This EIP defines a minimal interface for **fungible tokens with encrypted balances**. Token balances are stored as Fully Homomorphic Encryption (FHE) ciphertexts. Transfers are verified via zero-knowledge proofs without revealing amounts, sender balances, or recipient balances to any on-chain observer.

Unlike [ERC-20](./eip-20.md) where `balanceOf` returns a plaintext `uint256`, this interface returns an opaque ciphertext that only the balance owner can decrypt. Arithmetic operations on balances (credit, debit, comparison) are performed homomorphically by the execution environment without any party observing plaintext values.

This interface is backwards-compatible with [ERC-20](./eip-20.md) for public aggregate values (`totalSupply`, `name`, `symbol`, `decimals`) while introducing encrypted counterparts for all privacy-sensitive operations.

## Motivation

[ERC-20](./eip-20.md) tokens expose all balances and transfer amounts publicly. This creates several critical problems:

1. **Portfolio exposure**: Anyone can see how much of any token an address holds, enabling targeted attacks, social engineering, and front-running.

2. **Transfer surveillance**: Every transfer amount is public, enabling transaction graph analysis, de-anonymization, and MEV extraction.

3. **Governance coercion**: In DAO voting with token-weighted governance, visible balances enable vote buying, whale tracking, and political coercion.

4. **Regulatory conflict**: Financial privacy regulations (GDPR Article 17 "right to be forgotten", MiCA, HIPAA for health tokens) conflict with permanent public ledger storage.

5. **MEV extraction**: Visible pending transactions enable sandwich attacks, front-running, and other MEV strategies that extract value from users.

Existing privacy solutions (mixers, L2 privacy chains) operate outside the ERC ecosystem, breaking composability with DeFi protocols, wallets, and indexers. This EIP brings privacy into the token interface itself, allowing any compliant wallet or protocol to interact with encrypted tokens through a well-defined interface.

### Why not just add a privacy layer on top?

Privacy layers (Tornado Cash, Aztec Connect) are external wrappers. They break composability: a "shielded" token cannot be used in Uniswap, Aave, or Compound without unshielding first — defeating the purpose. This EIP makes privacy native to the token interface. A compliant lending protocol can accept encrypted collateral, compute liquidation thresholds homomorphically, and never see the actual collateral amount.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- **Ciphertext**: An FHE-encrypted value. Represented on-chain as `bytes`. Only the owner of the corresponding decryption key can recover the plaintext.
- **Proof**: A zero-knowledge proof (SNARK/STARK) attesting to the validity of an operation without revealing the operands.
- **Blind Transfer**: A transfer where the amount is encrypted. The proof guarantees: (a) sender has sufficient balance, (b) amount is non-negative, (c) no overflow occurs, (d) balances are correctly updated.
- **Selective Disclosure**: The ability for a balance owner to prove a property of their balance (e.g., "≥ 1000") without revealing the exact value.
- **Encryption Scheme**: The FHE scheme used. This EIP is scheme-agnostic but RECOMMENDS TFHE (Torus FHE) for its boolean circuit efficiency.

### Interface

Every compliant contract MUST implement the following interface:

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0;

/// @title ERC-1680 Encrypted Token Interface
/// @notice An interface for tokens with FHE-encrypted balances
///         and zero-knowledge transfer verification.

interface IERC1680 {

    // ──────────────────────────────────────────────
    //  Custom Errors
    // ──────────────────────────────────────────────

    error ProofVerificationFailed(bytes32 proofHash);
    error NonceAlreadyUsed(uint256 nonce);
    error InvalidCiphertext();
    error InsufficientEncryptedBalance();
    error KeyVersionMismatch(uint256 expected, uint256 provided);

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    /// @notice Emitted on every blind transfer.
    /// @dev    The `amount` field is intentionally absent.
    ///         The `proofHash` allows anyone to verify the transfer
    ///         was valid without learning the amount.
    /// @param  from        The sender address.
    /// @param  to          The recipient address.
    /// @param  proofHash   Keccak256 hash of the ZK proof.
    /// @param  keyVersion  The FHE key version used for this transfer.
    event BlindTransfer(
        address indexed from,
        address indexed to,
        bytes32 proofHash,
        uint256 keyVersion
    );

    /// @notice Emitted when an encrypted approval is set.
    /// @param  owner    The token owner.
    /// @param  spender  The approved spender.
    event BlindApproval(
        address indexed owner,
        address indexed spender
    );

    /// @notice Emitted when tokens are minted (encrypted).
    /// @param  to         The recipient.
    /// @param  proofHash  Proof that mint is authorized and valid.
    event BlindMint(
        address indexed to,
        bytes32 indexed proofHash
    );

    /// @notice Emitted when tokens are burned (encrypted).
    /// @param  from       The address burning tokens.
    /// @param  proofHash  Proof that burn is valid.
    event BlindBurn(
        address indexed from,
        bytes32 indexed proofHash
    );

    /// @notice Emitted when the FHE key is rotated.
    /// @param  oldVersion  The previous key version.
    /// @param  newVersion  The new key version.
    event KeyRotated(
        uint256 indexed oldVersion,
        uint256 indexed newVersion
    );

    // ──────────────────────────────────────────────
    //  ERC-20 Compatible (Public Metadata)
    // ──────────────────────────────────────────────

    /// @notice Returns the token name.
    function name() external view returns (string memory);

    /// @notice Returns the token symbol.
    function symbol() external view returns (string memory);

    /// @notice Returns the number of decimals.
    function decimals() external view returns (uint8);

    /// @notice Returns the total supply.
    /// @dev    Implementations MAY return the actual total supply (public)
    ///         or MAY return 0 if total supply itself is confidential.
    ///         If confidential, `totalSupplyEncrypted()` MUST be implemented.
    function totalSupply() external view returns (uint256);

    // ──────────────────────────────────────────────
    //  Encrypted Balance Queries
    // ──────────────────────────────────────────────

    /// @notice Returns the encrypted balance of `account`.
    /// @dev    The returned bytes are an FHE ciphertext. Only `account`
    ///         (or a party holding the decryption key) can decrypt it.
    ///         External observers see opaque bytes.
    /// @param  account  The address to query.
    /// @return The FHE ciphertext of the balance.
    function encryptedBalanceOf(address account)
        external
        view
        returns (bytes memory);

    /// @notice Returns the FHE scheme identifier used by this token.
    /// @dev    Allows wallets and protocols to select the correct
    ///         decryption/re-encryption logic.
    ///         Example return values: "TFHE-v0.3", "OpenFHE-BFV", "CONCRETE-v1"
    /// @return A string identifying the FHE scheme and version.
    function encryptionScheme() external view returns (string memory);

    /// @notice Returns the public encryption key of the token contract.
    /// @dev    Users encrypt their inputs with this key before submitting.
    ///         The contract (or its FHE co-processor) holds the
    ///         corresponding secret key.
    /// @return The public key bytes.
    function publicKey() external view returns (bytes memory);

    /// @notice Returns the current FHE key version.
    /// @dev    Incremented on each key rotation. Proofs MUST reference
    ///         the active key version to be accepted.
    /// @return The current key version number.
    function keyVersion() external view returns (uint256);

    /// @notice Returns whether a given key version is currently active.
    /// @param  version  The key version to query.
    /// @return True if the version is the current active key.
    function isKeyActive(uint256 version) external view returns (bool);

    // ──────────────────────────────────────────────
    //  Blind Transfers
    // ──────────────────────────────────────────────

    /// @notice Transfer an encrypted amount to `to`.
    /// @dev    The `encryptedAmount` is an FHE ciphertext of the amount.
    ///         The `proof` is a ZK proof attesting:
    ///           1. sender balance >= amount (non-negative remainder)
    ///           2. amount >= 0
    ///           3. new sender balance = old sender balance - amount
    ///           4. new recipient balance = old recipient balance + amount
    ///         The contract MUST verify the proof on-chain before applying
    ///         the homomorphic balance update.
    /// @param  to               The recipient address.
    /// @param  encryptedAmount  FHE ciphertext of the transfer amount.
    /// @param  proof            ZK proof of transfer validity.
    /// @return True if the transfer was verified and applied.
    function blindTransfer(
        address to,
        bytes calldata encryptedAmount,
        bytes calldata proof
    ) external returns (bool);

    /// @notice Transfer from `from` to `to` using an encrypted approval.
    /// @dev    Requires prior `blindApprove` from `from` to `msg.sender`.
    ///         The proof MUST additionally attest that the transfer
    ///         does not exceed the encrypted allowance.
    /// @param  from             The sender address.
    /// @param  to               The recipient address.
    /// @param  encryptedAmount  FHE ciphertext of the transfer amount.
    /// @param  proof            ZK proof including allowance verification.
    /// @return True if the transfer was verified and applied.
    function blindTransferFrom(
        address from,
        address to,
        bytes calldata encryptedAmount,
        bytes calldata proof
    ) external returns (bool);

    // ──────────────────────────────────────────────
    //  Encrypted Approvals
    // ──────────────────────────────────────────────

    /// @notice Approve `spender` to transfer up to `encryptedAmount`.
    /// @dev    The allowance is stored as an FHE ciphertext.
    ///         Subsequent `blindTransferFrom` calls deduct from this
    ///         allowance homomorphically.
    ///         The proof MUST attest that the ciphertext is well-formed
    ///         and non-negative. It MUST NOT require a balance check at
    ///         approval time — balance sufficiency is checked at transfer time.
    /// @param  spender          The approved spender.
    /// @param  encryptedAmount  FHE ciphertext of the max allowance.
    /// @param  proof            Proof that the ciphertext is valid and non-negative.
    /// @return True if the approval was set.
    function blindApprove(
        address spender,
        bytes calldata encryptedAmount,
        bytes calldata proof
    ) external returns (bool);

    /// @notice Returns the encrypted allowance of `spender` for `owner`.
    /// @param  owner    The token owner.
    /// @param  spender  The approved spender.
    /// @return The FHE ciphertext of the remaining allowance.
    function encryptedAllowance(address owner, address spender)
        external
        view
        returns (bytes memory);

    // ──────────────────────────────────────────────
    //  Selective Disclosure (OPTIONAL)
    // ──────────────────────────────────────────────

    /// @notice Verify a property proof about an account's balance.
    /// @dev    Allows an account to prove a predicate about their balance
    ///         (e.g., "my balance >= 1000") without revealing the balance.
    ///         The `predicate` encodes the condition type and threshold.
    ///         The `proof` is a ZK proof binding the predicate to the
    ///         account's actual encrypted balance.
    ///         The proof MUST be generated by `account` or an authorized
    ///         delegate. Third-party probing is not possible — proof
    ///         generation requires knowledge of the plaintext balance.
    /// @param  account    The address whose balance is being proven.
    /// @param  predicate  Encoded predicate (condition + threshold).
    /// @param  proof      ZK proof of the predicate's truth.
    /// @return True if the predicate is verified.
    function verifyBalancePredicate(
        address account,
        bytes calldata predicate,
        bytes calldata proof
    ) external view returns (bool);

    // ──────────────────────────────────────────────
    //  Mint / Burn (OPTIONAL)
    // ──────────────────────────────────────────────

    /// @notice Mint encrypted tokens to `to`.
    /// @dev    Only callable by authorized minter.
    ///         The `encryptedAmount` is added homomorphically to
    ///         the recipient's encrypted balance.
    /// @param  to               The recipient.
    /// @param  encryptedAmount  FHE ciphertext of the mint amount.
    /// @param  proof            Proof of authorized minting.
    function blindMint(
        address to,
        bytes calldata encryptedAmount,
        bytes calldata proof
    ) external;

    /// @notice Burn encrypted tokens from `msg.sender`.
    /// @param  encryptedAmount  FHE ciphertext of the burn amount.
    /// @param  proof            Proof that balance >= amount.
    function blindBurn(
        bytes calldata encryptedAmount,
        bytes calldata proof
    ) external;
}
```

### Interface Detection

Compliant contracts MUST implement [ERC-165](./eip-165.md) and return `true` for the interface ID of `IERC1680`.

```solidity
bytes4 constant IERC1680_ID = type(IERC1680).interfaceId;
```

### Optional Extensions

Implementations MAY additionally implement one or more of the following extension interfaces:

**`IERC1680_Shielded`** — Bridge between the public pool (compatible with [ERC-20](./eip-20.md)) and the encrypted pool:

```solidity
interface IERC1680_Shielded is IERC1680 {
    event Shielded(address indexed account, uint256 amount);
    event Unshielded(address indexed account, uint256 amount);

    /// @notice Move tokens from public ERC-20 balance to encrypted balance.
    function shield(uint256 amount) external;

    /// @notice Move tokens from encrypted balance to public ERC-20 balance.
    /// @param  proof  Proof of sufficient encrypted balance.
    function unshield(uint256 amount, bytes calldata proof) external;
}
```

**`IERC1680_ConfidentialSupply`** — For tokens that also hide total supply:

```solidity
interface IERC1680_ConfidentialSupply is IERC1680 {
    function totalSupplyEncrypted() external view returns (bytes memory);
}
```

**`IERC1680_Fees`** — FHE computation fee interface:

```solidity
interface IERC1680_Fees is IERC1680 {
    event FeeCollected(address indexed payer, address indexed recipient, uint256 amount);
    function feeConfig() external view returns (
        address feeRecipient,
        uint256 feeBasisPoints,
        uint256 pGasPerGate
    );
    function estimateBlindTransferCost() external view returns (uint256 pGas);
}
```

**`IERC1680_Batch`** — Aggregated batch blind transfers:

```solidity
interface IERC1680_Batch is IERC1680 {
    function blindBatchTransfer(
        address[] calldata recipients,
        bytes[] calldata encryptedAmounts,
        bytes calldata batchProof
    ) external returns (bool);
}
```

### Predicate Encoding

The `predicate` parameter in `verifyBalancePredicate` MUST use the following encoding:

```solidity
// Predicate = abi.encode(PredicateType, threshold)
enum PredicateType {
    GTE,    // balance >= threshold
    LTE,    // balance <= threshold
    EQ,     // balance == threshold
    NEQ,    // balance != threshold
    RANGE   // lowerBound <= balance <= upperBound
}

// For RANGE type:
// predicate = abi.encode(PredicateType.RANGE, lowerBound, upperBound)
```

### Proof Format

This EIP does not mandate a specific ZK proof system. Implementations MAY use Groth16, Halo2, Nova, Plonk, or any system that provides:

1. Succinctness: Proof size SHOULD be ≤ 1 KB.
2. Non-interactivity: Proof generation requires no interaction with the verifier.
3. Soundness: Negligible probability of false proof acceptance.

The proof MUST encode the following public inputs (available to the verifier):

```
publicInputs = {
    from:                address,    // sender
    to:                  address,    // recipient
    encryptedAmountHash: bytes32,    // hash of the encrypted amount
    oldBalanceHashFrom:  bytes32,    // hash of sender's pre-transfer encrypted balance
    newBalanceHashFrom:  bytes32,    // hash of sender's post-transfer encrypted balance
    oldBalanceHashTo:    bytes32,    // hash of recipient's pre-transfer encrypted balance
    newBalanceHashTo:    bytes32,    // hash of recipient's post-transfer encrypted balance
    nonce:               uint256     // replay protection
}
```

### Re-encryption

When a user needs to read their own balance, they SHOULD NOT request decryption on-chain. Instead, the FHE co-processor or execution environment MUST support **re-encryption**: transforming the ciphertext from the contract's public key to the user's personal public key, off-chain, so that only the user can decrypt the result on their device.

## Rationale

### Why encrypted balances instead of commitments?

Commitment schemes (Pedersen, Poseidon) hide values but don't support computation. You can't add two Pedersen commitments and get a valid commitment to the sum without the sender's help. FHE ciphertexts support homomorphic addition and comparison natively, enabling the contract to update balances without any party revealing plaintext values.

### Why separate events without amounts?

[ERC-20](./eip-20.md)'s `Transfer(from, to, amount)` leaks the amount. `BlindTransfer(from, to, proofHash, keyVersion)` preserves the minimum information needed for indexing (who transferred to whom) without revealing how much. The `proofHash` enables off-chain auditors (with appropriate keys) to verify transfer validity.

### Why optional `totalSupply`?

Some use cases (e.g., confidential security tokens) require hiding even the total supply. Making `totalSupply` optionally zero with a separate `totalSupplyEncrypted()` extension accommodates both public and confidential supply models.

### Why `verifyBalancePredicate` instead of `balanceOf`?

In DeFi, you rarely need the exact balance. You need to know "does this user have enough collateral?" (predicate: `balance >= threshold`). Selective disclosure via predicate proofs gives protocols exactly the information they need — and nothing more.

### Why is balance check absent from `blindApprove`?

[ERC-20](./eip-20.md)'s `approve` does not check that the owner currently holds the approved amount — the check occurs at `transferFrom` time. This EIP follows the same pattern: `blindApprove` verifies only that the ciphertext is well-formed and non-negative. Balance sufficiency is proven at `blindTransferFrom` time via the ZK proof.

### Why a key version field?

FHE key rotation (e.g., due to key compromise or scheme upgrade) invalidates all ciphertexts encrypted under the old key. The `keyVersion` field on events and the `keyVersion()` / `isKeyActive()` query functions allow clients and indexers to detect key rotations and re-encrypt balances under the new key.

### Backwards Compatibility with [ERC-20](./eip-20.md)

The public metadata functions (`name`, `symbol`, `decimals`, `totalSupply`) are identical to [ERC-20](./eip-20.md). This allows block explorers and basic wallet UIs to display token identity. The encrypted functions (`blindTransfer`, `encryptedBalanceOf`) are additive — they don't override [ERC-20](./eip-20.md) functions but extend them.

A token MAY implement both [ERC-20](./eip-20.md) and this interface simultaneously, where [ERC-20](./eip-20.md) functions operate on a separate "public balance" pool and encrypted functions operate on the "shielded balance" pool. The optional `IERC1680_Shielded` extension provides `shield`/`unshield` bridge functions to move tokens between pools.

## Backwards Compatibility

This interface is fully backwards-compatible with [ERC-20](./eip-20.md) for metadata queries. Tokens implementing this interface alongside [ERC-20](./eip-20.md) can participate in both the public and encrypted ecosystems.

Wallets that do not support this interface will display the token name and symbol but will show a balance of 0 (since `balanceOf` returns the public pool balance, which may be empty if all tokens are shielded).

This EIP REQUIRES [ERC-165](./eip-165.md) for interface detection, allowing protocols to query whether a token supports encrypted operations before attempting them.

## Reference Implementation

A reference implementation is provided in the STYX Protocol repository (`Valisthea/styx-erc-encrypted-token`):

- **StyxEncryptedToken.sol**: Full implementation with TFHE backend
- **StyxVerifier.sol**: On-chain ZK proof verifier (Halo2)
- **StyxReencryptor.sol**: Re-encryption proxy for balance queries

## Security Considerations

### FHE Ciphertext Malleability

FHE ciphertexts are malleable by design (homomorphic operations modify them). The ZK proof binds the ciphertext to a specific operation, preventing unauthorized modifications. Implementations MUST verify proofs before applying any ciphertext to state.

### Proof Replay

Each proof includes a nonce. Implementations MUST maintain a nonce registry and reject proofs with previously-used nonces. The nonce SHOULD be derived from the sender's transaction count to prevent cross-chain replay.

### Side-Channel Leakage

While balances and amounts are encrypted, the following metadata remains public:

- **Transaction timing**: When transfers occur.
- **Gas consumption**: Different proof sizes may leak information about amount magnitude.
- **Access patterns**: Who transacts with whom.

Implementations SHOULD use constant-size proofs and constant gas consumption for all transfer amounts. Uniform circuit compilation (all operations compile to the same gate count) achieves this property.

### Quantum Threat

Lattice-based FHE schemes (TFHE, BFV, BGV) are believed to be quantum-resistant. However, the ZK proof system may not be. Implementations SHOULD use quantum-resistant proof systems or plan migration paths.

### Key Management

The contract's FHE secret key is the most sensitive asset. If compromised, all balances are exposed. Implementations MUST use threshold key management (Shamir Secret Sharing with ≥ 5 custodians) or hardware security modules (HSMs).

### Share Inflation ([ERC-4626](./eip-4626.md) Analog)

For vault-like implementations that wrap encrypted tokens, the share inflation attack analog exists: an attacker could manipulate the encrypted share/asset ratio. Implementations MUST initialize vaults with a minimum deposit or use virtual shares to prevent first-depositor attacks on encrypted vaults.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
