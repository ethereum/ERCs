// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ILaunchDirectory} from "./ILaunchDirectory.sol";

/// @title Reference launch directory.
/// @notice One instance per chain. Permissionless to list, because a directory
///         that can refuse to list is a censorship point: a launch that cannot
///         be listed also cannot be reported against.
contract LaunchDirectory is ILaunchDirectory {
    struct Record {
        address token;
        address deployer;
        address escrow;
        address venue;
        bool    listed;
    }

    mapping(bytes32 => Record)    internal _records;
    mapping(address => bytes32[]) internal _byToken;
    mapping(address => bytes32[]) internal _byDeployer;

    /// @notice Recompute the canonical identifier for a launch.
    /// @dev Binding `block.chainid` stops an identifier minted on one chain from
    ///      colliding with, or being replayed against, a launch on another.
    function deriveLaunchId(
        address escrow,
        address token,
        address deployer,
        uint256 nonce
    ) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, escrow, token, deployer, nonce));
    }

    /// @param nonce the escrow's launch counter, so the identifier can be
    ///        recomputed and checked against the caller
    /// @dev Listing is permissionless in that no allowlist governs it, but the
    ///      identifier commits to the escrow that minted it. Recomputing the
    ///      derivation with `msg.sender` is what makes that binding real:
    ///      without it, anyone can compute a launch's future identifier from
    ///      public inputs and squat it, permanently blocking the registration
    ///      it belongs to and misattributing the record.
    function list(bytes32 launchId, address token, address deployer, address venue, uint256 nonce)
        external
    {
        require(!_records[launchId].listed, "already listed");
        require(
            launchId == deriveLaunchId(msg.sender, token, deployer, nonce),
            "identifier does not commit to caller"
        );
        _records[launchId] = Record({
            token: token,
            deployer: deployer,
            escrow: msg.sender,
            venue: venue,
            listed: true
        });

        _byToken[token].push(launchId);
        _byDeployer[deployer].push(launchId);

        emit LaunchListed(launchId, token, deployer, msg.sender, venue);
    }

    function launchesOf(address token) external view returns (bytes32[] memory) {
        return _byToken[token];
    }

    function launchesBy(address deployer) external view returns (bytes32[] memory) {
        return _byDeployer[deployer];
    }

    function escrowOf(bytes32 id)   external view returns (address) { return _records[id].escrow; }
    function venueOf(bytes32 id)    external view returns (address) { return _records[id].venue; }
    function deployerOf(bytes32 id) external view returns (address) { return _records[id].deployer; }
    function tokenOf(bytes32 id)    external view returns (address) { return _records[id].token; }

    function isListed(bytes32 id) external view returns (bool) { return _records[id].listed; }
}
