// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IERC7007.sol";

/**
 * @title ERC7007 Token Standard, optional updatable extension
 */
interface IERC7007Updatable is IERC7007 {
    /**
     * @dev Update the `aigcData` of `prompt`.
     */
    function update(
        bytes calldata prompt,
        bytes calldata aigcData
    ) external;

    /**
     * @dev Emitted when `tokenId` token is updated.
     */
    event Update(
        uint256 indexed tokenId,
        bytes indexed prompt,
        bytes indexed aigcData
    );
}
