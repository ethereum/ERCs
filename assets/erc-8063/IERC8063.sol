// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @title IERC8063 — Minimal interface for onchain groups
/// @notice A group is a container with an owner, members, and shared resources
interface IERC8063 is IERC165 {
    /// @dev Emitted when a new group is created
    event GroupCreated(uint256 indexed groupId, address indexed owner, string name, string metadataURI);

    /// @dev Emitted when the owner invites an account
    event MemberInvited(uint256 indexed groupId, address indexed inviter, address indexed invitee);

    /// @dev Emitted when an invited account accepts and becomes a member
    event MemberJoined(uint256 indexed groupId, address indexed account);

    /// @dev Emitted when a member is removed (cannot remove the owner)
    event MemberRemoved(uint256 indexed groupId, address indexed account, address indexed by);

    /// @notice Create a new group; caller becomes owner and initial member
    /// @param name Optional human-readable group name
    /// @param metadataURI Optional offchain metadata (e.g., JSON document)
    /// @return groupId Newly created group identifier
    function createGroup(string calldata name, string calldata metadataURI) external returns (uint256 groupId);

    /// @notice Returns the owner of a group
    function groupOwner(uint256 groupId) external view returns (address);

    /// @notice Returns the human-readable name of the group (may be empty)
    function groupName(uint256 groupId) external view returns (string memory);

    /// @notice Returns true if `account` is a member of the group
    function isMember(uint256 groupId, address account) external view returns (bool);

    /// @notice Returns current number of members (including owner)
    function getMemberCount(uint256 groupId) external view returns (uint256);

    /// @notice Owner invites an account to join the group
    function inviteMember(uint256 groupId, address account) external;

    /// @notice Invitee accepts an outstanding invite and becomes a member
    function acceptInvite(uint256 groupId) external;

    /// @notice Owner removes a member (owner cannot be removed)
    function removeMember(uint256 groupId, address account) external;
}
