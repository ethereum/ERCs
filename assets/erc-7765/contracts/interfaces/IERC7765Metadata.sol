// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

/// @title ERC-7765 Privileged Non-Fungible Tokens Tied To Real World Assets, optional metadata extension
/// @dev See https://eips.ethereum.org/EIPS/eip-7765
interface IERC7765Metadata /* is IERC7765 */ { 
    /// @notice A distinct Uniform Resource Identifier (URI) for a given privilegeId.
    /// @dev Throws if `_privilegeId` is not a valid privilegeId. URIs are defined in RFC
    ///  3986. The URI may point to a JSON file that conforms to the "ERC-7765
    ///  Metadata JSON Schema".
    function privilegeURI(uint256 _privilegeId) external view returns (string memory);
}
