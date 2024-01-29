// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

struct Execution {
    address target;
    uint256 value;
    bytes callData;
}

struct UserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;
    bytes signature;
}

interface IERC7579Account {
    error UnsupportedModuleType(uint256 moduleType);
    // Error thrown when an execution with an unsupported CallType was made
    error UnsupportedCallType(bytes1 callType);
    // Error thrown when an execution with an unsupported ExecType was made
    error UnsupportedExecType(bytes1 execType);

    error AccountInitializationFailed();

    event ModuleInstalled(uint256 moduleTypeId, address module);
    event ModuleUninstalled(uint256 moduleTypeId, address module);

    /**
     * @dev Executes a transaction on behalf of the account.
     *         This function is intended to be called by ERC-4337 EntryPoint.sol
     * @dev Ensure adequate authorization control: i.e. onlyEntryPointOrSelf
     *
     * @dev MSA MUST implement this function signature.
     * If a mode is requested that is not supported by the Account, it MUST revert
     * @param mode The encoded execution mode of the transaction. See ModeLib.sol for details
     * @param executionCalldata The return data of the executed contract call.
     */
    function execute(bytes32 mode, bytes calldata executionCalldata) external payable;

    /**
     * @dev Executes a transaction on behalf of the account.
     *         This function is intended to be called by Executor Modules
     * @dev Ensure adequate authorization control: i.e. onlyExecutorModule
     *
     * @dev MSA MUST implement this function signature.
     * If a mode is requested that is not supported by the Account, it MUST revert
     * @param mode The encoded execution mode of the transaction. See ModeLib.sol for details
     * @param executionCalldata The return data of the executed contract call.
     */
    function executeFromExecutor(bytes32 mode, bytes calldata executionCalldata) external payable;

    /**
     * @dev ERC-4337 executeUserOp according to ERC-4337 v0.7
     *         This function is intended to be called by ERC-4337 EntryPoint.sol
     * @dev Ensure adequate authorization control: i.e. onlyEntryPointOrSelf
     *      The implementation of the function is OPTIONAL
     *
     * @param userOp PackedUserOperation struct (see ERC-4337 v0.7+)
     */
    function executeUserOp(UserOperation calldata userOp) external payable;

    /**
     * @dev ERC-4337 validateUserOp according to ERC-4337 v0.7
     *         This function is intended to be called by ERC-4337 EntryPoint.sol
     * this validation function should decode / sload the validator module to validate the userOp
     * and call it.
     *
     * @dev MSA MUST implement this function signature.
     * @param userOp PackedUserOperation struct (see ERC-4337 v0.7+)
     */
    function validateUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        payable
        returns (uint256 validSignature);

    /**
     * @dev installs a Module of a certain type on the smart account
     * @dev Implement Authorization control of your chosing
     * @param moduleType the module type ID according the ERC-7579 spec
     * @param module the module address
     * @param initData arbitrary data that may be required on the module during `onInstall`
     * initialization.
     */
    function installModule(uint256 moduleType, address module, bytes calldata initData) external payable;

    /**
     * @dev uninstalls a Module of a certain type on the smart account
     * @dev Implement Authorization control of your chosing
     * @param moduleType the module type ID according the ERC-7579 spec
     * @param module the module address
     * @param deInitData arbitrary data that may be required on the module during `onInstall`
     * initialization.
     */
    function uninstallModule(uint256 moduleType, address module, bytes calldata deInitData) external payable;

    /**
     * Function to check if the account supports a certain CallType or ExecType (see ModeLib.sol)
     * @param encodedMode the encoded mode
     */
    function supportsAccountMode(bytes32 encodedMode) external view returns (bool);

    /**
     * Function to check if the account supports installation of a certain module type Id
     * @param moduleTypeId the module type ID according the ERC-7579 spec
     */
    function supportsModule(uint256 moduleTypeId) external view returns (bool);

    /**
     * Function to check if the account has a certain module installed
     * @param moduleType the module type ID according the ERC-7579 spec
     *      Note: keep in mind that some contracts can be multiple module types at the same time. It
     *            thus may be necessary to query multiple module types
     * @param module the module address
     * @param additionalContext additional context data that the smart account may interpret to
     *                          identifiy conditions under which the module is installed.
     *                          usually this is not necessary, but for some special hooks that
     *                          are stored in mappings, this param might be needed
     */
    function isModuleInstalled(uint256 moduleType, address module, bytes calldata additionalContext)
        external
        view
        returns (bool);

    /**
     * @dev Returns the account id of the smart account
     * @return accountImplementationId the account id of the smart account
     * the accountId should be structured like so:
     *        "vendorname.accountname.semver"
     */
    function accountId() external view returns (string memory accountImplementationId);

    /**
     * @dev initialized the account. Function might be called directly, or by a Factory
     * @param data. encoded data that can be used during the initialization phase
     */
    function initializeAccount(bytes calldata data) external payable;
}
