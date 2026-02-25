// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

/// @title ERC-7858 Epoch

import {IERC7858} from "./IERC7858.sol";

interface IERC7858Epoch is IERC7858 {
    /**
     * @dev Retrieves the balance of a specific `epoch` owned by an account.
     * @param epoch The `epoch for which the balance is checked.
     * @param account The address of the account.
     * @return uint256 The balance of the specified `epoch`.
     * @notice "MUST" return 0 if the specified `epoch` is expired.
     */
    function unexpiredBalanceOfAtEpoch(
        uint256 epoch,
        address account
    ) external view returns (uint256);

    /**
     * @dev Retrieves the current epoch of the contract.
     * @return uint256 The current epoch of the token contract,
     * often used for determining active/expired states.
     */
    function currentEpoch() external view returns (uint256);

    /**
     * @dev Retrieves the duration of a single epoch.
     * @return uint256 The duration of a single epoch.
     * @notice The unit of the epoch length is determined by the `validityPeriodType` function.
     */
    function epochLength() external view returns (uint256);

    /**
     * @dev Checks whether a specific `epoch` is expired.
     * @param epoch The `epoch` to check.
     * @return bool True if the token is expired, false otherwise.
     * @notice Implementing contracts "MUST" define and document the logic for determining expiration,
     * typically by comparing the latest epoch with the given `epoch` value,
     * based on the `EXPIRY_TYPE` measurement (e.g., block count or time duration).
     */
    function isEpochExpired(uint256 epoch) external view returns (bool);

    /**
     * @dev Retrieves the balance of unexpired tokens owned by an account.
     * @param account The address of the account.
     * @return uint256 The amount of unexpired tokens owned by an account.
     */
    function unexpiredBalanceOf(
        address account
    ) external view returns (uint256);

    /**
     * @dev Retrieves the validity duration of each token.
     * @return uint256 The validity duration of each token in `epoch` unit.
     */
    function validityDuration() external view returns (uint256);
}
