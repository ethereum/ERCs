// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IFrameValidator} from "./IFrameValidator.sol";
import {IERC8286FrameAccount} from "./IERC8286FrameAccount.sol";

// IERC7579Module, and the IERC7579AccountConfig / IERC7579ModuleConfig surfaces inherited
// via IERC8286FrameAccount, are as defined in ERC-7579.

contract ERC8286FrameAccount is IERC8286FrameAccount {
    uint8 internal constant APPROVE_NONE = 0x0;
    uint8 internal constant APPROVE_PAYMENT = 0x1;
    uint8 internal constant APPROVE_EXECUTION = 0x2;
    uint8 internal constant APPROVE_SCOPE_MASK = 0x3;

    // EIP-8141 frame modes (FRAMEPARAM param 0x02).
    uint256 internal constant MODE_VERIFY = 1;
    uint256 internal constant MODE_SENDER = 2;

    // ERC-8286 assigns frame validators a new module type id, distinct from ERC-7579's
    // validateUserOp validators (type id 1). Value 11 is TBD in the draft.
    uint256 internal constant MODULE_TYPE_FRAME_VALIDATOR = 11;

    // SENDER-frame execution modes (see "SENDER Frame Execution Modes"). callType extends
    // ERC-7579's encoding with two new values; execType keeps its ERC-7579 meaning.
    bytes1 internal constant FRAME_CALLTYPE_SINGLE = 0x02; // exactly one SENDER frame
    bytes1 internal constant FRAME_CALLTYPE_BATCH = 0x03; // multiple SENDER frames
    bytes1 internal constant EXECTYPE_DEFAULT = 0x00; // revert-all (atomic batch)
    bytes1 internal constant EXECTYPE_TRY = 0x01; // try (not part of an atomic batch)

    mapping(address => bool) public isValidatorInstalled;

    modifier onlySelf() {
        require(msg.sender == address(this), "unauthorized");
        _;
    }

    function verify(bytes calldata data) external override returns (uint8 approvalMode) {
        uint256 frameIndex;
        uint256 frameMode;
        bytes32 sigHash;
        uint256 allowedRaw;
        assembly {
            frameIndex := verbatim_1i_1o(hex"b0", 0x0a) // TXPARAM currently executing frame index
            frameMode := verbatim_2i_1o(hex"b3", frameIndex, 0x02) // FRAMEPARAM(frameIndex, param=0x02 mode)
            sigHash := verbatim_1i_1o(hex"b0", 0x08) // TXPARAM canonical signing hash
            allowedRaw := verbatim_2i_1o(hex"b3", frameIndex, 0x06) // FRAMEPARAM(frameIndex, param=0x06 allowed scope)
        }

        // Only a VERIFY frame runs under STATICCALL protection and invalidates the whole
        // transaction on revert. A DEFAULT frame can also reach this code with
        // caller == ENTRY_POINT, so the mode MUST be checked rather than assumed.
        require(frameMode == MODE_VERIFY, "not a VERIFY frame");

        address validator = address(bytes20(data[0:20]));
        bytes calldata validatorData = data[20:];
        require(isValidatorInstalled[validator], "validator not installed");

        uint8 allowedScope = uint8(allowedRaw) & APPROVE_SCOPE_MASK;

        approvalMode =
            IFrameValidator(validator).validateFrame(sigHash, frameIndex, allowedScope, validatorData);

        // Mask to the frame's allowance; the account is the final authority.
        uint8 granted = approvalMode & allowedScope;

        // If execution is approved, every presented SENDER-frame mode must be supported;
        // otherwise clear the execution bit, leaving payment (if any) intact.
        if ((granted & APPROVE_EXECUTION) != 0 && !_senderFramesSupported()) {
            granted &= APPROVE_PAYMENT;
        }

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
        require(moduleTypeId == MODULE_TYPE_FRAME_VALIDATOR, "unsupported module type");
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
        require(moduleTypeId == MODULE_TYPE_FRAME_VALIDATOR, "unsupported module type");
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
        return moduleTypeId == MODULE_TYPE_FRAME_VALIDATOR && isValidatorInstalled[module];
    }

    function accountId() external pure override returns (string memory) {
        return "erc8286.reference-frame-account.0.1.0";
    }

    // This reference account is protocol-dispatched only: it defines no execute entrypoint,
    // so supportsExecutionMode declares which SENDER-frame shapes its validators are willing
    // to authorize, using the frame execution modes (callType 0x02 / 0x03). ERC-7579 execute
    // modes (callType 0x00 / 0x01) report unsupported because there is no execute to process
    // them.
    function supportsExecutionMode(bytes32 encodedMode) external pure override returns (bool) {
        return _supportsExecMode(encodedMode[0], encodedMode[1]);
    }

    function supportsModule(uint256 moduleTypeId) external pure override returns (bool) {
        return moduleTypeId == MODULE_TYPE_FRAME_VALIDATOR;
    }

    function _supportsExecMode(bytes1 callType, bytes1 execType) internal pure returns (bool) {
        bool okCall = callType == FRAME_CALLTYPE_SINGLE || callType == FRAME_CALLTYPE_BATCH;
        bool okExec = execType == EXECTYPE_DEFAULT || execType == EXECTYPE_TRY;
        return okCall && okExec;
    }

    // Checks every execution mode the transaction's SENDER frames present against
    // supportsExecutionMode. A transaction presents callType 0x02 if it has exactly one
    // SENDER frame and 0x03 otherwise; execType is 0x00 for a frame in an atomic batch and
    // 0x01 otherwise. Returns false if any presented mode is unsupported.
    function _senderFramesSupported() internal view returns (bool) {
        uint256 numFrames;
        assembly {
            numFrames := verbatim_1i_1o(hex"b0", 0x09) // TXPARAM len(frames)
        }

        uint256 senderCount;
        for (uint256 i = 0; i < numFrames; i++) {
            if (_frameMode(i) == MODE_SENDER) senderCount++;
        }
        if (senderCount == 0) return true; // no SENDER frames, no modes to check

        bytes1 callType = senderCount == 1 ? FRAME_CALLTYPE_SINGLE : FRAME_CALLTYPE_BATCH;

        for (uint256 i = 0; i < numFrames; i++) {
            if (_frameMode(i) != MODE_SENDER) continue;
            bytes1 execType = _inAtomicBatch(i) ? EXECTYPE_DEFAULT : EXECTYPE_TRY;
            if (!_supportsExecMode(callType, execType)) return false;
        }
        return true;
    }

    function _frameMode(uint256 i) internal view returns (uint256 mode) {
        assembly {
            mode := verbatim_2i_1o(hex"b3", i, 0x02) // FRAMEPARAM(frameIndex=i, param=0x02 mode)
        }
    }

    // A frame is part of an atomic batch if it carries the atomic-batch flag (a frame in
    // positions i..j-1 of a group), or if the preceding frame carries it (the terminating
    // frame j of the group).
    function _inAtomicBatch(uint256 i) internal view returns (bool) {
        uint256 flag;
        assembly {
            flag := verbatim_2i_1o(hex"b3", i, 0x07) // FRAMEPARAM(frameIndex=i, param=0x07 atomic_batch)
        }
        if (flag == 1) return true;
        if (i == 0) return false;
        uint256 prevFlag;
        assembly {
            prevFlag := verbatim_2i_1o(hex"b3", sub(i, 1), 0x07)
        }
        return prevFlag == 1;
    }
}
