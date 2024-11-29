// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title ERC-7818 interface
 * @dev Interface for adding expirable functionality to ERC20 tokens.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC7818 is IERC20 {
    /**
     * @dev Enum represents the types of `epoch` that can be used.
     * @notice The implementing contract may use one of these types to define how the `epoch` is measured.
     */
    enum EPOCH_TYPE {
        BLOCKS_BASED, // measured in the number of blocks (e.g., 1000 blocks)
        TIME_BASED // measured in seconds (UNIX time) (e.g., 1000 seconds)
    }

    /**
     * @dev Retrieves the balance of a specific `epoch` owned by an account.
     * @param account The address of the account.
     * @param epoch The `epoch for which the balance is checked.
     * @return uint256 The balance of the specified `epoch`.
     * @notice "MUST" return 0 if the specified `epoch` is expired.
     */
    function balanceOfAtEpoch(
        address account,
        uint256 epoch
    ) external view returns (uint256);

    /**
     * @dev Retrieves the latest epoch currently tracked by the contract.
     * @return uint256 The latest epoch of the contract.
     */
    function currentEpoch() external view returns (uint256);

    /**
     * @dev Retrieves the duration of a single epoch.
     * @return uint256 The duration of a single epoch.
     * @notice The unit of the epoch length is determined by the `validityPeriodType()` function.
     */
    function epochLength() external view returns (uint256);

    /**
     * @dev Returns the type of the epoch.
     * @return EPOCH_TYPE Enum value indicating the unit of epoch.
     */
    function epochType() external view returns (EPOCH_TYPE);

    /**
     * @dev Returns the fixed validity period for tokens, in epochs.
     * @return uint256 Duration tokens remain valid, measured in epochs.
     * @notice The duration aligns with the unit defined by `epochType()` (blocks or seconds).
     */
    function validityPeriod() external view returns (uint256);

    /**
     * @dev Checks whether a specific `epoch` is expired.
     * @param epoch The `epoch` to check.
     * @return bool True if the token is expired, false otherwise.
     */
    function isEpochExpired(uint256 epoch) external view returns (bool);

    /**
     * @dev Transfers a specific `epoch` and value to a recipient.
     * @param to The recipient address.
     * @param epoch The `epoch` for the transfer.
     * @param value The amount to transfer.
     * @return bool True if the transfer succeeded, otherwise false.
     */
    function transferAtEpoch(
        address to,
        uint256 epoch,
        uint256 value
    ) external returns (bool);

    /**
     * @dev Transfers a specific `epoch` and value from one account to another.
     * @param from The sender's address.
     * @param to The recipient's address.
     * @param epoch The `epoch` for the transfer.
     * @param value The amount to transfer.
     * @return bool True if the transfer succeeded, otherwise false.
     */
    function transferFromAtEpoch(
        address from,
        address to,
        uint256 epoch,
        uint256 value
    ) external returns (bool);
}
