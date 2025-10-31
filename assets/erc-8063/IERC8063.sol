// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @title IERC8063 — Minimal interface for onchain groups
/// @notice A group is a contract with an owner and members
interface IERC8063 is IERC165 {
    /// @dev Emitted when the owner invites an account
    event MemberInvited(address indexed inviter, address indexed invitee);

    /// @dev Emitted when an invited account accepts and becomes a member
    event MemberJoined(address indexed account);

    /// @dev Emitted when a member is removed (cannot remove the owner)
    event MemberRemoved(address indexed account, address indexed by);

    /// @dev Emitted when a member transfers their membership to another address
    event MembershipTransferred(address indexed from, address indexed to);

    /// @notice Returns the owner of the group
    function owner() external view returns (address);

    /// @notice Returns the human-readable name of the group (may be empty)
    function name() external view returns (string memory);

    /// @notice Returns true if `account` is a member of the group
    function isMember(address account) external view returns (bool);

    /// @notice Returns current number of members (including owner)
    function getMemberCount() external view returns (uint256);

    /// @notice Owner invites an account to join the group
    function inviteMember(address account) external;

    /// @notice Invitee accepts an outstanding invite and becomes a member
    function acceptInvite() external;

    /// @notice Owner removes a member (owner cannot be removed)
    function removeMember(address account) external;

    /// @notice Transfer membership to another address (caller loses membership)
    /// @param to Address to receive membership (must not already be a member)
    function transferMembership(address to) external;
}
