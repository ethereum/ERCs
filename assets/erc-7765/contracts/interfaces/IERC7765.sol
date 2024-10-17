// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

/// @title ERC-7765 Privileged Non-Fungible Tokens Tied To Real World Assets
/// @dev See https://eips.ethereum.org/EIPS/eip-7765
interface IERC7765 /* is IERC721, IERC165 */ { 
    /// @notice This event emitted when a specific privilege of a token is successfully exercised.
    /// @param _operator  the address who exercised the privilege.
    /// @param _to  the address to benefit from the privilege.
    /// @param _tokenId  the NFT tokenID.
    /// @param _privilegeId  the ID of the privileges.
    event PrivilegeExercised(
        address indexed _operator, address indexed _to, uint256 indexed _tokenId, uint256 _privilegeId
    );

    /// @notice This function exercise a specific privilege of a token.
    /// @dev Throws if `_privilegeId` is not a valid privilegeId.
    /// @param _to  the address to benefit from the privilege.
    /// @param _tokenId  the NFT tokenID.
    /// @param _privilegeId  the ID of the privileges.
    /// @param _data  extra data passed in for extra message or future extension.
    function exercisePrivilege(address _to, uint256 _tokenId, uint256 _privilegeId, bytes calldata _data) external;

    /// @notice This function is to check whether a specific privilege of a token can be exercised.
    /// @dev Throws if `_privilegeId` is not a valid privilegeId.
    /// @param _to  the address to benefit from the privilege.
    /// @param _tokenId  the NFT tokenID.
    /// @param _privilegeId  the ID of the privileges.
    function isExercisable(address _to, uint256 _tokenId, uint256 _privilegeId)
        external
        view
        returns (bool _exercisable);

    /// @notice This function is to check whether a specific privilege of a token has been exercised.
    /// @dev Throws if `_privilegeId` is not a valid privilegeId.
    /// @param _to  the address to benefit from the privilege.
    /// @param _tokenId  the NFT tokenID.
    /// @param _privilegeId  the ID of the privileges.
    function isExercised(address _to, uint256 _tokenId, uint256 _privilegeId) external view returns (bool _exercised);

    /// @notice This function is to list all privilegeIds of a token.
    /// @param _tokenId  the NFT tokenID.
    function getPrivilegeIds(uint256 _tokenId) external view returns (uint256[] memory privilegeIds);
}
