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
    function etch(address, bytes calldata) external;
    function mockCall(address, bytes calldata, bytes calldata) external;
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

/// ArbSys as an Arbitrum chain has it at address(100): the chain's own block number, which `block.number` is not there.
/// The tests etch this code at address(100) and set the number in its storage.
contract MockArbSys {
    uint256 private _number;

    function setArbBlockNumber(uint256 number) external {
        _number = number;
    }

    function arbBlockNumber() external view returns (uint256) {
        return _number;
    }
}

/// The EIP-2935 history contract's read side: 32-byte block number in, 32-byte hash out, revert when it has none.
/// The tests etch this code at 0x0000F90827F1C53a10cb7A02335B175320002935.
contract MockBlockHistory {
    mapping(uint256 => bytes32) private _hashes;

    function setHash(uint256 number, bytes32 hash) external {
        _hashes[number] = hash;
    }

    fallback(bytes calldata input) external returns (bytes memory) {
        require(input.length == 32, "input");
        bytes32 h = _hashes[abi.decode(input, (uint256))];
        require(h != bytes32(0), "out of range");
        return abi.encode(h);
    }
}
