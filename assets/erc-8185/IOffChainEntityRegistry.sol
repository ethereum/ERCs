// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IOffChainEntityRegistry
/// @notice Maps off-chain entity identifiers to Ethereum addresses.
interface IOffChainEntityRegistry {
    event Claimed(bytes32 indexed id, string namespace, string canonicalString, address indexed owner, address verifier);
    event Revoked(bytes32 indexed id, string namespace, string canonicalString, address indexed previousOwner);
    event Linked(bytes32 indexed aliasId, bytes32 indexed primaryId);
    event Unlinked(bytes32 indexed aliasId, bytes32 indexed primaryId);
    event VerifierUpdated(bytes32 indexed namespaceKey, string namespace, address verifier);

    function toId(string calldata namespace, string calldata canonicalString) external pure returns (bytes32);
    function canonicalOf(bytes32 id) external view returns (bytes32);
    function ownerOf(bytes32 id) external view returns (address);
    function verifierOf(string calldata namespace) external view returns (address);

    function claim(string calldata namespace, string calldata canonicalString, bytes calldata proof) external;
    function revoke(string calldata namespace, string calldata canonicalString) external;

    function linkIds(bytes32 primaryId, bytes32[] calldata aliasIds) external;
    function unlinkIds(bytes32 primaryId, bytes32[] calldata aliasIds) external;

    function setVerifier(string calldata namespace, address verifier) external;
}
