// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IOffChainEntityRegistry} from "./IOffChainEntityRegistry.sol";
import {IVerifier} from "./IVerifier.sol";

/// @title OffChainEntityRegistry — Reference Implementation
/// @notice Minimal implementation of ERC-XXXX. Production deployments should
///         add appropriate access control to setVerifier().
contract OffChainEntityRegistry is IOffChainEntityRegistry {
    address public admin;

    mapping(bytes32 => address) public verifiers;   // namespaceKey => verifier
    mapping(bytes32 => address) public owners;       // id => owner
    mapping(bytes32 => bytes32) public aliases;      // id => primaryId

    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }

    constructor(address admin_) {
        admin = admin_;
    }

    // -- Identifier helpers --------------------------------------------------

    function toId(string calldata namespace, string calldata canonicalString) public pure returns (bytes32) {
        _requireValidNamespace(namespace);
        return keccak256(abi.encode(namespace, canonicalString));
    }

    function canonicalOf(bytes32 id) public view returns (bytes32) {
        bytes32 primary = aliases[id];
        return primary == bytes32(0) ? id : primary;
    }

    function ownerOf(bytes32 id) public view returns (address) {
        return owners[canonicalOf(id)];
    }

    // -- Registration --------------------------------------------------------

    function claim(
        string calldata namespace,
        string calldata canonicalString,
        bytes calldata proof
    ) external {
        bytes32 id = toId(namespace, canonicalString);
        require(ownerOf(id) == address(0), "already claimed");

        address verifier = verifiers[keccak256(bytes(namespace))];
        require(verifier != address(0), "no verifier");
        require(IVerifier(verifier).verify(id, msg.sender, proof), "invalid proof");

        if (aliases[id] != bytes32(0)) {
            delete aliases[id];
        }

        owners[id] = msg.sender;
        emit Claimed(id, namespace, canonicalString, msg.sender);
    }

    function revoke(
        string calldata namespace,
        string calldata canonicalString
    ) external {
        bytes32 id = toId(namespace, canonicalString);
        require(aliases[id] == bytes32(0), "cannot revoke alias");
        require(owners[id] == msg.sender, "not owner");

        address previous = owners[id];
        delete owners[id];
        emit Revoked(id, namespace, canonicalString, previous);
    }

    // -- Linking -------------------------------------------------------------

    function linkIds(bytes32 primaryId, bytes32[] calldata aliasIds) external {
        require(owners[primaryId] == msg.sender, "not owner of primary");
        require(aliases[primaryId] == bytes32(0), "primary is an alias");

        for (uint256 i = 0; i < aliasIds.length; i++) {
            bytes32 aliasId = aliasIds[i];
            require(aliasId != primaryId, "cannot self-link");
            require(owners[aliasId] == msg.sender, "not owner of alias");
            require(aliases[aliasId] == bytes32(0), "already linked");

            aliases[aliasId] = primaryId;
            delete owners[aliasId];
            emit Linked(aliasId, primaryId);
        }
    }

    function unlinkIds(bytes32 primaryId, bytes32[] calldata aliasIds) external {
        require(owners[primaryId] == msg.sender, "not owner of primary");

        for (uint256 i = 0; i < aliasIds.length; i++) {
            bytes32 aliasId = aliasIds[i];
            require(aliases[aliasId] == primaryId, "not alias of primary");

            delete aliases[aliasId];
            owners[aliasId] = msg.sender;
            emit Unlinked(aliasId, primaryId);
        }
    }

    // -- Admin ---------------------------------------------------------------

    function setVerifier(string calldata namespace, address verifier) external onlyAdmin {
        _requireValidNamespace(namespace);
        bytes32 key = keccak256(bytes(namespace));
        verifiers[key] = verifier;
        emit VerifierUpdated(key, namespace, verifier);
    }

    function _requireValidNamespace(string calldata namespace) internal pure {
        bytes memory ns = bytes(namespace);
        require(ns.length != 0, "empty namespace");

        for (uint256 i = 0; i < ns.length; i++) {
            bytes1 c = ns[i];
            bool isDigit = c >= 0x30 && c <= 0x39;
            bool isLower = c >= 0x61 && c <= 0x7A;
            bool isHyphen = c == 0x2D;
            require(isDigit || isLower || isHyphen, "invalid namespace");
        }
    }
}
