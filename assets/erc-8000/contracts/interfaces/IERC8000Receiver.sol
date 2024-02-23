// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

/**
 * @title EIP-MFT token receiver interface
 * @dev Interface for a smart contract that wants to be informed by EIP-MFT contracts when
 *  receiving values from ANY addresses or EIP-3525 tokens.
 * Note: the EIP-165 identifier for this interface is 0xde7a9e53.
 */
interface IERC8000Receiver {
    /**
     * @notice Handle the receipt of an EIP-MFT token value.
     * @dev An EIP-MFT smart contract MUST check whether this function is implemented by the
     *  recipient contract, if the recipient contract implements this function, the EIP-MFT
     *  contract MUST call this function after a value transfer (i.e. `transferFrom(uint256,
     *  uint256,uint256,,uint256,bytes)`).
     *  MUST return 0xde7a9e53 (i.e. `bytes4(keccak256('onERC8000Received(address,uint256,uint256,uint256,uint256,bytes)'))`) if the transfer is accepted.
     *  MUST revert or return any value other than 0x009ce20b if the transfer is rejected.
     * @param _operator The address which triggered the transfer
     * @param _fromTokenId The token id to transfer value from
     * @param _toTokenId The token id to transfer value to
     * @param _slotIndex The slot index to transfer value to
     * @param _valueOrNftId Number of ERC20 or ID of ERC721
     * @param _data Additional data with no specified format
     * @return `bytes4(keccak256('onERC8000Received(address,uint256,uint256,uint256,uint256,bytes)'))`
     *  unless the transfer is rejected.
     */
    function onERC8000Received(address _operator, uint256 _fromTokenId, uint256 _toTokenId,uint256 _slotIndex, uint256 _valueOrNftId, bytes calldata _data) external returns (bytes4);

}