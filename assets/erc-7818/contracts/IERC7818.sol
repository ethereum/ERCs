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
     * @param epoch The `epoch for which the balance is checked.
     * @param account The address of the account.
     * @return uint256 The balance of the specified `epoch`.
     * @notice "MUST" return 0 if the specified `epoch` is expired.
     */
    function balanceOfAtEpoch(
        uint256 epoch,
        address account
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
     * @return EPOCH_TYPE  Enum value indicating the unit of an epoch.
     */
    function epochType() external view returns (EPOCH_TYPE);

    /**
     * @dev Retrieves the validity duration in `epoch` counts.
     * @return uint256 The validity duration in `epoch` counts.
     */
    function validityDuration() external view returns (uint256);

    /**
     * @dev Checks whether a specific `epoch` is expired.
     * @param epoch The `epoch` to check.
     * @return bool True if the token is expired, false otherwise.
     * @notice Implementing contracts "MUST" define and document the logic for determining expiration,
     * typically by comparing the latest epoch with the given `epoch` value,
     * based on the `EPOCH_TYPE` measurement (e.g., block count or time duration).
     */
    function isEpochExpired(uint256 epoch) external view returns (bool);

    /**
     * @dev Transfers a specific `epoch` and value to a recipient.
     * @param epoch The `epoch` for the transfer.
     * @param to The recipient address.
     * @param value The amount to transfer.
     * @return bool True if the transfer succeeded, otherwise false.
     */
    function transferAtEpoch(
        uint256 epoch,
        address to,
        uint256 value
    ) external returns (bool);

    /**
     * @dev Transfers a specific `epoch` and value from one account to another.
     * @param epoch The `epoch` for the transfer.
     * @param from The sender's address.
     * @param to The recipient's address.
     * @param value The amount to transfer.
     * @return bool True if the transfer succeeded, otherwise false.
     */
    function transferFromAtEpoch(
        uint256 epoch,
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}
