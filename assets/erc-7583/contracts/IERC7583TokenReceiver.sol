// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Note: the ERC-165 identifier for this interface is 0xee1c3373.
interface IERC7583TokenReceiver {
    /// @notice Handle the receipt of an inscription
    /// @dev The ERC7583 smart contract calls this function on the recipient
    ///  after a `transfer`. This function MAY throw to revert and reject the
    ///  transfer. Return of other than the magic value MUST result in the
    ///  transaction being reverted.
    ///  Note: the contract address is always the message sender.
    /// @param _operator The address which called `safeTransferFrom` function
    /// @param _from The address which previously owned the token
    /// @param _tokenId The insctiption identifier which is being transferred
    /// @return `bytes4(keccak256("onERC7583Received(address,address,uint256)"))`
    ///  unless throwing
    function onERC7583Received(address _operator, address _from, uint256 _tokenId) external returns(bytes4);
}