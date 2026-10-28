// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// Minimal Foundry cheatcode interface, so the tests need no external library.
interface Vm {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function roll(uint256) external;
    function warp(uint256) external;
    function chainId(uint256) external;
    function expectRevert() external;
    function expectRevert(bytes4) external;
    function expectRevert(bytes calldata) external;
    function expectEmit(bool, bool, bool, bool) external;
    function expectEmit(bool, bool, bool, bool, address) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);

    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }
}

/// The part of an ERC-8376 directory this proposal reads.
contract MockDirectory {
    mapping(bytes32 => address) public tokenOf;

    function list(bytes32 launchId, address token) external {
        tokenOf[launchId] = token;
    }
}

/// An ERC-8004-style identity registry: ERC-721 ownership plus an agent wallet.
contract MockIdentityRegistry {
    mapping(uint256 => address) private _owner;
    mapping(uint256 => address) private _wallet;

    function mint(uint256 agentId, address owner) external {
        _owner[agentId] = owner;
        _wallet[agentId] = owner;
    }

    function transfer(uint256 agentId, address to) external {
        _owner[agentId] = to;
        _wallet[agentId] = address(0);
    }

    function setAgentWallet(uint256 agentId, address wallet) external {
        _wallet[agentId] = wallet;
    }

    function ownerOf(uint256 agentId) external view returns (address) {
        address o = _owner[agentId];
        require(o != address(0), "nonexistent");
        return o;
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        return _wallet[agentId];
    }
}

/// A plain ERC-721-style registry without getAgentWallet.
contract MockPlainRegistry {
    mapping(uint256 => address) private _owner;

    function mint(uint256 agentId, address owner) external {
        _owner[agentId] = owner;
    }

    function ownerOf(uint256 agentId) external view returns (address) {
        address o = _owner[agentId];
        require(o != address(0), "nonexistent");
        return o;
    }
}
