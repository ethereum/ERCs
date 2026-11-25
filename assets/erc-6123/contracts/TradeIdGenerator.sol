// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @notice Generates decimal trade identifiers unique within this contract instance.
 * @dev The counter is never reset. Checked increment reverts on exhaustion rather
 *      than reusing an identifier. Reverted transactions do not consume identifiers.
 */
abstract contract TradeIdGenerator {
    uint256 private _tradeIdCounter;

    function _newTradeId() internal returns (string memory) {
        uint256 value = ++_tradeIdCounter;
        uint256 remaining = value;
        uint256 digits;
        do {
            ++digits;
            remaining /= 10;
        } while (remaining != 0);

        bytes memory identifier = new bytes(digits);
        while (value != 0) {
            identifier[--digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(identifier);
    }
}
