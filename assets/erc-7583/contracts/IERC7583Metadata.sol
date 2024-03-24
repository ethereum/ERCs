// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC7583.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC7583 standard.
 */
interface IERC7583Metadata is IERC7583 {
	/**
     * @dev Embed the inscription data corresponding to the insId into Ethereum through events.
     */
    event Inscribe(uint256 indexed id, bytes data);
    
	/**
     * @dev Returns the name of the inscription token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the inscription token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the inscription token.
     */
    function decimals() external view returns (uint8);
}