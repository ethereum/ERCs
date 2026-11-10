// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title AIFPCalls
/// @notice The one low-level call the reference contracts use to query a contract whose behaviour they do
///         not rely on (a leaf verifier, a subject set, the composite verifier seen from the registry): a
///         `staticcall` whose return data is never copied beyond its first word.
library AIFPCalls {
    /// @dev Calls `target` with `data`, forwarding `gasLimit` gas (the EVM caps the amount at 63/64 of the gas
    ///      left, see `hasGasFor`). Returns whether the call succeeded, the size of its return data and the
    ///      first 32 bytes of that data, zero-padded on the right when the data is shorter. Nothing beyond
    ///      those 32 bytes is copied, so the cost of this function does not grow with the amount of data the
    ///      callee returns.
    function staticcallWord(address target, bytes memory data, uint256 gasLimit)
        internal
        view
        returns (bool success, uint256 size, bytes32 word)
    {
        assembly ("memory-safe") {
            success := staticcall(gasLimit, target, add(data, 0x20), mload(data), 0, 0)
            size := returndatasize()
            let n := size
            if gt(n, 0x20) { n := 0x20 }
            mstore(0, 0)
            returndatacopy(0, 0, n)
            word := mload(0)
        }
    }

    /// @dev True when a call made right after this check can be given `gasLimit` gas in full. A call receives
    ///      at most 63/64 of the gas left once its own cost is paid (EIP-150), so the caller needs
    ///      `gasLimit * 64 / 63` plus that cost. `margin` has to cover the cost of the call itself and the few
    ///      opcodes between this check and the call: the calldata is already in memory and no return area is
    ///      reserved, so the call costs its account access only - 100 gas for an account already accessed in
    ///      the transaction, 2,600 for a cold one, and 2,600 more when the account is an EIP-7702 delegated
    ///      account whose delegate is cold.
    function hasGasFor(uint256 gasLimit, uint256 margin) internal view returns (bool) {
        return gasleft() >= gasLimit + gasLimit / 63 + 1 + margin;
    }
}
