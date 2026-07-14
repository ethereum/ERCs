// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

// IERC7579AccountConfig and IERC7579ModuleConfig are as defined in ERC-7579.

interface IERC8286FrameAccount is IERC7579AccountConfig, IERC7579ModuleConfig {
    // Selects an installed frame validator (module type id 11, TBD), masks its approval mode
    // with the frame's allowed scope, clears the execution bit if the transaction's SENDER
    // frames present an unsupported execution mode (supportsExecutionMode), then calls APPROVE.
    // MUST revert if the executing frame's mode is not VERIFY.
    // MUST NOT call APPROVE if validation fails (leaving the mode at APPROVE_NONE).
    function verify(bytes calldata data) external returns (uint8 approvalMode);

    function supportsApprovalMode(uint8 approvalMode) external view returns (bool);
}
