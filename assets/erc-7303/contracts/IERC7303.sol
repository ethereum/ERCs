// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.9;

interface IERC7303 {
    /// @notice Emitted when an ERC-721 control token is associated with `role`.
    event ERC721ControlTokenAdded(bytes32 indexed role, address indexed contractId);

    /// @notice Emitted when an ERC-1155 control token is associated with `role`.
    event ERC1155ControlTokenAdded(bytes32 indexed role, address indexed contractId, uint256 indexed typeId);

    /// @notice Check whether `account` currently holds `role`, per the
    ///         balance check described in this ERC.
    function hasRole(bytes32 role, address account) external view returns (bool);

    /// @notice Enumerate the ERC-721 control tokens associated with `role`.
    function getERC721ControlTokens(bytes32 role) external view returns (address[] memory contractIds);

    /// @notice Enumerate the ERC-1155 control tokens associated with `role`.
    function getERC1155ControlTokens(bytes32 role) external view returns (address[] memory contractIds, uint256[] memory typeIds);
}
