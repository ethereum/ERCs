// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IAccountFactory
/// @notice Deploys deterministic identity account proxies for identifier-based pre-funding.
interface IAccountFactory {
    event AccountDeployed(bytes32 indexed id, address account);

    /// @notice Returns the deterministic address for the account of `id`.
    ///         Pure computation — the address must not change on implementation upgrade.
    function predictAddress(bytes32 id) external view returns (address);

    /// @notice Deploys the account proxy for `id`. Reverts if already deployed.
    function deployAccount(bytes32 id) external returns (address account);
}
