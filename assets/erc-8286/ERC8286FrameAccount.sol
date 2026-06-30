// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IFrameValidator} from "./IFrameValidator.sol";
import {IERC8286FrameAccount} from "./IERC8286FrameAccount.sol";

// IERC7579Module, and the IERC7579AccountConfig / IERC7579ModuleConfig surfaces inherited
// via IERC8286FrameAccount, are as defined in ERC-7579.

contract ERC8286FrameAccount is IERC8286FrameAccount {
    uint8 internal constant APPROVE_NONE = 0x0;
    uint8 internal constant APPROVE_SCOPE_MASK = 0x3;

    uint256 internal constant MODULE_TYPE_VALIDATOR = 1;

    bytes1 internal constant CALLTYPE_SINGLE = 0x00;
    bytes1 internal constant CALLTYPE_BATCH = 0x01;
    bytes1 internal constant EXECTYPE_DEFAULT = 0x00;
    bytes1 internal constant EXECTYPE_TRY = 0x01;

    mapping(address => bool) public isValidatorInstalled;

    modifier onlySelf() {
        require(msg.sender == address(this), "unauthorized");
        _;
    }

    function verify(bytes calldata data) external override returns (uint8 approvalMode) {
        address validator = address(bytes20(data[0:20]));
        bytes calldata validatorData = data[20:];
        require(isValidatorInstalled[validator], "validator not installed");

        uint256 frameIndex;
        bytes32 sigHash;
        uint256 allowedRaw;
        assembly {
            frameIndex := verbatim_1i_1o(hex"b0", 0x0a) // TXPARAM currently executing frame index
            sigHash := verbatim_1i_1o(hex"b0", 0x08) // TXPARAM canonical signing hash
            allowedRaw := verbatim_2i_1o(hex"b3", frameIndex, 0x06) // FRAMEPARAM(frameIndex, param=0x06 allowed scope)
        }
        uint8 allowedScope = uint8(allowedRaw) & APPROVE_SCOPE_MASK;

        approvalMode =
            IFrameValidator(validator).validateFrame(sigHash, frameIndex, allowedScope, validatorData);

        // Clamp to the frame's allowance and the account's supported modes before approving.
        uint8 granted = approvalMode & allowedScope;
        require(granted != APPROVE_NONE, "validation failed");
        require(supportsApprovalMode(granted), "unsupported approval mode");

        assembly {
            verbatim_3i_0o(hex"aa", 0, 0, granted) // APPROVE: offset=0, length=0, scope=granted; exits the frame
        }
    }

    function supportsApprovalMode(uint8 approvalMode) public pure override returns (bool) {
        return approvalMode <= APPROVE_SCOPE_MASK;
    }

    function installModule(uint256 moduleTypeId, address module, bytes calldata initData)
        external
        override
        onlySelf
    {
        require(moduleTypeId == MODULE_TYPE_VALIDATOR, "unsupported module type");
        require(!isValidatorInstalled[module], "already installed");
        isValidatorInstalled[module] = true;
        IERC7579Module(module).onInstall(initData);
        emit ModuleInstalled(moduleTypeId, module);
    }

    function uninstallModule(uint256 moduleTypeId, address module, bytes calldata deInitData)
        external
        override
        onlySelf
    {
        require(moduleTypeId == MODULE_TYPE_VALIDATOR, "unsupported module type");
        require(isValidatorInstalled[module], "not installed");
        isValidatorInstalled[module] = false;
        IERC7579Module(module).onUninstall(deInitData);
        emit ModuleUninstalled(moduleTypeId, module);
    }

    function isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata)
        external
        view
        override
        returns (bool)
    {
        return moduleTypeId == MODULE_TYPE_VALIDATOR && isValidatorInstalled[module];
    }

    function accountId() external pure override returns (string memory) {
        return "erc8286.reference-frame-account.0.1.0";
    }

    function supportsExecutionMode(bytes32 encodedMode) external pure override returns (bool) {
        bytes1 callType = encodedMode[0];
        bytes1 execType = encodedMode[1];
        bool okCall = callType == CALLTYPE_SINGLE || callType == CALLTYPE_BATCH;
        bool okExec = execType == EXECTYPE_DEFAULT || execType == EXECTYPE_TRY;
        return okCall && okExec;
    }

    function supportsModule(uint256 moduleTypeId) external pure override returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }
}
