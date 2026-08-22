// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  Token-Bound Executable Skills — core interface (KERNEL v4.3, frozen)
/// @notice Standalone extension interface; a compliant contract also implements
///         ERC-721 and ERC-165 and declares each capability separately.
interface ISkillToken {
    struct SkillBinding {
        bytes32 mdHash;      // SHA-256 digest of the plaintext primary Markdown document
        bytes32 packageHash; // SHA-256 digest of the encoded SkillRoot as published
        uint64  version;     // content version, starts at 1
    }

    event SkillUpdated(uint256 indexed tokenId, bytes32 mdHash, bytes32 packageHash, uint64 version);
    event SkillURIUpdated(uint256 indexed tokenId, string packageURI);
    event SkillUpdateAuthorityChanged(uint256 indexed tokenId,
                                      address indexed previousAuthority,
                                      address indexed newAuthority);
    event SkillFrozen(uint256 indexed tokenId);

    function skillOf(uint256 tokenId) external view returns (SkillBinding memory);
    function skillURI(uint256 tokenId) external view returns (string memory);
    function updateAuthorityOf(uint256 tokenId) external view returns (address);
    function isSkillFrozen(uint256 tokenId) external view returns (bool);

    function updateSkill(uint256 tokenId, bytes32 mdHash, bytes32 packageHash) external;
    function setSkillURI(uint256 tokenId, string calldata packageURI) external;
    function setUpdateAuthority(uint256 tokenId, address newAuthority) external;
    function freezeSkill(uint256 tokenId) external;
}
