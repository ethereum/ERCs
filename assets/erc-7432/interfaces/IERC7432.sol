// SPDX-License-Identifier: CC0-1.0

pragma solidity 0.8.9;

import { IERC165 } from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

/// @title ERC-7432 Non-Fungible Token Roles
/// @dev See https://eips.ethereum.org/EIPS/eip-7432
/// Note: the ERC-165 identifier for this interface is 0xd00ca5cf.
interface IERC7432 is IERC165 {
    struct Role {
        bytes32 roleId;
        address tokenAddress;
        uint256 tokenId;
        address recipient;
        uint64 expirationDate;
        bool revocable;
        bytes data;
    }

    /** Events **/

    /// @notice Emitted when an NFT is locked (deposited or frozen).
    /// @param _owner The owner of the NFT.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    event TokenLocked(address indexed _owner, address indexed _tokenAddress, uint256 _tokenId);

    /// @notice Emitted when a role is granted.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @param _roleId The role identifier.
    /// @param _owner The user assigning the role.
    /// @param _recipient The user receiving the role.
    /// @param _expirationDate The expiration date of the role.
    /// @param _revocable Whether the role is revocable or not.
    /// @param _data Any additional data about the role.
    event RoleGranted(
        address indexed _tokenAddress,
        uint256 indexed _tokenId,
        bytes32 indexed _roleId,
        address _owner,
        address _recipient,
        uint64 _expirationDate,
        bool _revocable,
        bytes _data
    );

    /// @notice Emitted when a role is revoked.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @param _roleId The role identifier.
    event RoleRevoked(address indexed _tokenAddress, uint256 indexed _tokenId, bytes32 indexed _roleId);

    /// @notice Emitted when an NFT is unlocked (withdrawn or unfrozen).
    /// @param _owner The original owner of the NFT.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    event TokenUnlocked(address indexed _owner, address indexed _tokenAddress, uint256 indexed _tokenId);

    /// @notice Emitted when a user is approved to manage roles on behalf of another user.
    /// @param _tokenAddress The token address.
    /// @param _operator The user approved to grant and revoke roles.
    /// @param _isApproved The approval status.
    event RoleApprovalForAll(address indexed _tokenAddress, address indexed _operator, bool indexed _isApproved);

    /** External Functions **/

    /// @notice Grants a role to a user.
    /// @dev Reverts if sender is not approved or the NFT owner.
    /// @param _role The role attributes.
    function grantRole(Role calldata _role) external;

    /// @notice Revokes a role from a user.
    /// @dev Reverts if sender is not approved or the original owner.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @param _roleId The role identifier.
    function revokeRole(address _tokenAddress, uint256 _tokenId, bytes32 _roleId) external;

    /// @notice Unlocks NFT (transfer back to original owner or unfreeze it).
    /// @dev Reverts if sender is not approved or the original owner.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    function unlockToken(address _tokenAddress, uint256 _tokenId) external;

    /// @notice Approves operator to grant and revoke roles on behalf of another user.
    /// @param _tokenAddress The token address.
    /// @param _operator The user approved to grant and revoke roles.
    /// @param _approved The approval status.
    function setRoleApprovalForAll(address _tokenAddress, address _operator, bool _approved) external;

    /** View Functions **/

    /// @notice Retrieves the owner of NFT.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @return owner_ The owner of the token.
    function ownerOf(address _tokenAddress, uint256 _tokenId) external view returns (address owner_);

    /// @notice Retrieves the recipient of an NFT role.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @param _roleId The role identifier.
    /// @return recipient_ The user that received the role.
    function recipientOf(
        address _tokenAddress,
        uint256 _tokenId,
        bytes32 _roleId
    ) external view returns (address recipient_);

    /// @notice Retrieves the custom data of a role assignment.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @param _roleId The role identifier.
    /// @return data_ The custom data of the role.
    function roleData(
        address _tokenAddress,
        uint256 _tokenId,
        bytes32 _roleId
    ) external view returns (bytes memory data_);

    /// @notice Retrieves the expiration date of a role assignment.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @param _roleId The role identifier.
    /// @return expirationDate_ The expiration date of the role.
    function roleExpirationDate(
        address _tokenAddress,
        uint256 _tokenId,
        bytes32 _roleId
    ) external view returns (uint64 expirationDate_);

    /// @notice Verifies if the role is revocable.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @param _roleId The role identifier.
    /// @return revocable_ Whether the role is revocable.
    function isRoleRevocable(
        address _tokenAddress,
        uint256 _tokenId,
        bytes32 _roleId
    ) external view returns (bool revocable_);

    /// @notice Verifies if the owner approved the operator.
    /// @param _tokenAddress The token address.
    /// @param _owner The user that approved the operator.
    /// @param _operator The user that can grant and revoke roles.
    /// @return Whether the operator is approved.
    function isRoleApprovedForAll(
        address _tokenAddress,
        address _owner,
        address _operator
    ) external view returns (bool);
}
