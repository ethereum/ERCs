// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

// IERC7579Module is as defined in ERC-7579.

// An EIP-8141 frame validator (ERC-8286 module type id 11, TBD). A module MAY additionally
// be an ERC-7579 validator (type id 1) and serve both targets.

interface IFrameValidator is IERC7579Module {
    // Transaction context (sigHash, frameIndex, allowedScope, frame contents) MUST be read
    // via EIP-8141 introspection (TXPARAM / FRAMEPARAM / FRAMEDATA*), not account-supplied inputs.
    // Returns APPROVE_NONE (0x0) on failure; the account masks the result with allowedScope.
    // MAY revert for failures unrelated to the core validation logic (e.g. decoding errors).
    function validateFrame(bytes calldata data) external view returns (uint8 approvalMode);
}
