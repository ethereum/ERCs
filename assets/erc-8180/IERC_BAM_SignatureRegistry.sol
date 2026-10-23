// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IERC_BAM_SignatureRegistry
/// @notice Generic interface for signature scheme registries in Blob Authenticated Messaging
/// @dev Enables multiple signature schemes (ECDSA, BLS, STARK, Dilithium, etc.) with a unified
///      interface. Each scheme deploys its own registry implementing this interface.
/// Scheme-specific extensions (key rotation, revocation, etc.) are out of scope.
interface IERC_BAM_SignatureRegistry {
    /// @notice Emitted when a public key is registered.
    /// @param owner  The Ethereum address that owns this key.
    /// @param pubKey The public key bytes (format depends on scheme).
    /// @param index  The registry index assigned to this key.
    event KeyRegistered(address indexed owner, bytes pubKey, uint256 index);

    /// @notice Thrown when address already has a registered key.
    error AlreadyRegistered(address owner);

    /// @notice Thrown when address has no registered key.
    error NotRegistered(address owner);

    /// @notice Thrown when proof of possession is invalid.
    error InvalidProofOfPossession();

    /// @notice Thrown when public key format is invalid.
    error InvalidPublicKey();

    /// @notice Thrown when signature format is invalid.
    error InvalidSignature();

    /// @notice Thrown when verification fails.
    error VerificationFailed();

    /// @notice Returns the signature scheme identifier.
    /// @dev Scheme IDs:
    ///      0x01 = ECDSA-secp256k1
    ///      0x02 = BLS12-381
    ///      0x03 = STARK-Poseidon
    ///      0x04 = Dilithium
    ///      0x05-0xFF = Reserved for future schemes
    /// @return id The scheme identifier (1 byte).
    function schemeId() external pure returns (uint8 id);

    /// @notice Returns human-readable scheme name.
    /// @return name The scheme name (e.g., "BLS12-381").
    function schemeName() external pure returns (string memory name);

    /// @notice Returns the public key size for this scheme.
    /// @return size Size in bytes (0 if variable or recoverable from signature).
    function pubKeySize() external pure returns (uint256 size);

    /// @notice Returns the signature size for this scheme.
    /// @return size Size in bytes (0 if variable).
    function signatureSize() external pure returns (uint256 size);

    /// @notice Register a new public key with proof of possession.
    /// @dev Proof of possession format depends on the scheme.
    /// @param pubKey   The public key (format depends on scheme).
    /// @param popProof Proof of possession (prevents rogue key attacks).
    /// @return index   The assigned registry index.
    function register(bytes calldata pubKey, bytes calldata popProof) external returns (uint256 index);

    /// @notice Get the public key for an address.
    /// @param owner The Ethereum address.
    /// @return pubKey The registered public key (empty if not registered).
    function getKey(address owner) external view returns (bytes memory pubKey);

    /// @notice Check if an address has a registered key.
    /// @param owner The Ethereum address.
    /// @return registered True if the address has a registered key.
    function isRegistered(address owner) external view returns (bool registered);

    /// @notice Verify a signature against a public key.
    /// @param pubKey      The public key.
    /// @param messageHash The message hash (keccak256).
    /// @param signature   The signature bytes.
    /// @return valid      True if signature is valid.
    function verify(bytes calldata pubKey, bytes32 messageHash, bytes calldata signature)
        external
        view
        returns (bool valid);

    /// @notice Verify a signature using a registered key.
    /// @param owner       The owner whose registered key to use.
    /// @param messageHash The message hash.
    /// @param signature   The signature bytes.
    /// @return valid      True if signature is valid.
    function verifyWithRegisteredKey(address owner, bytes32 messageHash, bytes calldata signature)
        external
        view
        returns (bool valid);

    /// @notice Check if this scheme supports signature aggregation.
    /// @dev BLS supports aggregation; ECDSA does not.
    /// @return supported True if aggregation is supported.
    function supportsAggregation() external pure returns (bool supported);

    /// @notice Verify an aggregated signature (if supported).
    /// @dev Only callable if supportsAggregation() returns true.
    /// @param pubKeys             Array of public keys.
    /// @param messageHashes       Array of message hashes (same length as pubKeys).
    /// @param aggregatedSignature The aggregated signature.
    /// @return valid              True if aggregated signature is valid.
    function verifyAggregated(
        bytes[] calldata pubKeys,
        bytes32[] calldata messageHashes,
        bytes calldata aggregatedSignature
    ) external view returns (bool valid);
}
