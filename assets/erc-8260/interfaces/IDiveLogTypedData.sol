// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title ERC-8260 EIP-712 typed data for dive attestations.
/// @notice Domain: name "DiveLog", version "2", chainId, verifyingContract.
library DiveLogTypedData {
    bytes32 internal constant DOMAIN_NAME = keccak256("DiveLog");
    bytes32 internal constant DOMAIN_VERSION = keccak256("2");

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 internal constant ATTESTATION_TYPEHASH = keccak256(
        "Attestation(uint256 diveId,bytes32 contentHash,address verifyingContract,uint256 nonce)"
    );

    function domainSeparator(uint256 chainId, address verifyingContract) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, DOMAIN_NAME, DOMAIN_VERSION, chainId, verifyingContract)
        );
    }

    /// @notice Digest the attester signs: `\x19\x01 ‖ domainSeparator ‖ structHash`.
    /// @dev `contentHash` is the stored SHA-256 of the exact attested UDDF bytes,
    ///      carried as a bytes32 field. Never keccak256 the UDDF file itself.
    function attestationDigest(
        uint256 diveId,
        bytes32 contentHash,
        address verifyingContract,
        uint256 chainId,
        uint256 nonce
    ) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(ATTESTATION_TYPEHASH, diveId, contentHash, verifyingContract, nonce));

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(chainId, verifyingContract), structHash));
    }
}
