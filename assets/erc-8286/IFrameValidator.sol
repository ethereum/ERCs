// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

// IERC7579Module is as defined in ERC-7579.

// An EIP-8141 frame validator (ERC-8286 module type id 11, TBD). A module MAY additionally
// be an ERC-7579 validator (type id 1) and serve both targets.

interface IFrameValidator is IERC7579Module {
    // sigHash = TXPARAM(0x08), frameIndex = TXPARAM(0x0A), allowedScope = FRAMEPARAM(frameIndex, 0x06).
    // Returns APPROVE_NONE (0x0) on failure; the account masks the result with allowedScope.
    // MAY revert for failures unrelated to the core validation logic (e.g. decoding errors).
    function validateFrame(
        bytes32 sigHash,
        uint256 frameIndex,
        uint8 allowedScope,
        bytes calldata data
    ) external view returns (uint8 approvalMode);
}
