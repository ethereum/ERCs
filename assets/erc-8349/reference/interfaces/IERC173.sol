// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title ERC-173 Contract Ownership Standard
/// @notice Interface for the ERC-173 ownership standard.
/// @dev The ERC-165 interface identifier is `0x7f5828d0`.
/* is ERC165 */
interface IERC173 {
    /// @notice Emitted when contract ownership changes.
    /// @param previousOwner Previous owner.
    /// @param newOwner New owner.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Get the address of the owner
    /// @return owner_ The address of the owner.
    function owner() external view returns (address owner_);

    /// @notice Set the address of the new owner of the contract
    /// @dev Set _newOwner to address(0) to renounce any ownership.
    /// @param _newOwner The address of the new owner of the contract
    function transferOwnership(address _newOwner) external;
}