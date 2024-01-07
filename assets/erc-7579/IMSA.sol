// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @dev Execution Interface of the minimal Modular Smart Account standard
 */
interface IExecution {
    error Unsupported();

    struct Execution {
        address target;
        uint256 value;
        bytes callData;
    }

    /**
     *
     * @dev Executes a transaction on behalf of the account.
     *         This function is intended to be called by ERC-4337 EntryPoint.sol
     *
     * @dev MSA MUST implement this function signature. If functionality should not be supported, revert "Unsupported"!
     * @dev This function MUST revert if the call fails.
     * @param target The address of the contract to call.
     * @param value The value in wei to be sent to the contract.
     * @param callData The call data to be sent to the contract.
     * @return result The return data of the executed contract call.
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata callData
    )
        external
        payable
        returns (bytes memory result);

    /**
     *
     * @dev Executes a batched transaction via 'call' on behalf of the account.
     *         This function is intended to be called by ERC-4337 EntryPoint.sol
     *
     * @dev This function MUST revert if the call fails.
     * @dev MSA MUST implement this function signature. If functionality should not be supported, revert "Unsupported"!
     * @param executions An array of struct Execution (address target, uint value, bytes callData)
     * @return results The return data of the executed contract call.
     */
    function executeBatch(Execution[] calldata executions)
        external
        payable
        returns (bytes[] memory results);

    /**
     *
     * @dev Executes a transaction on behalf of the account.
     *         This function is intended to be called by an Executor module.
     * @dev This function MUST revert if the call fails.
     * @dev MSA MUST implement this function signature. If functionality should not be supported, revert "Unsupported"!
     * @param target The address of the contract to call.
     * @param value The value in wei to be sent to the contract.
     * @param callData The call data to be sent to the contract.
     * @return result The return data of the executed contract call.
     */
    function executeFromExecutor(
        address target,
        uint256 value,
        bytes calldata callData
    )
        external
        payable
        returns (bytes memory);

    /**
     *
     * @dev Executes a transaction via delegatecall on behalf of the account.
     *         This function is intended to be called by an Executor module.
     *
     * @dev This function MUST revert if the call fails.
     * @dev MSA MUST implement this function signature. If functionality should not be supported, revert "Unsupported"!
     * @param executions An array of struct Execution (address target, uint value, bytes callData)
     * @return results The return data of the executed contract call.
     */
    function executeBatchFromExecutor(Execution[] calldata executions)
        external
        payable
        returns (bytes[] memory results);
}
/**
 * @dev implementing delegatecall execution on a smart account must be considered carefully and is not recommended in most cases
 */

interface IExecutionUnsafe {
    /**
     * Executes a Delegatecall on behalf of the account.
     * MUST execute a `delegatecall` to the target with the provided data
     * MUST allow ERC-4337 Entrypoint to be the sender and MAY allow `msg.sender == address(this)`
     * MUST revert if the call was not successful
     * @dev Executes a transaction via delegatecall on behalf of the account.
     *         This function is intended to be called by ERC-4337 EntryPoint.sol
     * @dev This function MUST revert if the call fails.
     * @dev MSA MUST implement this function signature. If functionality should not be supported, revert "Unsupported"!
     * @param target The address of the contract to call.
     * @param callData The call data to be sent to the contract.
     * @return result The return data of the executed contract call.
     */
    function executeDelegateCall(
        address target,
        bytes calldata callData
    )
        external
        payable
        returns (bytes memory result);

    /**
     * Executes a Delegatecall on behalf of the account, triggered by an Executor Module.
     * MUST execute a `delegatecall` to the target with the provided data and value
     * MUST only allow enabled executors to call this function
     * MUST revert if the call was not successful
     * @dev Executes a transaction via delegatecall on behalf of the account.
     *         This function is intended to be called by an Executor module.
     * @dev This function MUST revert if the call fails.
     * @dev MSA MUST implement this function signature. If functionality should not be supported, revert "Unsupported"!
     * @param target The address of the contract to call.
     * @param callData The call data to be sent to the contract.
     * @return result The return data of the executed contract call.
     */
    function executeDelegateCallFromExecutor(
        address target,
        bytes memory callData
    )
        external
        payable // gas bad
        returns (bytes memory result);
}

/**
 * @dev Configuration Interface of the minimal Modular Smart Account standard
 */
interface IAccountConfig {
    event EnableValidator(address module);
    event DisableValidator(address module);

    event EnableExecutor(address module);
    event DisableExecutor(address module);

    /////////////////////////////////////////////////////
    //  Validator Modules
    ////////////////////////////////////////////////////
    /**
     * @dev Enables a Validator module on the account.
     * @dev Implement Authorization control of your chosing
     * @param validator The address of the Validator module to enable.
     * @param data any abi encoded further paramters needed
     */
    function installValidator(address validator, bytes calldata data) external;

    /**
     * @dev Disables a Validator Module on the account.
     * @dev Implement Authorization control of your chosing
     * @param validator The address of the Validator module to enable.
     * @param data any abi encoded further paramters needed
     */
    function uninstallValidator(address validator, bytes calldata data) external;

    /**
     * @dev checks if specific validator module is enabled on the account
     * @param validator The address of the Validator module to enable.
     * returns bool if validator is enabled
     */
    function isValidatorEnabled(address validator) external view returns (bool);
    /////////////////////////////////////////////////////
    //  Executor Modules
    ////////////////////////////////////////////////////

    /**
     * @dev Enables a Executor module on the account.
     * @dev Implement Authorization control of your chosing
     * @param executor The address of the Validator module to enable.
     * @param data any abi encoded further paramters needed
     */
    function installExecutor(address executor, bytes calldata data) external;

    /**
     * @dev Disable a Executor module on the account.
     * @dev Implement Authorization control of your chosing
     * @param executor The address of the Validator module to enable.
     * @param data any abi encoded further paramters needed
     */
    function uninstallExecutor(address executor, bytes calldata data) external;

    /**
     * @dev checks if specific executor module is enabled on the account
     * @param executor The address of the Executort module
     * returns bool if executor is enabled
     */
    function isExecutorEnabled(address executor) external view returns (bool);
    /////////////////////////////////////////////////////
    //  Fallback Modules
    ////////////////////////////////////////////////////
    /**
     * @dev Enables a Fallback module on the account.
     * @dev Implement Authorization control of your chosing
     */
    function enableFallback(address fallbackHandler, bytes calldata data) external;
    /**
     * @dev uninstallExecutor
     *
     */
    function disableFallback(address fallbackHandler, bytes calldata data) external;
    /**
     * @dev checks if specific fallback handler is enabled on the account
     * @param fallbackHandler The address of the fallback handler module
     * returns bool if fallbackhandler is enabled
     */
    function isFallbackEnabled(address fallbackHandler) external view returns (bool);
}

/**
 * @dev Configuration Interface of the minimal Modular Smart Account Hook extention standard
 */
interface IAccountConfig_Hook {
    event EnableHook(address module);
    event DisableHook(address module);
    /////////////////////////////////////////////////////
    //  Hook Modules
    ////////////////////////////////////////////////////

    /**
     * @dev Enables a Hook module on the account.
     * @dev Implement Authorization control of your chosing
     * @param hook The address of the Hook module to enable.
     * @param data any abi encoded further paramters needed
     */
    function installHook(address hook, bytes calldata data) external;

    /**
     * @dev Disable a Hook module on the account.
     * @dev Implement Authorization control of your chosing
     * @param hook The address of the hook module to enable.
     * @param data any abi encoded further paramters needed
     */
    function uninstallHook(address hook, bytes calldata data) external;

    /**
     * @dev checks if specific hook module is enabled on the account
     * @param hook The address of the Executort module to enable.
     * returns bool if hook is enabled
     */
    function isHookEnabled(address hook) external view returns (bool);
}

interface IMSA is IExecution, IExecutionUnsafe, IAccountConfig {
    /////////////////////////////////////////////////////
    //  Account Initialization
    ////////////////////////////////////////////////////

    /**
     * @dev initializes a MSA
     * @dev implement checks  that account can only be initialized once
     * @param data abi encoded init params
     */
    function initializeAccount(bytes calldata data) external;
}
