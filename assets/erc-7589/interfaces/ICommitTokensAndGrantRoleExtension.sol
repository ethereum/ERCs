// SPDX-License-Identifier: CC0-1.0

pragma solidity 0.8.9;

interface ICommitTokensAndGrantRoleExtension {
    /// @notice Commits tokens and grant role in a single transaction.
    /// @param _grantor The owner of the SFTs.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @param _tokenAmount The token amount.
    /// @param _role The role identifier.
    /// @param _grantee The recipient the role.
    /// @param _expirationDate The expiration date of the role.
    /// @param _revocable Whether the role is revocable or not.
    /// @param _data Any additional data about the role.
    /// @return commitmentId_ The identifier of the commitment created.
    function commitTokensAndGrantRole(
        address _grantor,
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _tokenAmount,
        bytes32 _role,
        address _grantee,
        uint64 _expirationDate,
        bool _revocable,
        bytes calldata _data
    ) external returns (uint256 commitmentId_);
}
