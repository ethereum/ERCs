// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @dev Minimal stand-in for an ERC-8004 Identity Registry: just enough ERC-721 + agentWallet
///      surface for AID tests. Not a conforming ERC-8004 implementation.
contract MockIdentityRegistry8004 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue);

    uint256 public nextId = 1;
    mapping(uint256 => address) private _owner;
    mapping(uint256 => address) private _wallet;

    function register() external returns (uint256 agentId) {
        agentId = nextId++;
        _owner[agentId] = msg.sender;
        emit Transfer(address(0), msg.sender, agentId);
    }

    function ownerOf(uint256 agentId) external view returns (address) {
        address o = _owner[agentId];
        require(o != address(0), "ERC721: invalid token ID");
        return o;
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        return _wallet[agentId];
    }

    /// @dev test-only: no signature check (real ERC-8004 requires the new wallet's signature)
    function setAgentWallet(uint256 agentId, address wallet) external {
        require(_owner[agentId] == msg.sender, "not owner");
        _wallet[agentId] = wallet;
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encode(wallet));
    }

    /// @dev like ERC-8004: a transfer clears the agent wallet
    function transfer(uint256 agentId, address to) external {
        require(_owner[agentId] == msg.sender, "not owner");
        _owner[agentId] = to;
        delete _wallet[agentId];
        emit Transfer(msg.sender, to, agentId);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encode(address(0)));
    }

    function burn(uint256 agentId) external {
        require(_owner[agentId] == msg.sender, "not owner");
        delete _owner[agentId];
        delete _wallet[agentId];
        emit Transfer(msg.sender, address(0), agentId);
    }
}

/// @dev EIP-1271 wallet mock: accepts any signature whose recovered signer is `owner`.
contract MockERC1271Wallet {
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function isValidSignature(bytes32 hash, bytes memory sig) external view returns (bytes4) {
        if (sig.length != 65) return 0xffffffff;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        return ecrecover(hash, v, r, s) == owner ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}
