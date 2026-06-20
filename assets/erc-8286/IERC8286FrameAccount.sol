// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

// IERC7579AccountConfig and IERC7579ModuleConfig are as defined in ERC-7579.

interface IERC8286FrameAccount is IERC7579AccountConfig, IERC7579ModuleConfig {
    function verify(bytes calldata data) external returns (uint8 approvalMode);

    function supportsApprovalMode(uint8 approvalMode) external view returns (bool);
}
