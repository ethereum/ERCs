// SPDX-License-Identifier: CC0-1.0

pragma solidity 0.8.9;

import { IERC165 } from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

interface ISftRolesRegistry is IERC165 {
    struct RoleAssignment {
        address grantee;
        uint64 expirationDate;
        bool revocable;
        bytes data;
    }

    struct Commitment {
        address grantor;
        address tokenAddress;
        uint256 tokenId;
        uint256 tokenAmount;
    }

    /** Events **/

    /// @notice Emitted when tokens are committed (deposited or frozen).
    /// @param _grantor The owner of the SFTs.
    /// @param _commitmentId The identifier of the commitment created.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @param _tokenAmount The token amount.
    event TokensCommitted(
        address indexed _grantor,
        uint256 indexed _commitmentId,
        address indexed _tokenAddress,
        uint256 _tokenId,
        uint256 _tokenAmount
    );

    /// @notice Emitted when a role is granted.
    /// @param _commitmentId The commitment identifier.
    /// @param _role The role identifier.
    /// @param _grantee The recipient the role.
    /// @param _expirationDate The expiration date of the role.
    /// @param _revocable Whether the role is revocable or not.
    /// @param _data Any additional data about the role.
    event RoleGranted(
        uint256 indexed _commitmentId,
        bytes32 indexed _role,
        address indexed _grantee,
        uint64 _expirationDate,
        bool _revocable,
        bytes _data
    );

    /// @notice Emitted when a role is revoked.
    /// @param _commitmentId The commitment identifier.
    /// @param _role The role identifier.
    /// @param _grantee The recipient of the role revocation.
    event RoleRevoked(uint256 indexed _commitmentId, bytes32 indexed _role, address indexed _grantee);

    /// @notice Emitted when a user releases tokens from a commitment.
    /// @param _commitmentId The commitment identifier.
    event TokensReleased(uint256 indexed _commitmentId);

    /// @notice Emitted when a user is approved to manage roles on behalf of another user.
    /// @param _tokenAddress The token address.
    /// @param _operator The user approved to grant and revoke roles.
    /// @param _isApproved The approval status.
    event RoleApprovalForAll(address indexed _tokenAddress, address indexed _operator, bool _isApproved);

    /** External Functions **/

    /// @notice Commits tokens (deposits on a contract or freezes balance).
    /// @param _grantor The owner of the SFTs.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @param _tokenAmount The token amount.
    /// @return commitmentId_ The unique identifier of the commitment created.
    function commitTokens(
        address _grantor,
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _tokenAmount
    ) external returns (uint256 commitmentId_);

    /// @notice Grants a role to `_grantee`.
    /// @param _commitmentId The identifier of the commitment.
    /// @param _role The role identifier.
    /// @param _grantee The recipient the role.
    /// @param _expirationDate The expiration date of the role.
    /// @param _revocable Whether the role is revocable or not.
    /// @param _data Any additional data about the role.
    function grantRole(
        uint256 _commitmentId,
        bytes32 _role,
        address _grantee,
        uint64 _expirationDate,
        bool _revocable,
        bytes calldata _data
    ) external;

    /// @notice Revokes a role.
    /// @param _commitmentId The commitment identifier.
    /// @param _role The role identifier.
    /// @param _grantee The recipient of the role revocation.
    function revokeRole(uint256 _commitmentId, bytes32 _role, address _grantee) external;

    /// @notice Releases tokens back to grantor.
    /// @param _commitmentId The commitment identifier.
    function releaseTokens(uint256 _commitmentId) external;

    /// @notice Approves operator to grant and revoke roles on behalf of another user.
    /// @param _tokenAddress The token address.
    /// @param _operator The user approved to grant and revoke roles.
    /// @param _approved The approval status.
    function setRoleApprovalForAll(address _tokenAddress, address _operator, bool _approved) external;

    /** View Functions **/

    /// @notice Returns the owner of the commitment (grantor).
    /// @param _commitmentId The commitment identifier.
    /// @return grantor_ The commitment owner.
    function grantorOf(uint256 _commitmentId) external view returns (address grantor_);

    /// @notice Returns the address of the token committed.
    /// @param _commitmentId The commitment identifier.
    /// @return tokenAddress_ The token address.
    function tokenAddressOf(uint256 _commitmentId) external view returns (address tokenAddress_);

    /// @notice Returns the identifier of the token committed.
    /// @param _commitmentId The commitment identifier.
    /// @return tokenId_ The token identifier.
    function tokenIdOf(uint256 _commitmentId) external view returns (uint256 tokenId_);

    /// @notice Returns the amount of tokens committed.
    /// @param _commitmentId The commitment identifier.
    /// @return tokenAmount_ The token amount.
    function tokenAmountOf(uint256 _commitmentId) external view returns (uint256 tokenAmount_);

    /// @notice Returns the custom data of a role assignment.
    /// @param _commitmentId The commitment identifier.
    /// @param _role The role identifier.
    /// @param _grantee The recipient the role.
    /// @return data_ The custom data.
    function roleData(
        uint256 _commitmentId,
        bytes32 _role,
        address _grantee
    ) external view returns (bytes memory data_);

    /// @notice Returns the expiration date of a role assignment.
    /// @param _commitmentId The commitment identifier.
    /// @param _role The role identifier.
    /// @param _grantee The recipient the role.
    /// @return expirationDate_ The expiration date.
    function roleExpirationDate(
        uint256 _commitmentId,
        bytes32 _role,
        address _grantee
    ) external view returns (uint64 expirationDate_);

    /// @notice Returns the expiration date of a role assignment.
    /// @param _commitmentId The commitment identifier.
    /// @param _role The role identifier.
    /// @param _grantee The recipient the role.
    /// @return revocable_ Whether the role is revocable or not.
    function isRoleRevocable(
        uint256 _commitmentId,
        bytes32 _role,
        address _grantee
    ) external view returns (bool revocable_);

    /// @notice Checks if the grantor approved the operator for all SFTs.
    /// @param _tokenAddress The token address.
    /// @param _grantor The user that approved the operator.
    /// @param _operator The user that can grant and revoke roles.
    /// @return isApproved_ Whether the operator is approved or not.
    function isRoleApprovedForAll(
        address _tokenAddress,
        address _grantor,
        address _operator
    ) external view returns (bool isApproved_);
}
