// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title Per-chain resolution from a token to its launches.
/// @notice Without this, `launchId` is unobtainable: a wallet holding only a
///         token address could not consult a guard before buying, which is the
///         one moment the guard exists for.
interface ILaunchDirectory {
    event LaunchListed(
        bytes32 indexed launchId,
        address indexed token,
        address indexed deployer,
        address escrow,
        address venue
    );

    /// @notice List a launch. The identifier MUST recompute to the caller.
    /// @dev Implementations MUST verify
    ///      `launchId == keccak256(abi.encode(chainid, msg.sender, token, deployer, nonce))`.
    ///      Without that check the identifier is predictable from public inputs
    ///      and can be squatted before the launch is registered.
    function list(
        bytes32 launchId,
        address token,
        address deployer,
        address venue,
        uint256 nonce
    ) external;

    /// @notice Every launch recorded for a token, oldest first.
    function launchesOf(address token) external view returns (bytes32[] memory);

    /// @notice Every launch by a deployer, oldest first. Supports serial-deployer analysis.
    function launchesBy(address deployer) external view returns (bytes32[] memory);

    function escrowOf(bytes32 launchId)   external view returns (address);
    function venueOf(bytes32 launchId)    external view returns (address);
    function deployerOf(bytes32 launchId) external view returns (address);
    function tokenOf(bytes32 launchId)    external view returns (address);
}
