// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title ERC-7635 Semi-Fungible Token Standard
 * Note: the ERC-165 identifier for this interface is 0x9fa8825f.
 */
interface IERC7635 is IERC721 {
    /**
     * @dev MUST emit when value of a token is transferred to another token with the same slot,
     *  including zero value transfers (_value == 0) as well as transfers when tokens are created
     *  (`_fromTokenId` == 0) or destroyed (`_toTokenId` == 0).
     * @param _fromTokenId The token id to transfer value from
     * @param _toTokenId The token id to transfer value to
     * @param _slotIndex The slot index to transfer value to
     * @param _value The transferred value
     */
    event TransferValue(uint256 indexed _fromTokenId, uint256 indexed _toTokenId, uint256 indexed _slotIndex, uint256 _value);

    /**
     * @dev MUST emits when the approval value of a token is set or changed.
     * @param _tokenId The token to approve
     * @param _owner The owner address of this MFT
     * @param _slotIndex The slot to approve
     * @param _operator The operator to approve for
     * @param _value The maximum value that `_operator` is allowed to manage
     */
    event ApprovalValue(uint256 indexed _tokenId, address indexed _owner, uint256 indexed _slotIndex, address _operator, uint256 _value);

    /**
     * @notice Get the number of decimals the slot
     * @return The number of decimals for value
     */
    function slotDecimals(uint256 _slotIndex) external view returns (uint8);

    /**
     * @notice Get the balance of slot.
     * @param _tokenId The token for which to query the balance
     * @param _slotIndex The slot for which to query the balance
     * @return The value of `_slotIndex`
     */
    function balanceOf(uint256 _tokenId, uint256 _slotIndex) external view returns (uint256);

    /**
    * @dev Gets the number of NFTS in the slot
    * @param tokenId_ MFT ID
    * @param slotIndex_ Slot index
    */
    function nftBalanceOf(uint256 tokenId_, uint256 slotIndex_) external view returns (uint256[] memory);

    /**
     * @notice Allow an operator to manage the value of a token, up to the `_value` amount.
     * @dev MUST revert unless caller is the current owner, an authorized operator, or the approved
     *  address for `_tokenId`.
     *  MUST emit ApprovalValue event.
     * @param _tokenId The token to approve
     * @param _slotIndex The slot to approve
     * @param _operator The operator to be approved
     * @param _value The maximum value of `_toTokenId` that `_operator` is allowed to manage
     */
    function approve(
        uint256 _tokenId,
        uint256 _slotIndex,
        address _operator,
        uint256 _value
    ) external payable;

    /**
     * @notice Get the maximum value of a token that an operator is allowed to manage.
     * @param _tokenId The token for which to query the allowance
     * @param _slotIndex The slot for which to query the allowance
     * @param _operator The address of an operator
     * @return The current approval value of `_tokenId` that `_operator` is allowed to manage
     */
    function allowance(uint256 _tokenId, uint256 _slotIndex, address _operator) external view returns (uint256);


    /**
    * @dev The MFT transfers slot value to other MFTS
    * @param _fromTokenId MFT ID of the transaction initiator
    * @param _toTokenId MSFT ID of the receiver
    * @param _slotIndex Slot index
    * @param _valueOrNftId Number of ERC20 or ID of ERC721
    */
    function transferFrom(
        uint256 _fromTokenId,
        uint256 _toTokenId,
        uint256 _slotIndex,
        uint256 _valueOrNftId
    ) external payable;

    /**
    * @dev Slot transfers to EOA wallet address
    * @param _fromTokenId  MFT ID of the transaction initiator
    * @param _toAddress The recipient's wallet address
    * @param _slotIndex Slot index
    * @param _valueOrNftId Number of ERC20 or ID of ERC721
    */
    function transferFrom(
        uint256 _fromTokenId,
        address _toAddress,
        uint256 _slotIndex,
        uint256 _valueOrNftId
    ) external payable;

}
