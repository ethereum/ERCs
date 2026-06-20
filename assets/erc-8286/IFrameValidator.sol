// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

// IERC7579Module is as defined in ERC-7579.

interface IFrameValidator is IERC7579Module {
    // sigHash = TXPARAM(0x08), frameIndex = TXPARAM(0x0A), allowedScope = FRAMEPARAM(frameIndex, 0x06).
    // Returns APPROVE_NONE (0x0) on failure; the account clamps the result to allowedScope.
    function validateFrame(
        bytes32 sigHash,
        uint256 frameIndex,
        uint8 allowedScope,
        bytes calldata data
    ) external view returns (uint8 approvalMode);
}
