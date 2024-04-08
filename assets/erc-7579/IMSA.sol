// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

interface IERC7579Account {
    // MUST be emitted when a module is installed
    event ModuleInstalled(uint256 moduleTypeId, address module);

    // MUST be emitted when a module is uninstalled
    event ModuleUninstalled(uint256 moduleTypeId, address module);

    /**
     * @dev Executes a transaction on behalf of the account.
     * @param mode The encoded execution mode of the transaction. See ModeLib.sol for details
     * @param executionCalldata The encoded execution call data
     *
     * MUST ensure adequate authorization control: e.g. onlyEntryPointOrSelf if used with ERC-4337
     * If a mode is requested that is not supported by the Account, it MUST revert
     */
    function execute(bytes32 mode, bytes calldata executionCalldata) external;

    /**
     * @dev Executes a transaction on behalf of the account.
     *         This function is intended to be called by Executor Modules
     * @param mode The encoded execution mode of the transaction. See ModeLib.sol for details
     * @param executionCalldata The encoded execution call data
     *
     * MUST ensure adequate authorization control: i.e. onlyExecutorModule
     * If a mode is requested that is not supported by the Account, it MUST revert
     */
    function executeFromExecutor(bytes32 mode, bytes calldata executionCalldata)
        external
        returns (bytes[] memory returnData);

    /**
     * @dev ERC-1271 isValidSignature
     *         This function is intended to be used to validate a smart account signature
     * and may forward the call to a validator module
     * @param hash The hash of the data that is signed
     * @param data The data that is signed
     *
     * MAY forward the call to a validator module
     * The validator module MUST be called with isValidSignatureWithSender(address sender, bytes32 hash, bytes signature)
     * with sender being the msg.sender of this function
     * MUST sanitize the data parameter to before forwarding it to the validator module
     */
    function isValidSignature(bytes32 hash, bytes calldata data) external view returns (bytes4);

    /**
     * @dev Returns the account id of the smart account
     * @return accountImplementationId the account id of the smart account
     *
     * MUST return a non-empty string
     * The accountId SHOULD be structured like so:
     *        "vendorname.accountname.semver"
     * The id SHOULD be unique across all smart accounts
     */
    function accountId() external view returns (string memory accountImplementationId);

    /**
     * @dev Function to check if the account supports a certain execution mode (see above)
     * @param encodedMode the encoded mode
     *
     * MUST return true if the account supports the mode and false otherwise
     */
    function supportsExecutionMode(bytes32 encodedMode) external view returns (bool);

    /**
     * @dev Function to check if the account supports a certain module typeId
     * @param moduleTypeId the module type ID according to the ERC-7579 spec
     *
     * MUST return true if the account supports the module type and false otherwise
     */
    function supportsModule(uint256 moduleTypeId) external view returns (bool);

    /**
     * @dev Installs a Module of a certain type on the smart account
     * @param moduleTypeId the module type ID according to the ERC-7579 spec
     * @param module the module address
     * @param initData arbitrary data that may be required on the module during `onInstall`
     * initialization.
     *
     * MUST implement authorization control
     * MUST call `onInstall` on the module with the `initData` parameter if provided
     * MUST emit ModuleInstalled event
     * MUST revert if the module is already installed or the initialization on the module failed
     */
    function installModule(uint256 moduleTypeId, address module, bytes calldata initData) external;

    /**
     * @dev Uninstalls a Module of a certain type on the smart account
     * @param moduleTypeId the module type ID according the ERC-7579 spec
     * @param module the module address
     * @param deInitData arbitrary data that may be required on the module during `onInstall`
     * initialization.
     *
     * MUST implement authorization control
     * MUST call `onUninstall` on the module with the `deInitData` parameter if provided
     * MUST emit ModuleUninstalled event
     * MUST revert if the module is not installed or the deInitialization on the module failed
     */
    function uninstallModule(uint256 moduleTypeId, address module, bytes calldata deInitData) external;

    /**
     * @dev Returns whether a module is installed on the smart account
     * @param moduleTypeId the module type ID according the ERC-7579 spec
     * @param module the module address
     * @param additionalContext arbitrary data that may be required to determine if the module is installed
     *
     * MUST return true if the module is installed and false otherwise
     */
    function isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata additionalContext)
        external
        view
        returns (bool);
}
