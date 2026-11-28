// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title ERC-XXXX — Cryptographic Proof Attachment Standard
/// @notice Minimal interface for attaching cryptographic proofs to arbitrary
///         on-chain assets through bounded DAG dependencies (B-hybrid).
/// @dev    Normative text: `EIP-XXXX.md` at the repository root.
///         ERC-165 id `0x7118c651` = XOR of the seven function selectors below
///         (return types ignored). Implementations MUST also support ERC-165
///         (`supportsInterface`). This file does **not** inherit IERC165: doing
///         so would fold `supportsInterface` into `type(IERCXXXX).interfaceId`
///         and break the fixed id.
interface IERCXXXX {
    /// @dev ERC-165 identifier of this interface: XOR of the 7 external selectors below.
    ///      IERCXXXX_INTERFACE_ID == 0x7118c651.
    /// @notice Emitted exactly once per successful `attachProof` call.
    /// @param assetId       The asset the proof is bound to.
    /// @param proofId       Unique identifier returned by `attachProof`.
    /// @param submitter     `msg.sender` of the `attachProof` call (or the meta-tx originator
    ///                      if the implementation supports trusted forwarders).
    /// @param metadataHash  `keccak256(metadata)` commitment persisted on-chain.
    /// @param metadata      Full attach-time payload (log-only; MUST equal the calldata).
    /// @param dependencies  Array of prerequisite `proofId` values, as supplied.
    event ProofAttached(
        bytes32 indexed assetId,
        bytes32 indexed proofId,
        address indexed submitter,
        bytes32 metadataHash,
        bytes metadata,
        bytes32[] dependencies
    );

    /// @notice Emitted whenever the flag bitfield of a proof changes.
    /// @param proofId  The proof whose flags changed.
    /// @param updater  Address that triggered the change.
    /// @param oldFlags Previous flag bitfield.
    /// @param newFlags New flag bitfield.
    event ProofFlagsUpdated(
        bytes32 indexed proofId, address indexed updater, uint256 oldFlags, uint256 newFlags
    );

    /// @notice Attach a cryptographic proof to an asset.
    /// @dev MUST revert if `dependencies.length` exceeds the implementation cap
    ///      (see EIP-XXXX "Constants"), if any dependency does not exist, or if
    ///      `metadata` exceeds the implementation maximum length.
    /// @param assetId      Universal asset identifier (see "assetId" in Definitions).
    /// @param proofHash    Commitment to the off-chain proof data (typically `keccak256`).
    /// @param metadata     Bounded additional data — pointer or inline payload.
    ///                     Capped by `MAX_METADATA_LEN()` (MUST be `>= 256` and `<= 65535`).
    /// @param dependencies Array of prerequisite `proofId` values forming the DAG edge set.
    /// @return proofId     Unique identifier for the newly attached proof.
    function attachProof(
        bytes32 assetId,
        bytes32 proofHash,
        bytes calldata metadata,
        bytes32[] calldata dependencies
    ) external returns (bytes32 proofId);

    /// @notice Update the flag bitfield of an existing proof.
    /// @dev MUST revert if `proofId` does not exist. Authorization rules over which
    ///      bits a given caller may set are specified in EIP-XXXX "Authorization".
    /// @param proofId The proof to update.
    /// @param flags   New flag bitfield (replaces the previous value).
    function setProofFlags(bytes32 proofId, uint256 flags) external;

    /// @notice Retrieve a proof (B-hybrid). MUST revert if `proofId` does not exist.
    /// @dev Full `metadata` bytes are NOT returned here — reconstruct from `ProofAttached`
    ///      logs (or an off-chain store keyed by `metadataHash`). `metadataHead` length is
    ///      word-aligned: `32 * floor(min(METADATA_HEAD_LEN, metadataLen) / 32)` (0, 32, 64, or 96).
    function getProof(bytes32 proofId)
        external
        view
        returns (
            bytes32 assetId,
            address submitter,
            bytes32 proofHash,
            bytes32 metadataHash,
            bytes memory metadataHead,
            uint16 metadataLen,
            uint64 timestamp,
            bytes32[] memory dependencies,
            uint256 flags
        );

    /// @notice Paginated list of `proofId` values attached to `assetId`, in insertion order.
    /// @dev If `offset >= total`, `proofIds` MUST be empty and `total` MUST still be returned.
    ///      Implementations MUST cap the returned slice at `limit`.
    function getAssetProofs(bytes32 assetId, uint256 offset, uint256 limit)
        external
        view
        returns (bytes32[] memory proofIds, uint256 total);

    /// @notice Returns `true` iff `proofId` has been successfully attached.
    /// @dev This standard does not define deletion or garbage-collection of proofs.
    function proofExists(bytes32 proofId) external view returns (bool);

    /// @notice Total number of proofs ever attached to `assetId`.
    function getProofCount(bytes32 assetId) external view returns (uint256);

    /// @notice Per-implementation upper bound on `metadata.length` accepted by `attachProof`.
    /// @dev MUST return a value `>= 256` and `<= 65535`. RECOMMENDED `>= 16384` for
    ///      implementations intended to host inline state / MPT / ZK proofs rather
    ///      than only off-chain pointers.
    function MAX_METADATA_LEN() external view returns (uint256);
}
