// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  Token-Bound Task Tenders — core binding interface (TASK-KERNEL v1.0)
/// @notice Standalone extension interface; a compliant contract also implements
///         ERC-721, ERC-165, and ITaskTender, declaring each capability separately.
///         Deliberately isomorphic to ISkillToken (Token-Bound Executable Skills):
///         same three-field binding, same identity/transport split, same
///         independent publication right, same irreversible freeze.
interface ITaskToken {
    struct TaskBinding {
        bytes32 tdHash;   // SHA-256 digest of the plaintext primary Markdown task document
        bytes32 taskHash; // SHA-256 digest of the encoded TaskRoot as published
        uint64  version;  // content version, starts at 1
    }

    event TaskUpdated(uint256 indexed tokenId, bytes32 tdHash, bytes32 taskHash, uint64 version);
    event TaskURIUpdated(uint256 indexed tokenId, string taskURI);
    event TaskUpdateAuthorityChanged(uint256 indexed tokenId,
                                     address indexed previousAuthority,
                                     address indexed newAuthority);
    event TaskFrozen(uint256 indexed tokenId);

    function taskOf(uint256 tokenId) external view returns (TaskBinding memory);
    function taskURI(uint256 tokenId) external view returns (string memory);
    function updateAuthorityOf(uint256 tokenId) external view returns (address);
    function isTaskFrozen(uint256 tokenId) external view returns (bool);

    function updateTask(uint256 tokenId, bytes32 tdHash, bytes32 taskHash) external;
    function setTaskURI(uint256 tokenId, string calldata taskURI) external;
    function setUpdateAuthority(uint256 tokenId, address newAuthority) external;
    function freezeTask(uint256 tokenId) external;
}
